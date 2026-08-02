// _shared/crypto_test.ts
// トークン暗号化と OAuth state 署名の検証（ADR-0006）。
// 実行: cd supabase/functions && deno task test

import { decryptToken, encryptToken, issueState, verifyState } from "./crypto.ts";

// テスト用の 32 バイト鍵（本番の鍵とは無関係な固定値）
Deno.env.set("TOKEN_ENCRYPTION_KEY", btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => i))));

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

Deno.test("暗号化して復号すると元のトークンに戻る", async () => {
  const plain = "EAAG-long-lived-token-1234567890";
  const stored = await encryptToken(plain);
  assert(stored.startsWith("\\x"), "bytea 向けの \\x 16進形式で返す");
  assert(!stored.includes(plain), "暗号文に平文が含まれない");
  assert(await decryptToken(stored) === plain, "ラウンドトリップで一致する");
});

Deno.test("同じ平文でも IV により毎回異なる暗号文になる", async () => {
  const a = await encryptToken("same-token");
  const b = await encryptToken("same-token");
  assert(a !== b, "IV がランダムであること");
});

Deno.test("改ざんされた暗号文は復号に失敗する", async () => {
  const stored = await encryptToken("token");
  const tampered = stored.slice(0, -2) + (stored.endsWith("00") ? "01" : "00");
  let failed = false;
  try {
    await decryptToken(tampered);
  } catch {
    failed = true;
  }
  assert(failed, "GCM の認証タグで改ざんを検出する");
});

Deno.test("state は正しい user_id を返し、改ざんは拒否される", async () => {
  const userId = "11111111-1111-1111-1111-111111111111";
  const state = await issueState(userId);
  assert(await verifyState(state) === userId, "正当な state は user_id を返す");
  assert(await verifyState(state + "x") === null, "署名改ざんは null");
  assert(await verifyState("garbage") === null, "形式不正は null");

  // ペイロード改ざん（別ユーザー ID にすり替え）も署名不一致で拒否される
  const otherPayload = btoa(`22222222-2222-2222-2222-222222222222|${Date.now() + 60000}|n`)
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  const sig = state.split(".")[1];
  assert(await verifyState(`${otherPayload}.${sig}`) === null, "ペイロード改ざんは null");
});
