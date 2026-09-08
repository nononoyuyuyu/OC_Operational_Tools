import 'package:flutter/material.dart';

/// 入力欄とポップアップの外観を共通化し、選択状態は呼び出し側で管理する。
class SelectField<T> extends StatelessWidget {
  const SelectField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.hint,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final Widget? hint;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: initialValue,
    items: items,
    onChanged: onChanged,
    decoration: decoration,
    hint: hint,
    isExpanded: true,
    borderRadius: BorderRadius.circular(16),
    dropdownColor: Theme.of(context).colorScheme.surface,
    elevation: 3,
    menuMaxHeight: 320,
    icon: const Icon(Icons.keyboard_arrow_down_rounded),
    padding: const EdgeInsets.symmetric(horizontal: 4),
  );
}
