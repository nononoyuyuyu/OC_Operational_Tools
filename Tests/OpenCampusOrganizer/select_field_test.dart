import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/design/select_field.dart';
import 'package:open_campus_organizer/design/theme.dart';

void main() {
  testWidgets('狭い画面でも長い選択肢へスクロールでき、配色変更後も選択を保つ', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var appearance = AppAppearance.dark;
    int? selected;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: buildTheme(appearance),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectField<int>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'サーバー'),
                    items: List.generate(
                      30,
                      (i) => DropdownMenuItem(value: i, child: Text('サーバー $i')),
                    ),
                    onChanged: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.tap(find.byType(SelectField<int>));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('サーバー 20'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('サーバー 20').last);
    await tester.pumpAndSettle();
    expect(selected, 20);
    for (final theme in AppAppearance.values) {
      rebuild(() => appearance = theme);
      await tester.pumpAndSettle();
      expect(selected, 20);
      await tester.tap(find.byType(SelectField<int>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // メニュー外のタップで閉じても値を変更しない。
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(selected, 20);
    }
  });
}
