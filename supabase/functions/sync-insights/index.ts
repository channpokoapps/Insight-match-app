// sync-insights/index.ts
// 日次バッチのディスパッチャ（ADR-0004）。
//
// 役割:
//   1. 対象となる SNS 連携を洗い出して sync_jobs / sync_job_items を作る
//   2. チャンクに分けて sync-worker を並列度 5 で起動する
//   3. 実処理は行わない（1リクエストの実行時間上限に収めるため）
//
// 呼び出し元: pg_cron（private.invoke_edge_function 経由）
// private スキーマへは直接 SQL で接続する（_shared/db.ts 参照）。

import { assertServiceRole, safeLog } from "../_shared/client.ts";
import { sql } from "../_shared/db.ts";

const CHUNK_SIZE = 50;
const CONCURRENCY = 5;

interface Payload {
  trigger: "daily" | "retry" | "manual";
}

Deno.serve(async (req) => {
  try {
    assertServiceRole(req);
  } catch (res) {
    return res as Response;
  }
  try {
    return await dispatch(req);
  } catch (e) {
    // 数値・トークンはここに到達しない（エラーコード/メッセージのみ）
    const msg = e instanceof Error ? e.message : JSON.stringify(e);
    safeLog("sync_dispatch_error", { error_code: msg.slice(0, 120) });
    return Response.json({ ok: false, error: msg }, { status: 500 });
  }
});

async function dispatch(req: Request): Promise<Response> {
  const payload: Payload = await req.json().catch(() => ({ trigger: "manual" as const }));
  const db = sql();

  // 対象の抽出。retry は前回失敗時の attempt を引き継ぐ（バックオフと
  // 最大試行回数を新ジョブでも継続させるため）。
  let targets: { credential_id: string; attempt: number }[] = [];

  if (payload.trigger === "retry") {
    const rows: { id: string; credential_id: string; attempt: number }[] = await db`
      select id, credential_id, attempt
        from private.sync_job_items
       where status = 'retry' and next_retry_at <= now()
       limit 1000`;
    targets = rows.map((r) => ({ credential_id: r.credential_id, attempt: r.attempt ?? 0 }));
    // 旧アイテムを終端化する。retry のまま残すと 15 分ごとに再投入され続け、
    // attempt もリセットされて無限リトライになるため。
    if (rows.length > 0) {
      await db`
        update private.sync_job_items
           set status = 'failed', next_retry_at = null
         where id = any(${rows.map((r) => r.id)}::uuid[])`;
    }
  } else {
    const rows: { id: string }[] = await db`
      select id from private.social_credentials where status = 'active' limit 10000`;
    targets = rows.map((r) => ({ credential_id: r.id, attempt: 0 }));
  }

  if (targets.length === 0) {
    // 対象 0 件でも daily はジョブ行を残す。死活監視の記録と、
    // Supabase Free の「7日間非アクティブで一時停止」の回避を兼ねる。
    if (payload.trigger === "daily") {
      await db`insert into private.sync_jobs (target_count, finished_at)
               values (0, now())`;
    }
    safeLog("sync_dispatch_empty", { status: payload.trigger });
    return Response.json({ ok: true, target_count: 0, trigger: payload.trigger });
  }

  const [job]: { id: string }[] = await db`
    insert into private.sync_jobs (target_count)
    values (${targets.length}) returning id`;

  const items = targets.map((t) => ({
    job_id: job.id,
    credential_id: t.credential_id,
    status: "pending",
    attempt: t.attempt,
  }));
  for (let i = 0; i < items.length; i += 500) {
    await db`insert into private.sync_job_items ${db(items.slice(i, i + 500))}`;
  }
  const credentialIds = targets.map((t) => t.credential_id);

  safeLog("sync_dispatch_start", { job_id: job.id, count: credentialIds.length });

  // ワーカー起動（結果は待たない。ワーカー側が自分の担当分を完了させる）
  const chunks: string[][] = [];
  for (let i = 0; i < credentialIds.length; i += CHUNK_SIZE) {
    chunks.push(credentialIds.slice(i, i + CHUNK_SIZE));
  }

  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/sync-worker`;
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
  };

  for (let i = 0; i < chunks.length; i += CONCURRENCY) {
    await Promise.allSettled(
      chunks.slice(i, i + CONCURRENCY).map((chunk) =>
        fetch(url, {
          method: "POST",
          headers,
          body: JSON.stringify({ job_id: job.id, credential_ids: chunk }),
        })
      ),
    );
  }

  return Response.json({ ok: true, job_id: job.id, target_count: credentialIds.length });
}
