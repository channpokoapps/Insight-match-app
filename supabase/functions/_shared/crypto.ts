// _shared/crypto.ts
// SNS アクセストークンの暗号化・復号と、OAuth state の署名（ADR-0006）。
//
// 注意:
//   - 鍵は Supabase Secrets の TOKEN_ENCRYPTION_KEY（32 バイトの base64）からのみ読む。
//   - 平文トークン・鍵をログに出さない（AGENTS.md R-7）。
//   - 保存形式は bytea 列に合わせた \x 始まりの 16 進文字列（IV 12 バイト || 暗号文）。

const IV_LENGTH = 12;

/** OAuth state の HMAC に使うドメイン分離プレフィックス。 */
const STATE_PREFIX = "meta-oauth-state|";

/** state の有効期間（ミリ秒）。認可画面での滞在を考慮して 10 分。 */
export const STATE_TTL_MS = 10 * 60 * 1000;

function rawKey(): ArrayBuffer {
  const encoded = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  if (!encoded) throw new Error("CONFIG_ERROR");
  const key = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  if (key.length !== 32) throw new Error("CONFIG_ERROR");
  return key.buffer as ArrayBuffer;
}

async function aesKey(usage: KeyUsage): Promise<CryptoKey> {
  return await crypto.subtle.importKey("raw", rawKey(), "AES-GCM", false, [usage]);
}

function toHex(bytes: Uint8Array): string {
  return "\\x" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function fromHexOrBase64(value: string): Uint8Array {
  if (value.startsWith("\\x")) {
    const hex = value.slice(2);
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
    }
    return bytes;
  }
  // 過去データ・テスト用の base64 も受け付ける
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}

/**
 * トークンを AES-256-GCM で暗号化し、bytea 列へ渡せる 16 進文字列を返す。
 */
export async function encryptToken(plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const key = await aesKey("encrypt");
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(plain),
  );
  const out = new Uint8Array(IV_LENGTH + cipher.byteLength);
  out.set(iv, 0);
  out.set(new Uint8Array(cipher), IV_LENGTH);
  return toHex(out);
}

/**
 * bytea 列から読んだ値（\x 16進、または base64）を復号する。
 */
export async function decryptToken(stored: string): Promise<string> {
  const raw = fromHexOrBase64(stored);
  const iv = raw.slice(0, IV_LENGTH);
  const data = raw.slice(IV_LENGTH);
  const key = await aesKey("decrypt");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, data);
  return new TextDecoder().decode(plain);
}

function base64UrlEncode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function base64UrlDecode(value: string): Uint8Array {
  const b64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function hmac(message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    rawKey(),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(STATE_PREFIX + message),
  );
  return new Uint8Array(sig);
}

/**
 * OAuth の state を発行する（CSRF 対策）。
 * 形式: base64url(user_id|有効期限ms|nonce) + "." + base64url(HMAC)
 */
export async function issueState(userId: string): Promise<string> {
  const nonce = base64UrlEncode(crypto.getRandomValues(new Uint8Array(16)));
  const payload = `${userId}|${Date.now() + STATE_TTL_MS}|${nonce}`;
  const sig = await hmac(payload);
  return `${base64UrlEncode(new TextEncoder().encode(payload))}.${base64UrlEncode(sig)}`;
}

/**
 * state を検証し、正当なら user_id を返す。不正・期限切れは null。
 */
export async function verifyState(state: string): Promise<string | null> {
  const dot = state.lastIndexOf(".");
  if (dot <= 0) return null;
  let payload: string;
  let givenSig: Uint8Array;
  try {
    payload = new TextDecoder().decode(base64UrlDecode(state.slice(0, dot)));
    givenSig = base64UrlDecode(state.slice(dot + 1));
  } catch {
    return null;
  }
  const expected = await hmac(payload);
  if (givenSig.length !== expected.length) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected[i] ^ givenSig[i];
  if (diff !== 0) return null;

  const [userId, expiresAt] = payload.split("|");
  if (!userId || !expiresAt || Date.now() > Number(expiresAt)) return null;
  return userId;
}
