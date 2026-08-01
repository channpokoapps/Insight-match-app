import 'package:app2/features/search/domain/criteria.dart';
import 'package:app2/features/search/domain/masked_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Criteria のシリアライズ', () {
    test('サーバが受け付ける形の JSON になる', () {
      const Criteria criteria = CriteriaGroup(
        op: LogicalOp.and,
        children: <Criteria>[
          MetricCriteria(
            metric: CriteriaMetric.avgReach,
            platform: SocialPlatform.instagram,
            window: MetricWindow.d30,
            comparator: Comparator.gte,
            value: 3000,
          ),
          AttributeCriteria(
            attribute: CriteriaAttribute.prefectureId,
            comparator: Comparator.eq,
            value: 13,
          ),
        ],
      );

      expect(criteria.toJson(), <String, dynamic>{
        'op': 'AND',
        'children': <dynamic>[
          <String, dynamic>{
            'metric': 'avg_reach',
            'platform': 'instagram',
            'window': 30,
            'cmp': '>=',
            'value': 3000.0,
          },
          <String, dynamic>{
            'attr': 'prefecture_id',
            'cmp': '=',
            'value': 13.0,
          },
        ],
      });
    });

    test('往復変換で内容が保たれる', () {
      const Criteria original = MetricCriteria(
        metric: CriteriaMetric.engagementRate,
        platform: SocialPlatform.instagram,
        window: MetricWindow.d90,
        comparator: Comparator.gt,
        value: 0.03,
      );
      final Criteria restored = Criteria.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
    });
  });

  group('CriteriaValidator', () {
    test('3段までのネストは許可される', () {
      const Criteria criteria = CriteriaGroup(
        op: LogicalOp.and,
        children: <Criteria>[
          CriteriaGroup(
            op: LogicalOp.or,
            children: <Criteria>[
              MetricCriteria(
                metric: CriteriaMetric.followers,
                platform: SocialPlatform.instagram,
                window: MetricWindow.d30,
                comparator: Comparator.gte,
                value: 1000,
              ),
            ],
          ),
        ],
      );
      expect(CriteriaValidator.validate(criteria), isNull);
    });

    test('4段のネストは拒否される', () {
      const Criteria leaf = MetricCriteria(
        metric: CriteriaMetric.followers,
        platform: SocialPlatform.instagram,
        window: MetricWindow.d30,
        comparator: Comparator.gte,
        value: 1000,
      );
      const Criteria criteria = CriteriaGroup(
        op: LogicalOp.and,
        children: <Criteria>[
          CriteriaGroup(
            op: LogicalOp.or,
            children: <Criteria>[
              CriteriaGroup(op: LogicalOp.and, children: <Criteria>[leaf]),
            ],
          ),
        ],
      );
      expect(CriteriaValidator.validate(criteria), isNotNull);
    });
  });

  group('MaskedCount', () {
    test('5人未満のレスポンスでは実数を持たない', () {
      final MaskedCount count = MaskedCount.fromJson(<String, dynamic>{
        'count': null,
        'masked': true,
        'label': '5人未満',
      });
      expect(count.count, isNull);
      expect(count.masked, isTrue);
      expect(count.isDeterminable, isFalse);
      expect(count.label, '5人未満');
    });

    test('5人以上なら実数を持つ', () {
      final MaskedCount count = MaskedCount.fromJson(<String, dynamic>{
        'count': 23,
        'masked': false,
        'label': '23人',
      });
      expect(count.count, 23);
      expect(count.isDeterminable, isTrue);
    });

    test('未知の形式では安全側（masked）に倒れる', () {
      final MaskedCount count = MaskedCount.fromJson(<String, dynamic>{});
      expect(count.masked, isTrue);
      expect(count.isDeterminable, isFalse);
    });
  });
}
