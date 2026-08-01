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

  // 対象の抽出
  let credentialIds: string[] = [];

  if (payload.trigger === "retry") {
    const { data, error } = await db
      .from("sync_job_items")
      .select("credential_id")
      .eq("status", "retry")
      .lte("next_retry_at", new Date().toISOString())
      .limit(1000);
    if (error) throw error;
    credentialIds = (data ?? []).map((r) => r.credential_id as string);
  } else {
    const { data, error } = await db
      .from("social_credentials")
      .select("id")
      .eq("status", "active")
      .limit(10000);
    if (error) throw error;
    credentialIds = (data ?? []).map((r) => r.id as string);
  }

  if (credentialIds.length === 0) {
    safeLog("sync_dispatch_empty", { status: payload.trigger });
    return Response.json({ ok: true, target_count: 0 });
  }

  const { data: job, error: jobError } = await db
    .from("sync_jobs")
    .insert({ target_count: credentialIds.length })
    .select("id")
    .single();
  if (jobError) throw jobError;

  const items = credentialIds.map((id) => ({
    job_id: job.id,
    credential_id: id,
    status: "pending",
  }));
  for (let i = 0; i < items.length; i += 500) {
    const { error } = await db.from("sync_job_items").insert(items.slice(i, i + 500));
    if (error) throw error;
  }

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
