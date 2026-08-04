import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/masters/master_repository.dart';
import 'package:insight_match/shared/widgets/genre_multi_select.dart';

const List<MasterItem> _genres = <MasterItem>[
  MasterItem(id: 1, name: '和食'),
  MasterItem(id: 3, name: '居酒屋'),
  MasterItem(id: 13, name: kOtherGenreName),
];

Widget _host({required Set<int> selected, required Set<int> sink}) {
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return GenreMultiSelect(
            label: 'ジャンル',
            genres: const AsyncValue<List<MasterItem>>.data(_genres),
            selectedIds: selected,
            otherController: TextEditingController(),
            onToggle: (int id, bool on) => setState(() {
              if (on) {
                selected.add(id);
              } else {
                selected.remove(id);
              }
              sink
                ..clear()
                ..addAll(selected);
            }),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('ジャンルは複数まとめて選択できる', (WidgetTester tester) async {
    final Set<int> selected = <int>{};
    final Set<int> sink = <int>{};
    await tester.pumpWidget(_host(selected: selected, sink: sink));

    await tester.tap(find.text('和食'));
    await tester.pump();
    await tester.tap(find.text('居酒屋'));
    await tester.pump();

    expect(sink, <int>{1, 3});
  });

  testWidgets('その他を選んだときだけ自由記述欄が出る', (WidgetTester tester) async {
    final Set<int> selected = <int>{};
    await tester
        .pumpWidget(_host(selected: selected, sink: <int>{}));

    expect(find.text('その他のジャンル'), findsNothing);

    await tester.tap(find.text(kOtherGenreName));
    await tester.pump();

    expect(find.text('その他のジャンル'), findsOneWidget);
  });

  test('hasOther はマスタ上の「その他」の id で判定する', () {
    expect(GenreMultiSelect.hasOther(_genres, <int>{13}), isTrue);
    expect(GenreMultiSelect.hasOther(_genres, <int>{1, 3}), isFalse);
    expect(GenreMultiSelect.hasOther(_genres, <int>{}), isFalse);
  });
}
