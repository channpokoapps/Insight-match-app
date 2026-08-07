#!/usr/bin/env node
// Google ログインに必要なコンソール設定を API から適用・確認するスクリプト。
//
// 手作業（Firebase コンソール / Supabase ダッシュボードのクリック）を置き換える
// ためのもの。`.github/workflows/setup_auth.yml` から呼ばれる想定で、必要な
// 資格情報は GitHub Secrets から環境変数として渡される。
//
// やること:
//   1. Firebase Authentication の Google プロバイダを有効化する。
//      クライアント ID には **Supabase に登録済みのウェブ クライアント ID**
//      (GOOGLE_WEB_CLIENT_ID) をそのまま使う。こうすると Google が発行する
//      ID トークンの `aud` が Supabase の Client ID と一致するため、
//      Supabase 側は追加設定なしで受け付けられる。
//   2. Firebase の「承認済みドメイン」に配信ホストが入っていることを確認し、
//      足りなければ追加する（プレビューチャンネル用）。
//   3. (任意) Supabase の Google プロバイダ設定を確認・是正する。
//      SUPABASE_ACCESS_TOKEN が無ければこの手順は飛ばす。
//
// 秘密情報は一切出力しない。クライアント ID は末尾のみ表示する。
//
// 使い方:
//   APPLY=true node scripts/setup_google_auth.mjs
//   APPLY=false ...  # 確認のみ（既定）。何も変更しない。

import { createSign } from 'node:crypto';

const APPLY = process.env.APPLY === 'true';
/** 未解決があるときに終了コード 1 で落とすか。確認だけの自動実行では false。 */
const FAIL_ON_UNRESOLVED = process.env.FAIL_ON_UNRESOLVED !== 'false';
const PREVIEW_DOMAIN = (process.env.PREVIEW_DOMAIN ?? '').trim();

/** 実行結果の行。最後にまとめて表示する。 */
const report = [];

/** 変更が必要なのに適用できなかったものがあれば 1 で終了する。 */
let unresolved = 0;

function log(step, status, detail) {
  report.push({ step, status, detail });
  console.log(`[${status}] ${step}: ${detail}`);
}

/** クライアント ID などの識別子を、照合できる程度に伏せて表示する。 */
function mask(value) {
  if (!value) return '(未設定)';
  return value.length <= 12 ? '***' : `***${value.slice(-12)}`;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(
      `${name} が未設定です。GitHub の Settings → Secrets and variables → Actions に登録してください。`,
    );
  }
  return value.trim();
}

// ---------------------------------------------------------------------------
// 設定値の取り出し
// ---------------------------------------------------------------------------

/** `FLUTTER_ENV_PROD`（env/prod.json の中身）から接続情報を取り出す。 */
function readAppEnv() {
  const raw = requireEnv('FLUTTER_ENV_PROD');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new Error(`FLUTTER_ENV_PROD が JSON として読めません: ${error.message}`);
  }
  const clientId = (parsed.GOOGLE_WEB_CLIENT_ID ?? '').trim();
  const supabaseUrl = (parsed.SUPABASE_URL ?? '').trim();
  if (!clientId) {
    throw new Error(
      'FLUTTER_ENV_PROD に GOOGLE_WEB_CLIENT_ID がありません（docs/manual_setup/supabase.md §4.2）。',
    );
  }
  return { clientId, supabaseUrl };
}

/** `https://<ref>.supabase.co` から プロジェクト ref を取り出す。 */
function supabaseRefOf(url) {
  if (!url) return null;
  const host = new URL(url).host;
  const ref = host.split('.')[0];
  return ref || null;
}

// ---------------------------------------------------------------------------
// Google のアクセストークン（サービスアカウントの JWT 交換）
// ---------------------------------------------------------------------------

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * サービスアカウント鍵から短命のアクセストークンを得る。
 *
 * gcloud を入れずに済ませるため、JWT bearer フローを直接実行する。
 */
