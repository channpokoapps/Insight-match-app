// _shared/insights.ts
// インサイトの集計とレスポンス解析（純粋関数）。
//
// sync-worker から分離してテスト可能にする。ここには I/O を書かない。
// 集計結果は private.creator_metrics にのみ保存される（AGENTS.md R-1）。

/** 集計ウィンドウ（日数）。7/30/90 日平均（要件 9-2 #10）。 */
export const WINDOWS = [7, 30, 90] as const;

/** メディア1件分のスナップショット。取得できなかった指標は null。 */
export interface MediaMetrics {
  id: string;
  media_type?: string;
  permalink?: string;
  timestamp: string;
  like_count?: number | null;
  comments_count?: number | null;
  reach?: number | null;
  impressions?: number | null;
  saved?: number | null;
  shares?: number | null;
  views?: number | null;
}

/** ウィンドウごとの集計値。creator_metrics の1行に対応する。 */
export interface WindowMetrics {
  window_days: number;
  avg_reach: number | null;
  avg_impressions: number | null;
  avg_likes: number | null;
  avg_comments: number | null;
  avg_saves: number | null;
  avg_shares: number | null;
  avg_views: number | null;
  engagement_rate: number | null;
  post_count: number;
}

/**
 * 7/30/90 日のウィンドウ平均を計算する。
 *
 * 取得できなかった指標（null）は平均の分母から除外する（要件 9-4-3）。
 * エンゲージメント率 = (いいね + コメント + 保存 + シェア) ÷ リーチ（要件 9-3）。
 */
export function aggregateWindows(media: MediaMetrics[], nowMs: number): WindowMetrics[] {
  return WINDOWS.map((windowDays) => {
    const from = nowMs - windowDays * 86_400_000;
    const target = media.filter((m) => {
      const t = new Date(m.timestamp).getTime();
      return Number.isFinite(t) && t >= from && t <= nowMs;
    });
    const avg = (pick: (m: MediaMetrics) => number | null | undefined): number | null => {
      const values = target.map(pick).filter((v): v is number => typeof v === "number");
      return values.length === 0 ? null : values.reduce((a, b) => a + b, 0) / values.length;
    };

    const avgReach = avg((m) => m.reach);
    const avgLikes = avg((m) => m.like_count);
    const avgComments = avg((m) => m.comments_count);
    const avgSaves = avg((m) => m.saved);
    const avgShares = avg((m) => m.shares);

    const engagement = avgReach && avgReach > 0
      ? ((avgLikes ?? 0) + (avgComments ?? 0) + (avgSaves ?? 0) + (avgShares ?? 0)) / avgReach
      : null;

    return {
      window_days: windowDays,
      avg_reach: avgReach,
      avg_impressions: avg((m) => m.impressions),
      avg_likes: avgLikes,
      avg_comments: avgComments,
      avg_saves: avgSaves,
      avg_shares: avgShares,
      avg_views: avg((m) => m.views),
      engagement_rate: engagement,
      post_count: target.length,
    };
  });
}

/**
 * メディアインサイト API（/{media-id}/insights）のレスポンスを
 * `{ 指標名: 値 }` に変換する。解析できない形は空を返す。
 */
export function parseInsightValues(body: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  const data = (body as { data?: unknown })?.data;
  if (!Array.isArray(data)) return out;
  for (const entry of data) {
    const name = (entry as { name?: unknown })?.name;
    const values = (entry as { values?: unknown })?.values;
    if (typeof name !== "string" || !Array.isArray(values)) continue;
    const value = (values[0] as { value?: unknown })?.value;
    if (typeof value === "number") out[name] = value;
  }
  return out;
}

/**
 * follower_demographics（period=lifetime, metric_type=total_value,
 * breakdown 指定）のレスポンスを `{ bucket, value }` の一覧に変換する。
 */
export function parseDemographics(body: unknown): { bucket: string; value: number }[] {
  const out: { bucket: string; value: number }[] = [];
  const data = (body as { data?: unknown })?.data;
  if (!Array.isArray(data) || data.length === 0) return out;
  const breakdowns = (data[0] as { total_value?: { breakdowns?: unknown } })
    ?.total_value?.breakdowns;
  if (!Array.isArray(breakdowns) || breakdowns.length === 0) return out;
  const results = (breakdowns[0] as { results?: unknown })?.results;
  if (!Array.isArray(results)) return out;
  for (const r of results) {
    const dims = (r as { dimension_values?: unknown })?.dimension_values;
    const value = (r as { value?: unknown })?.value;
    if (Array.isArray(dims) && typeof dims[0] === "string" && typeof value === "number") {
      out.push({ bucket: dims[0], value });
    }
  }
  return out;
}

/** 比率（0〜1）へ正規化する。合計 0 のときは空を返す。 */
export function toRatios(
  entries: { bucket: string; value: number }[],
): { bucket: string; ratio: number }[] {
  const total = entries.reduce((a, b) => a + b.value, 0);
  if (total <= 0) return [];
  return entries.map((e) => ({ bucket: e.bucket, ratio: e.value / total }));
}
