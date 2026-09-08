import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 保存値の復元・旧データのエラー検証用。実際の選択操作はdate_picker_testで検証する。
Future<void> restoreDateField(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  final field = tester.widget<TextField>(finder);
  field.controller!.text = value;
  field.onChanged?.call(value);
  await tester.pump();
}
