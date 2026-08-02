// _shared/insights_test.ts
// インサイト集計・レスポンス解析の検証。
// 実行: cd supabase/functions && deno task test

import {
  aggregateWindows,
  type MediaMetrics,
  parseDemographics,
  parseInsightValues,
  toRatios,
} from "./insights.ts";

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertClose(actual: number | null, expected: number, msg: string): void {
  assert(actual !== null && Math.abs(actual - expected) < 1e-9, `${msg}: got ${actual}`);
}

const NOW = Date.parse("2026-08-01T00:00:00Z");

function mediaAt(daysAgo: number, values: Partial<MediaMetrics> = {}): MediaMetrics {
  return {
    id: `m${daysAgo}`,
    timestamp: new Date(NOW - daysAgo * 86_400_000).toISOString(),
    ...values,
  };
}

Deno.test("ウィンドウごとに対象投稿だけを平均する", () => {
  const media = [
    mediaAt(1, { reach: 100, like_count: 10 }),
    mediaAt(20, { reach: 300, like_count: 30 }),
    mediaAt(80, { reach: 500, like_count: 50 }),
    mediaAt(200, { reach: 9999, like_count: 999 }), // 90日より古い → 全ウィンドウ対象外
  ];
  const [w7, w30, w90] = aggregateWindows(media, NOW);

  assert(w7.post_count === 1, "7日は1件");
  assertClose(w7.avg_reach, 100, "7日平均リーチ");
  assert(w30.post_count === 2, "30日は2件");
  assertClose(w30.avg_reach, 200, "30日平均リーチ");
  assert(w90.post_count === 3, "90日は3件");
  assertClose(w90.avg_reach, 300, "90日平均リーチ");
});

Deno.test("取得できなかった指標(null)は平均の分母から除外する", () => {
  const media = [
    mediaAt(1, { reach: 100, saved: 10 }),
    mediaAt(2, { reach: 200, saved: null }), // saved が取れなかった投稿
  ];
  const [w7] = aggregateWindows(media, NOW);
  assertClose(w7.avg_reach, 150, "リーチは2件平均");
  assertClose(w7.avg_saves, 10, "保存数は取得できた1件のみで平均");
  assert(w7.avg_views === null, "全滅の指標は null");
});

Deno.test("エンゲージメント率 = (いいね+コメント+保存+シェア) ÷ リーチ", () => {
  const media = [
    mediaAt(1, { reach: 200, like_count: 20, comments_count: 10, saved: 6, shares: 4 }),
  ];
  const [w7] = aggregateWindows(media, NOW);
  assertClose(w7.engagement_rate, 0.2, "エンゲージメント率");
});

Deno.test("リーチが取得できないときエンゲージメント率は null", () => {
  const [w7] = aggregateWindows([mediaAt(1, { like_count: 10 })], NOW);
  assert(w7.engagement_rate === null, "分母なしは null");
});

Deno.test("メディアインサイトのレスポンスを指標名→値に変換する", () => {
  const body = {
    data: [
      { name: "reach", values: [{ value: 123 }] },
      { name: "saved", values: [{ value: 4 }] },
      { name: "broken", values: [] },
    ],
  };
  const values = parseInsightValues(body);
  assert(values.reach === 123 && values.saved === 4, "reach/saved を取り出す");
  assert(!("broken" in values), "値が無い指標は含めない");
  assert(Object.keys(parseInsightValues({})).length === 0, "不正な形は空");
});

Deno.test("follower_demographics を bucket と比率に変換する", () => {
  const body = {
    data: [{
      total_value: {
        breakdowns: [{
          dimension_keys: ["age"],
          results: [
            { dimension_values: ["18-24"], value: 30 },
            { dimension_values: ["25-34"], value: 70 },
          ],
        }],
      },
    }],
  };
  const ratios = toRatios(parseDemographics(body));
  assert(ratios.length === 2, "2バケット");
  assertClose(ratios[0].ratio, 0.3, "18-24 の比率");
  assertClose(ratios[1].ratio, 0.7, "25-34 の比率");
  assert(toRatios([]).length === 0, "空入力は空");
});
