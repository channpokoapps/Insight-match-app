// sync-insights/index.ts
// 日次バッチのディスパッチャ（ADR-0004）。
//
// 役割:
//   1. 対象となる SNS 連携を洗い出して sync_jobs / sync_job_items を作る
//   2. チャンクに分けて sync-worker を並列度 5 で起動する
//   3. 実処理は行わない（1リクエストの実行時間上限に収めるため）
//
// 呼び出し元: pg_cron（private.invoke_edge_function 経由）

import { createServiceClient, assertServiceRole, safeLog } from "../_shared/client.ts";

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

  const payload: Payload = await req.json().catch(() => ({ trigger: "manual" as const }));
  const db = createServiceClient();

  // 対象の抽出。retry は前回失敗時の attempt を引き継ぐ（バックオフと
  // 最大試行回数を新ジョブでも継続させるため）。
  let targets: { credential_id: string; attempt: number }[] = [];

  if (payload.trigger === "retry") {
    const { data, error } = await db
      .from("sync_job_items")
      .select("id, credential_id, attempt")
      .eq("status", "retry")
      .lte("next_retry_at", new Date().toISOString())
      .limit(1000);
    if (error) throw error;
    const rows = data ?? [];
    targets = rows.map((r) => ({
      credential_id: r.credential_id as string,
      attempt: (r.attempt as number) ?? 0,
    }));
    // 旧アイテムを終端化する。retry のまま残すと 15 分ごとに再投入され続け、
    // attempt もリセットされて無限リトライになるため。
    if (rows.length > 0) {
      const { error: closeError } = await db
        .from("sync_job_items")
        .update({ status: "failed", next_retry_at: null })
        .in("id", rows.map((r) => r.id as string));
      if (closeError) throw closeError;
    }
  } else {
    const { data, error } = await db
      .from("social_credentials")
      .select("id")
      .eq("status", "active")
      .limit(10000);
    if (error) throw error;
    targets = (data ?? []).map((r) => ({ credential_id: r.id as string, attempt: 0 }));
  }

  if (targets.length === 0) {
    // 対象 0 件でも daily はジョブ行を残す。死活監視の記録と、
    // Supabase Free の「7日間非アクティブで一時停止」の回避を兼ねる。
    if (payload.trigger === "daily") {
      await db
        .from("sync_jobs")
        .insert({ target_count: 0, finished_at: new Date().toISOString() });
    }
    safeLog("sync_dispatch_empty", { status: payload.trigger });
    return Response.json({ ok: true, target_count: 0 });
  }

  const { data: job, error: jobError } = await db
    .from("sync_jobs")
    .insert({ target_count: targets.length })
    .select("id")
    .single();
  if (jobError) throw jobError;

  const items = targets.map((t) => ({
    job_id: job.id,
    credential_id: t.credential_id,
    status: "pending",
    attempt: t.attempt,
  }));
  for (let i = 0; i < items.length; i += 500) {
    const { error } = await db.from("sync_job_items").insert(items.slice(i, i + 500));
    if (error) throw error;
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
});
