import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/search/domain/campaign_filter.dart';

void main() {
  group('CampaignFilter', () {
    test('中身が同じなら等しい（Provider のキャッシュが効く）', () {
      const CampaignFilter a = CampaignFilter(
        prefectureIds: <int>[13, 27],
        lineIds: <int>[99],
        sort: CampaignSort.rewardDesc,
      );
      final CampaignFilter b = CampaignFilter(
        prefectureIds: <int>[13, 27],
        lineIds: <int>[99],
        sort: CampaignSort.rewardDesc,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('リストの中身が違えば等しくない', () {
      const CampaignFilter a = CampaignFilter(prefectureIds: <int>[13]);
      const CampaignFilter b = CampaignFilter(prefectureIds: <int>[27]);
      expect(a, isNot(b));
    });

    test('未指定なら isActive は false', () {
      expect(const CampaignFilter().isActive, isFalse);
      expect(const CampaignFilter(sort: CampaignSort.rewardDesc).isActive,
          isFalse);
    });

    test('activeCount は指定した種類の数を返す', () {
      const CampaignFilter filter = CampaignFilter(
        prefectureIds: <int>[13],
        genreIds: <int>[1, 2],
        minReward: 5000,
      );
      expect(filter.activeCount, 3);
    });

    test('空リストは絞り込まない意味なので null にして送る', () {
      expect(CampaignFilter.toParam(const <int>[]), isNull);
      expect(CampaignFilter.toParam(const <int>[1]), <int>[1]);
    });

    test('minReward は明示的に消せる', () {
      const CampaignFilter filter = CampaignFilter(minReward: 5000);
      expect(filter.copyWith().minReward, 5000);
      expect(filter.copyWith(clearMinReward: true).minReward, isNull);
    });

    test('並び順のキーはサーバ側の許可リストと一致する', () {
      // 0014_search_campaigns.sql の case 分岐と揃っていること。
      expect(CampaignSort.newest.key, 'newest');
      expect(CampaignSort.rewardDesc.key, 'reward_desc');
    });
  });
}
