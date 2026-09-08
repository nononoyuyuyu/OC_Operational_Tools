import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/design/theme.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/presentation/results_panel.dart';
import 'package:open_campus_organizer/features/kakutei/presentation/results_projection.dart';
import 'support.dart';

class _CountingMember extends Member {
  _CountingMember(super.id, super.username);
  int reads = 0;
  @override
  String get displayName {
    reads++;
    return super.displayName;
  }
}

Extraction _result(Member user, Member author) => Extraction(
  conditions(),
  [Message('100', '4', author, start, content: 'body')],
  [Activity(user, 1, start, start, false)],
  excludedBots: 0,
  at: start,
);

void main() {
  test('非表示の投稿を検索せず、同じ検索結果の配列を再利用する', () {
    final user = _CountingMember('10', 'Alice');
    final author = _CountingMember('11', 'Bob');
    final projection = ResultsProjection(
      _result(user, author),
      search: 'alice',
    );
    expect(user.reads, 0);
    expect(author.reads, 0);
    expect(projection.adding, 1);
    final users = projection.users;
    expect(users.single.member, same(user));
    expect(user.reads, 1);
    expect(author.reads, 0);
    expect(projection.users, same(users));
    expect(user.reads, 1);
    final messages = projection.messages;
    expect(messages, isEmpty);
    expect(author.reads, 1);
    expect(projection.messages, same(messages));
    expect(author.reads, 1);
    expect(() => users.clear(), throwsUnsupportedError);
  });

  test('空検索では不変の元配列を再利用し、氏名を全件検査しない', () {
    final user = _CountingMember('10', 'Alice');
    final result = _result(user, user);
    final projection = ResultsProjection(result, search: '  ');
    expect(projection.users, same(result.users));
    expect(projection.messages, same(result.messages));
    expect(user.reads, 0);
  });

  test('検索語は大小文字と前後空白を正規化し、ID・本文の検索を維持する', () {
    final result = _result(alice, bob);
    expect(ResultsProjection(result, search: '  10 ').users, hasLength(1));
    expect(ResultsProjection(result, search: ' BODY ').messages, hasLength(1));
    expect(ResultsProjection(result, search: '11').messages, hasLength(1));
  });

  testWidgets('進捗だけでは再検索せず、結果・Controllerの変更では再同期する', (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    KakuteiController controller() => KakuteiController(
      gateway: FakeGateway(),
      credentials: MemoryStore(),
      journal: FakeJournal(),
      exports: FakeExport(),
    );
    final first = controller();
    final second = controller();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final user = _CountingMember('10', 'Alice');
    final author = _CountingMember('11', 'Bob');
    first.extraction = _result(user, author);
    Future<void> show(KakuteiController c) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppAppearance.dark),
          home: Scaffold(
            body: ResultsPanel(
              key: const ValueKey('projection-test'),
              controller: c,
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(first);
    user.reads = 0;
    author.reads = 0;
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pumpAndSettle();
    expect(user.reads, 1);
    expect(author.reads, 0);
    first.busy = true;
    await show(first);
    expect(user.reads, 1);
    expect(author.reads, 0);
    await tester.tap(find.widgetWithText(ChoiceChip, '投稿 1'));
    await tester.pumpAndSettle();
    expect(author.reads, 1);
    await show(first);
    expect(author.reads, 1);
    final replacement = _CountingMember('12', 'Replacement');
    first.extraction = _result(replacement, replacement);
    await show(first);
    expect(replacement.reads, 1);
    second.extraction = first.extraction;
    await show(second);
    expect(replacement.reads, 2);
    second.extraction = null;
    await show(second);
    expect(find.text('抽出結果はありません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
