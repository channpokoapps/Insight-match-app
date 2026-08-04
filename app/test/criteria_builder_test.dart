import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/criteria_editor.dart';
import 'package:insight_match/features/campaign/presentation/criteria_builder.dart';
import 'package:insight_match/features/search/domain/masked_count.dart';

void main() {
  Widget wrap(Widget child, {List<Override> overrides = const <Override>[]}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  /// 該当人数の問い合わせを差し替える。デバウンスを挟まないため即座に確定する。
  Override countOverride(MaskedCount value) =>
      matchingCreatorCountProvider.overrideWith(
        (Ref ref, String criteriaJson) async => value,
      );

  group('MatchingCountBadge', () {
    testWidgets('値が未入力のうちはサーバへ問い合わせない', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor();
      editor.root.children.add(CriteriaNodeMetric());

      await tester.pumpWidget(wrap(
        MatchingCountBadge(editor: editor),
        overrides: <Override>[
          countOverride(
            const MaskedCount(count: 42, masked: false, label: '42人'),
          ),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('値を入力すると'), findsOneWidget);
      expect(find.textContaining('42'), findsNothing);
    });

    testWidgets('サーバが返した人数をそのまま表示する', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor()
        ..root.children.add(CriteriaNodeMetric(value: 1000));

      await tester.pumpWidget(wrap(
        MatchingCountBadge(editor: editor),
        overrides: <Override>[
          countOverride(
            const MaskedCount(count: 42, masked: false, label: '42人'),
          ),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('42人'), findsOneWidget);
    });

    testWidgets('k 未満のときは実数を出さず、丸められた文言だけを出す',
        (WidgetTester tester) async {
      // サーバは count を返さない（AGENTS.md R-4）。
      // 画面側で推定値を補完しないことを型と表示の両方で担保する。
      final CriteriaEditor editor = CriteriaEditor()
        ..root.children.add(CriteriaNodeMetric(value: 999999));

      await tester.pumpWidget(wrap(
        MatchingCountBadge(editor: editor),
        overrides: <Override>[
          countOverride(
            const MaskedCount(count: null, masked: true, label: '5人未満'),
          ),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('5人未満'), findsOneWidget);
      expect(find.textContaining('人数が少ないため'), findsOneWidget);
      // 「0人」「1人」のような具体値を出さない
      expect(find.textContaining('0人'), findsNothing);
      expect(find.textContaining('1人'), findsNothing);
    });

    testWidgets('取得に失敗しても人数を推測して出さない', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor()
        ..root.children.add(CriteriaNodeMetric(value: 10));

      await tester.pumpWidget(wrap(
        MatchingCountBadge(editor: editor),
        overrides: <Override>[
          matchingCreatorCountProvider.overrideWith(
            (Ref ref, String criteriaJson) async =>
                throw Exception('network down'),
          ),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('取得できませんでした'), findsOneWidget);
      // 失敗時に人数らしき値を出さない
      expect(find.textContaining('条件に合う投稿者：'), findsNothing);
      expect(
        find.byWidgetPredicate((Widget w) =>
            w is Text && RegExp(r'\d+\s*人').hasMatch(w.data ?? '')),
        findsNothing,
      );
    });
  });

  group('CriteriaBuilder', () {
    testWidgets('条件が空のときは全員が応募できる旨を伝える', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor();
      await tester.pumpWidget(wrap(
        CriteriaBuilder(editor: editor, onChanged: () {}),
      ));

      expect(find.textContaining('すべての投稿者が応募できます'), findsOneWidget);
    });

    testWidgets('インサイト条件を追加できる', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor();
      int changes = 0;
      await tester.pumpWidget(wrap(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              CriteriaBuilder(
            editor: editor,
            onChanged: () => setState(() => changes++),
          ),
        ),
      ));

      await tester.tap(find.text('インサイト条件'));
      await tester.pump();

      expect(changes, 1);
      expect(editor.root.children, hasLength(1));
      expect(editor.root.children.first, isA<CriteriaNodeMetric>());
    });

    testWidgets('3 段目のグループにはさらにグループを追加させない',
        (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor();
      final CriteriaNodeGroup second = CriteriaNodeGroup();
      final CriteriaNodeGroup third = CriteriaNodeGroup();
      second.children.add(third);
      editor.root.children.add(second);

      await tester.pumpWidget(wrap(
        CriteriaBuilder(editor: editor, onChanged: () {}),
      ));

      // 根・2段目にはボタンが出るが、3段目には出ない。
      expect(find.text('グループ'), findsNWidgets(2));
    });

    testWidgets('編集できない状態では操作ボタンを無効にする', (WidgetTester tester) async {
      final CriteriaEditor editor = CriteriaEditor();
      await tester.pumpWidget(wrap(
        CriteriaBuilder(editor: editor, onChanged: () {}, enabled: false),
      ));

      // TextButton.icon は TextButton の派生型を作るため byType では拾えない。
      final List<Widget> buttons = tester
          .widgetList(find.byWidgetPredicate((Widget w) => w is TextButton))
          .toList();
      expect(buttons, isNotEmpty);
      expect(
        buttons.every((Widget w) => (w as TextButton).onPressed == null),
        isTrue,
      );
    });
  });
}
