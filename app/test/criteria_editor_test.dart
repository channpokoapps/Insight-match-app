import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/criteria_editor.dart';
import 'package:insight_match/features/search/domain/criteria.dart';

void main() {
  group('CriteriaEditor', () {
    test('条件が 1 つも無ければ空の AND グループを返す', () {
      final CriteriaEditor editor = CriteriaEditor();
      final Criteria criteria = editor.toCriteria();
      expect(criteria, isA<CriteriaGroup>());
      expect((criteria as CriteriaGroup).children, isEmpty);
      expect(criteria.op, LogicalOp.and);
      expect(editor.validate(), isNull);
    });

    test('値が未入力のリーフは送信内容に含めない', () {
      final CriteriaEditor editor = CriteriaEditor();
      editor.root.children.add(CriteriaNodeMetric(value: 1000));
      editor.root.children.add(CriteriaNodeMetric());

      expect(editor.completedLeafCount, 1);
      expect(editor.hasIncompleteLeaf, isTrue);
      expect((editor.toCriteria() as CriteriaGroup).children, hasLength(1));
    });

    test('値が未入力のリーフがあると保存できない', () {
      final CriteriaEditor editor = CriteriaEditor();
      editor.root.children.add(CriteriaNodeAttribute());
      expect(editor.validate(), contains('値が入力されていない'));
    });

    test('AND / OR の入れ子を送信用モデルへ変換する', () {
      final CriteriaEditor editor = CriteriaEditor();
      final CriteriaNodeGroup or = CriteriaNodeGroup(op: LogicalOp.or);
      or.children.add(CriteriaNodeMetric(
        metric: CriteriaMetric.followers,
        platform: SocialPlatform.instagram,
        window: MetricWindow.d30,
        comparator: Comparator.gte,
        value: 1000,
      ));
      or.children.add(CriteriaNodeMetric(
        metric: CriteriaMetric.avgReach,
        platform: SocialPlatform.tiktok,
        window: MetricWindow.d7,
        comparator: Comparator.gte,
        value: 5000,
      ));
      editor.root.children
        ..add(CriteriaNodeAttribute(
          attribute: CriteriaAttribute.age,
          comparator: Comparator.gte,
          value: 20,
        ))
        ..add(or);

      expect(editor.toCriteria().toJson(), <String, dynamic>{
        'op': 'AND',
        'children': <dynamic>[
          <String, dynamic>{'attr': 'age', 'cmp': '>=', 'value': 20.0},
          <String, dynamic>{
            'op': 'OR',
            'children': <dynamic>[
              <String, dynamic>{
                'metric': 'followers',
                'platform': 'instagram',
                'window': 30,
                'cmp': '>=',
                'value': 1000.0,
              },
              <String, dynamic>{
                'metric': 'avg_reach',
                'platform': 'tiktok',
                'window': 7,
                'cmp': '>=',
                'value': 5000.0,
              },
            ],
          },
        ],
      });
    });

    test('空のグループは送信内容から省かれる', () {
      final CriteriaEditor editor = CriteriaEditor();
      editor.root.children
        ..add(CriteriaNodeMetric(value: 100))
        ..add(CriteriaNodeGroup());
      expect((editor.toCriteria() as CriteriaGroup).children, hasLength(1));
    });

    test('保存済みの条件式から編集ツリーを復元できる', () {
      const Criteria original = CriteriaGroup(
        op: LogicalOp.or,
        children: <Criteria>[
          MetricCriteria(
            metric: CriteriaMetric.engagementRate,
            platform: SocialPlatform.youtube,
            window: MetricWindow.d90,
            comparator: Comparator.gt,
            value: 3.5,
          ),
          AttributeCriteria(
            attribute: CriteriaAttribute.prefectureId,
            comparator: Comparator.eq,
            value: 27,
          ),
        ],
      );
      final CriteriaEditor editor = CriteriaEditor.fromCriteria(original);
      expect(editor.root.op, LogicalOp.or);
      expect(editor.completedLeafCount, 2);
      expect(editor.toCriteria().toJson(), original.toJson());
    });

    test('単独のリーフを復元するとグループで包む', () {
      const Criteria leaf = AttributeCriteria(
        attribute: CriteriaAttribute.age,
        comparator: Comparator.lte,
        value: 30,
      );
      final CriteriaEditor editor = CriteriaEditor.fromCriteria(leaf);
      expect(editor.root.children, hasLength(1));
      expect(editor.toCriteria().toJson(), <String, dynamic>{
        'op': 'AND',
        'children': <dynamic>[leaf.toJson()],
      });
    });

    test('ネストは 3 段まで。それ以上はグループを追加させない', () {
      final CriteriaEditor editor = CriteriaEditor();
      final CriteriaNodeGroup second = CriteriaNodeGroup();
      final CriteriaNodeGroup third = CriteriaNodeGroup();
      editor.root.children.add(second);
      second.children.add(third);

      expect(editor.canNestUnder(editor.root), isTrue);
      expect(editor.canNestUnder(second), isTrue);
      expect(editor.canNestUnder(third), isFalse);
    });

    test('4 段目まで組むと検証で弾かれる', () {
      final CriteriaEditor editor = CriteriaEditor();
      final CriteriaNodeGroup g2 = CriteriaNodeGroup();
      final CriteriaNodeGroup g3 = CriteriaNodeGroup();
      final CriteriaNodeGroup g4 = CriteriaNodeGroup();
      g4.children.add(CriteriaNodeMetric(value: 1));
      g3.children.add(g4);
      g2.children.add(g3);
      editor.root.children.add(g2);

      expect(editor.validate(), contains('3段'));
    });

    test('入れ子の中のノードも削除できる', () {
      final CriteriaEditor editor = CriteriaEditor();
      final CriteriaNodeGroup group = CriteriaNodeGroup();
      final CriteriaNodeMetric leaf = CriteriaNodeMetric(value: 10);
      group.children.add(leaf);
      editor.root.children.add(group);

      editor.remove(leaf);
      expect(group.children, isEmpty);

      editor.remove(group);
      expect(editor.root.children, isEmpty);
    });
  });
}
