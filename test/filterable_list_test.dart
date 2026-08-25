import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/ui/ui.dart';

/// Search + filter behaviour of [FilterableList] (used by Activity, group
/// transactions, members, loans and meetings).
void main() {
  const items = ['Contribution Mary 20.00', 'Penalty John 5.00', 'Repayment Mary 27.50'];

  Widget host(List<String> data, {List<FilterOption<String>> filters = const [], int minItems = 1}) {
    return ShadcnApp(
      theme: VBankTheme.light(),
      home: Scaffold(
        child: FilterableList<String>(
          items: data,
          filters: filters,
          minItemsForSearch: minItems,
          searchText: (s) => s,
          builder: (context, visible) => ListView(children: [for (final v in visible) Text(v)]),
        ),
      ),
    );
  }

  testWidgets('shows every item until a query narrows it', (tester) async {
    await tester.pumpWidget(host(items));
    await tester.pumpAndSettle();
    expect(find.text('Contribution Mary 20.00'), findsOneWidget);
    expect(find.text('Penalty John 5.00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mary');
    await tester.pumpAndSettle();

    expect(find.text('Contribution Mary 20.00'), findsOneWidget);
    expect(find.text('Repayment Mary 27.50'), findsOneWidget);
    expect(find.text('Penalty John 5.00'), findsNothing);
    // Result counter appears once the list is narrowed.
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('search is case-insensitive and matches amounts', (tester) async {
    await tester.pumpWidget(host(items));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '27.5');
    await tester.pumpAndSettle();

    expect(find.text('Repayment Mary 27.50'), findsOneWidget);
    expect(find.text('Contribution Mary 20.00'), findsNothing);
  });

  testWidgets('no-match state explains why the list is empty', (tester) async {
    await tester.pumpWidget(host(items));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Contribution Mary 20.00'), findsNothing);
  });

  testWidgets('filter chips narrow the list and combine with the query', (tester) async {
    final filters = [
      FilterOption.all<String>(),
      FilterOption<String>('Contributions', (s) => s.startsWith('Contribution')),
      FilterOption<String>('Penalties', (s) => s.startsWith('Penalty')),
    ];
    await tester.pumpWidget(host(items, filters: filters));
    await tester.pumpAndSettle();
    expect(find.text('Penalty John 5.00'), findsOneWidget);

    await tester.tap(find.text('Contributions'));
    await tester.pumpAndSettle();
    expect(find.text('Contribution Mary 20.00'), findsOneWidget);
    expect(find.text('Penalty John 5.00'), findsNothing);

    // A query that can't match inside the active filter yields the empty state.
    await tester.enterText(find.byType(TextField), 'john');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('short lists hide the search field', (tester) async {
    await tester.pumpWidget(host(['only one'], minItems: 6));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('only one'), findsOneWidget);
  });
}