async function accessTokenFrom(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${base64url(
    JSON.stringify(claims),
  )}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  const jwt = `${unsigned}.${signer.sign(serviceAccount.private_key, 'base64url')}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(
      `サービスアカウントの認証に失敗しました（${response.status}）: ${body.error_description ?? body.error ?? ''}`,
    );
  }
  return body.access_token;
}

/** Identity Toolkit Admin API を呼ぶ。 */
async function callIdentityToolkit(token, path, { method = 'GET', body } = {}) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/admin/v2/${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : {};
  return { ok: response.ok, status: response.status, body: parsed };
}

/** 権限不足かどうか。原因の案内を変えるために区別する。 */
function isPermissionDenied(result) {
  return result.status === 401 || result.status === 403;
}

/**
 * 401/403 の理由を切り分けて案内する。
 *
 * 同じ 403 でも「API 自体が無効」と「IAM の権限不足」で対処が違うため、
 * API が返したメッセージを見て振り分ける。原因を取り違えると、
 * 効かない設定作業を延々やらせることになる。
 */
function permissionHint(projectId, result) {
  const error = result?.body?.error ?? {};
  const raw = `${error.status ?? ''} ${error.message ?? ''}`.trim();

  const apiDisabled =
    /SERVICE_DISABLED/i.test(raw) ||
    /has not been used in project|is disabled/i.test(raw);
  if (apiDisabled) {
    return (
      'Identity Toolkit API が無効です。Firebase コンソール → Authentication で ' +
      '一度「始める」を押すか、GCP コンソールで identitytoolkit.googleapis.com を' +
      `有効化してください（プロジェクト: ${projectId}）。API 応答: ${raw}`
    );
  }
  return (
    'サービスアカウントに Firebase Authentication の管理権限がありません。' +
    'GCP コンソール → IAM で FIREBASE_SERVICE_ACCOUNT のアカウントに ' +
    '「Firebase Authentication 管理者」(roles/firebaseauth.admin) を付与してください' +
    `（プロジェクト: ${projectId}）。API 応答: ${raw}`
  );
}

// ---------------------------------------------------------------------------
// 1. Firebase の Google プロバイダ
// ---------------------------------------------------------------------------

async function ensureGoogleProvider(token, projectId, clientId, clientSecret) {
  const path = `projects/${projectId}/defaultSupportedIdpConfigs/google.com`;
  const current = await callIdentityToolkit(token, path);

  if (isPermissionDenied(current)) {
    unresolved += 1;
    log('Google プロバイダ', 'NG', permissionHint(projectId, current));
    return;
  }

  const exists = current.ok;
  const enabled = exists && current.body.enabled === true;
  const sameClient = exists && current.body.clientId === clientId;

  if (enabled && sameClient) {
    log('Google プロバイダ', 'OK', `有効。クライアント ID は ${mask(clientId)}`);
    return;
  }

  const detail = !exists
    ? '未設定です'
    : !enabled
      ? '無効になっています'
      : `別のクライアント ID (${mask(current.body.clientId)}) が設定されています`;

  if (!APPLY) {
    unresolved += 1;
    log('Google プロバイダ', '要変更', `${detail}。APPLY=true で有効化します`);
    return;
  }

  // シークレットが無くても、まずは ID だけで試す。Google プロバイダは
  // シークレット無しで通ることがあり、事前に諦めると余計な設定作業を
  // 要求してしまう。必要だった場合は API がその旨を返すので、それを見せる。
  const payload = clientSecret
    ? { enabled: true, clientId, clientSecret }
    : { enabled: true, clientId };
  const fields = clientSecret ? 'enabled,clientId,clientSecret' : 'enabled,clientId';

  // 既存があれば更新、無ければ作成。作成は idpId をクエリで渡す。
  const result = exists
    ? await callIdentityToolkit(token, `${path}?updateMask=${fields}`, {
        method: 'PATCH',
        body: payload,
      })
    : await callIdentityToolkit(
        token,
        `projects/${projectId}/defaultSupportedIdpConfigs?idpId=google.com`,
        { method: 'POST', body: payload },
      );

  if (!result.ok) {
    unresolved += 1;
    const apiMessage = result.body?.error?.message ?? `HTTP ${result.status}`;
    const reason = isPermissionDenied(result)
      ? permissionHint(projectId, result)
      : clientSecret
        ? apiMessage
        : `${apiMessage}（GOOGLE_WEB_CLIENT_SECRET を登録すると解決する可能性があります）`;
    log('Google プロバイダ', 'NG', reason);
    return;
  }
  log('Google プロバイダ', '適用', `有効化しました。クライアント ID は ${mask(clientId)}`);
}

// ---------------------------------------------------------------------------
// 2. Firebase の承認済みドメイン
// ---------------------------------------------------------------------------

async function ensureAuthorizedDomain(token, projectId, domain) {
  if (!domain) {
    log('承認済みドメイン', 'skip', 'PREVIEW_DOMAIN の指定がないため確認のみ省略');
    return;
  }
  const path = `projects/${projectId}/config`;
  const current = await callIdentityToolkit(token, path);
  if (!current.ok) {
    unresolved += 1;
    const reason = isPermissionDenied(current)
      ? permissionHint(projectId, current)
      : current.body?.error?.message ?? `HTTP ${current.status}`;
    log('承認済みドメイン', 'NG', reason);
    return;
  }

  const domains = current.body.authorizedDomains ?? [];
  if (domains.includes(domain)) {
    log('承認済みドメイン', 'OK', `${domain} は登録済み`);
    return;
  }
  if (!APPLY) {
    unresolved += 1;
    log('承認済みドメイン', '要変更', `${domain} が未登録。APPLY=true で追加します`);
    return;
  }

  const result = await callIdentityToolkit(token, `${path}?updateMask=authorizedDomains`, {
    method: 'PATCH',
    body: { authorizedDomains: [...domains, domain] },
  });
  if (!result.ok) {
    unresolved += 1;
    log('承認済みドメイン', 'NG', result.body?.error?.message ?? `HTTP ${result.status}`);
    return;
  }
  log('承認済みドメイン', '適用', `${domain} を追加しました`);
}

// ---------------------------------------------------------------------------
// 3. Supabase の Google プロバイダ（任意）
// ---------------------------------------------------------------------------

async function checkSupabase(ref, clientId) {
  const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
  if (!token) {
    log(
      'Supabase の受け入れ設定',
      'skip',
      'SUPABASE_ACCESS_TOKEN 未設定のため未確認。Firebase 側と同じクライアント ID を使うので、' +
        'Supabase の Client ID が一致していれば追加設定は不要です',
    );
    return;
  }
  if (!ref) {
    unresolved += 1;
    log('Supabase の受け入れ設定', 'NG', 'FLUTTER_ENV_PROD の SUPABASE_URL からプロジェクト ref を取得できません');
    return;
  }

  // NOTE: Management API のフィールド名（external_google_*）は実機で未検証。
  // 想定と違えば下の PATCH が 4xx を返すので、その場合は
  // docs/manual_setup/supabase.md §4.2 の手動手順に切り替えること。
  const endpoint = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
  const response = await fetch(endpoint, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    unresolved += 1;
    log(
      'Supabase の受け入れ設定',
      'NG',
      `設定を読めません（HTTP ${response.status}）。アクセストークンとプロジェクト ref を確認してください`,
    );
    return;
  }
  const config = await response.json();
  const configured = (config.external_google_client_id ?? '').split(',').map((v) => v.trim());
  const additional = (config.external_google_additional_client_ids ?? '')
    .split(',')
    .map((v) => v.trim());
  const accepted = new Set([...configured, ...additional].filter(Boolean));

  if (config.external_google_enabled && accepted.has(clientId)) {
    log('Supabase の受け入れ設定', 'OK', `${mask(clientId)} を受け入れます`);
    return;
  }

  if (!APPLY) {
    unresolved += 1;
    log(
      'Supabase の受け入れ設定',
      '要変更',
      `${mask(clientId)} が Client ID / Authorized Client IDs のどちらにもありません。APPLY=true で追加します`,
    );
    return;
  }

  const merged = [...accepted, clientId].filter((v) => v && v !== config.external_google_client_id);
  const patch = await fetch(endpoint, {
    method: 'PATCH',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      external_google_enabled: true,
      external_google_additional_client_ids: merged.join(','),
    }),
  });
  if (!patch.ok) {
    unresolved += 1;
    log('Supabase の受け入れ設定', 'NG', `更新できません（HTTP ${patch.status}）`);
    return;
  }
  log('Supabase の受け入れ設定', '適用', `${mask(clientId)} を Authorized Client IDs に追加しました`);
}

// ---------------------------------------------------------------------------

async function main() {
  const serviceAccount = JSON.parse(requireEnv('FIREBASE_SERVICE_ACCOUNT'));
  const projectId = serviceAccount.project_id;
  if (!projectId) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT に project_id がありません。');
  }
  const { clientId, supabaseUrl } = readAppEnv();
  const clientSecret = (process.env.GOOGLE_WEB_CLIENT_SECRET ?? '').trim();

  console.log(`対象 Firebase プロジェクト: ${projectId}`);
  console.log(`モード: ${APPLY ? '適用 (APPLY=true)' : '確認のみ (APPLY=false)'}`);
  console.log('');

  const token = await accessTokenFrom(serviceAccount);
  await ensureGoogleProvider(token, projectId, clientId, clientSecret);
  await ensureAuthorizedDomain(token, projectId, PREVIEW_DOMAIN);
  await checkSupabase(supabaseRefOf(supabaseUrl), clientId);

  const summary = process.env.GITHUB_STEP_SUMMARY;
  if (summary) {
    const { appendFileSync } = await import('node:fs');
    const lines = [
      '## Google ログインの設定',
      '',
      `モード: ${APPLY ? '**適用**' : '確認のみ'}`,
      '',
      '| 項目 | 状態 | 内容 |',
      '|---|---|---|',
      ...report.map((r) => `| ${r.step} | ${r.status} | ${r.detail} |`),
      '',
    ];
    if (unresolved > 0) {
      lines.push(
        `未解決が ${unresolved} 件あります。手順は \`docs/manual_setup/supabase.md\` §4.2 を参照してください。`,
        '',
      );
    }
    appendFileSync(summary, `${lines.join('\n')}\n`);
  }

  if (unresolved > 0) {
    console.error(`\n未解決: ${unresolved} 件`);
    if (FAIL_ON_UNRESOLVED) {
      process.exit(1);
    }
    return;
  }
  console.log('\nすべて設定済みです。');
}

main().catch((error) => {
  console.error(`失敗しました: ${error.message}`);
  process.exit(1);
});
