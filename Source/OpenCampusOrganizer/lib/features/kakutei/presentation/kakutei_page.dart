import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/failure.dart';
import '../../../design/device_layout.dart';
import '../../../design/theme.dart';
import '../../../design/select_field.dart';
import '../../../design/widgets.dart';
import '../application/kakutei_controller.dart';
import '../data/saved_settings.dart';
import '../domain/jst.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import 'connection_panel.dart';
import 'history_panel.dart';
import 'operation_dialogs.dart';
import 'operation_feedback.dart';
import 'results_panel.dart';

class KakuteiPage extends StatefulWidget {
  const KakuteiPage({super.key, required this.controller});
  final KakuteiController controller;
  @override
  State<KakuteiPage> createState() => _KakuteiPageState();
}

class _KakuteiPageState extends State<KakuteiPage> {
  late final _start = TextEditingController(
    text: formatJst(DateTime.now().subtract(const Duration(days: 7))),
  );
  final _end = TextEditingController();
  final _minimum = TextEditingController(text: '1');
  bool _excludeBots = true, _content = false, _attachments = false;
  int _stage = 0;
  String? _validation, _reportId;
  Extraction? _seenExtraction;
  int _settingsRevision = -1;
  bool _pickingDate = false;
  KakuteiController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncStage();
  }

  @override
  void didUpdateWidget(covariant KakuteiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStage();
  }

  void _syncStage() {
    if (_settingsRevision != c.settingsRevision) {
      final input = c.settings.input;
      _start.text =
          input.start ??
          formatJst(DateTime.now().subtract(const Duration(days: 7)));
      _end.text = input.end;
      _minimum.text = input.minimum;
      _excludeBots = input.excludeBots;
      _content = input.includeContent;
      _attachments = input.includeAttachments;
      _settingsRevision = c.settingsRevision;
    }
    if (c.latestReport != null && c.latestReport!.id != _reportId) {
      _stage = 2;
    } else if (c.extraction != null && c.extraction != _seenExtraction) {
      _stage = 1;
    }
    if (_stage == 2 && c.latestReport == null) _stage = 0;
    _reportId = c.latestReport?.id;
    _seenExtraction = c.extraction;
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _minimum.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (isPhoneLayout(context) &&
        _validation != null &&
        c.error == _validation) {
      c.clearMessage();
    }
    _validation = null;
    c.updateInput(
      ExtractionInput(
        start: _start.text,
        end: _end.text,
        minimum: _minimum.text,
        excludeBots: _excludeBots,
        includeContent: _content,
        includeAttachments: _attachments,
      ),
    );
  }

  void _showError(String message) {
    setState(() => _validation = message);
    if (isPhoneLayout(context)) c.showError(message);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final phone = isPhoneLayout(context);
      final wide =
          !phone &&
          box.maxWidth >= 840 &&
          box.maxHeight - OperationFeedback.heightFor(context) - 12 >= 520;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.connected && !wide) ...[
            _steps(),
            SizedBox(height: phone ? 8 : 16),
          ],
          Expanded(
            key: const ValueKey('kakutei-workspace'),
            child: !c.connected
                ? SingleChildScrollView(child: ConnectionPanel(controller: c))
                : LayoutBuilder(
                    builder: (context, box) {
                      final results = ResultsPanel(
                        key: const ValueKey('kakutei-results'),
                        controller: c,
                        onError: _showError,
                        onShowReport: wide && c.latestReport != null
                            ? () => setState(() => _stage = 2)
                            : null,
                      );
                      final report = c.latestReport == null
                          ? const SizedBox()
                          : ReportPanel(
                              report: c.latestReport!,
                              controller: c,
                              fill: true,
                              onShowTargets: wide
                                  ? () => setState(() => _stage = 1)
                                  : null,
                            );
                      // 片側表示でも条件・検索・ページ位置の状態を保持する。
                      return Row(
                        children: [
                          if (wide) ...[
                            SizedBox(width: 384, child: _conditions()),
                            const SizedBox(width: 24),
                          ],
                          Expanded(
                            key: const ValueKey('kakutei-result-workspace'),
                            child: IndexedStack(
                              index: wide ? (_stage == 2 ? 2 : 1) : _stage,
                              children: [
                                if (wide) const SizedBox() else _conditions(),
                                results,
                                report,
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (!phone) ...[const SizedBox(height: 12), _feedback()],
        ],
      );
    },
  );

  Widget _steps() => LayoutBuilder(
    builder: (context, box) => Row(
      key: const ValueKey('kakutei-step-tabs'),
      children: [
        for (var index = 0; index < 3; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index < 2 ? 12 : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _stage == index
                          ? context.colors.primary
                          : context.colors.outlineVariant,
                    ),
                  ),
                ),
                child: TextButton(
                  onPressed: index == 2 && c.latestReport == null
                      ? null
                      : () => setState(() => _stage = index),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    foregroundColor: _stage == index
                        ? context.colors.primary
                        : context.colors.onSurfaceVariant,
                  ),
                  child: Text(
                    '${box.maxWidth >= 600 ? '0${index + 1}  ' : ''}${['条件設定', '対象者確認', '実行結果'][index]}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _feedback() => OperationFeedback(
    controller: c,
    localError: _validation,
    onDismiss: () => setState(() => _validation = null),
  );

  Widget _conditions() => Surface(
    key: const ValueKey('conditions-panel'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const PageStorageKey('condition-fields'),
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '抽出条件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: c.busy ? null : c.refresh,
                      tooltip: 'サーバー・チャンネル・ロール一覧を更新',
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _selectionFields(),
                const Divider(),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, box) => box.maxWidth < 328
                      ? Column(
                          children: [
                            _dateField('開始日時（JST）', _start),
                            const SizedBox(height: 12),
                            _dateField('終了日時（任意）', _end),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: _dateField('開始日時（JST）', _start)),
                            const SizedBox(width: 12),
                            Expanded(child: _dateField('終了日時（任意）', _end)),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _minimum,
                  enabled: !c.busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: '最小投稿数',
                    suffixText: '件以上',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  onChanged: (_) => _invalidate(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: [
                    _check(
                      'Botを除外',
                      _excludeBots,
                      (value) => _excludeBots = value,
                    ),
                    if (!isPhoneLayout(context)) ...[
                      _check('本文', _content, (value) => _content = value),
                      _check(
                        '添付URL',
                        _attachments,
                        (value) => _attachments = value,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('extract-users'),
                onPressed: c.busy ? null : _extract,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('対象者を確認'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: c.busy ? null : c.checkPermissions,
              tooltip: '権限をチェック',
              icon: const Icon(Icons.verified_user_outlined, size: 20),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _selectionFields() => LayoutBuilder(
    builder: (context, box) {
      final server = _dropdown(
        'サーバー',
        c.selectedGuild?.id,
        c.guilds.map((g) => (g.id, g.name)).toList(),
        (value) => c.selectGuild(value!),
      );
      final channel = _dropdown(
        'チャンネル',
        c.channelId,
        c.readableChannels
            .map(
              (ch) => (
                ch.id,
                c.readableChannels
                            .where((other) => other.name == ch.name)
                            .length >
                        1
                    ? ch.label
                    : '#${ch.name}',
              ),
            )
            .toList(),
        c.selectChannel,
      );
      final role = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dropdown(
            '対象ロール',
            c.roleId,
            (c.guildContext?.roles ?? [])
                .where((r) => r.id != c.selectedGuild?.id)
                .map(
                  (r) => (
                    r.id,
                    '${r.name}${roleBlockReason(c.guildContext!, r) == null ? '' : '（操作不可）'}',
                  ),
                )
                .toList(),
            c.selectRole,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('remove-selected-role'),
              onPressed:
                  c.busy ||
                      c.selectedRole == null ||
                      roleBlockReason(c.guildContext!, c.selectedRole!) != null
                  ? null
                  : _remove,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('このロールを一括解除…'),
            ),
          ),
          if (c.selectedRole != null &&
              roleBlockReason(c.guildContext!, c.selectedRole!) != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                roleBlockReason(c.guildContext!, c.selectedRole!)!,
                style: TextStyle(fontSize: 12, color: context.colors.error),
              ),
            ),
        ],
      );
      return box.maxWidth >= 640
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: server),
                const SizedBox(width: 16),
                Expanded(child: channel),
                const SizedBox(width: 16),
                Expanded(child: role),
              ],
            )
          : Column(
              children: [
                server,
                const SizedBox(height: 12),
                channel,
                const SizedBox(height: 12),
                role,
              ],
            );
    },
  );

  Widget _dropdown(
    String label,
    String? value,
    List<(String, String)> values,
    ValueChanged<String?> changed,
  ) => SelectField<String>(
    key: ValueKey('$label:$value:${values.map((v) => v.$1).join(',')}'),
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    hint: const Text('選択してください'),
    items: values
        .map(
          (entry) => DropdownMenuItem(
            value: entry.$1,
            child: Tooltip(
              message: entry.$2,
              child: Text(entry.$2, overflow: TextOverflow.ellipsis),
            ),
          ),
        )
        .toList(),
    onChanged: c.busy ? null : changed,
  );

  Widget _dateField(String label, TextEditingController field) =>
      ValueListenableBuilder(
        valueListenable: field,
        builder: (context, value, child) => TextField(
          style: const TextStyle(fontSize: 12),
          controller: field,
          enabled: !c.busy,
          readOnly: true,
          showCursor: false,
          enableInteractiveSelection: false,
          onTap: () => _pickDate(field),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 11,
            ),
            hintText: field == _end ? '空欄：抽出時刻まで' : 'yyyy/MM/dd HH:mm',
            suffixIcon: IconButton(
              padding: EdgeInsets.zero,
              onPressed: c.busy
                  ? null
                  : () {
                      if (field == _end && value.text.isNotEmpty) {
                        field.clear();
                        _invalidate();
                      } else {
                        _pickDate(field);
                      }
                    },
              tooltip: field == _end && value.text.isNotEmpty
                  ? '終了日時をリセット'
                  : '$labelを選択',
              icon: Icon(
                field == _end && value.text.isNotEmpty
                    ? Icons.close
                    : Icons.calendar_month_outlined,
                size: 19,
              ),
            ),
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: 32,
              height: 48,
            ),
          ),
          onChanged: (_) => _invalidate(),
        ),
      );

  Widget _check(String label, bool value, ValueChanged<bool> setter) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: c.busy
        ? null
        : () {
            setState(() => setter(!value));
            _invalidate();
          },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: c.busy
              ? null
              : (value) {
                  setState(() => setter(value!));
                  _invalidate();
                },
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
      ],
    ),
  );

  Future<void> _pickDate(TextEditingController field) async {
    if (c.busy || _pickingDate) return;
    _pickingDate = true;
    try {
      DateTime initial;
      try {
        initial = jstFields(parseJst(field.text));
      } catch (_) {
        initial = jstFields(DateTime.now());
      }
      final day = await showDatePicker(
        context: context,
        initialDate: initial.isBefore(DateTime(2015))
            ? DateTime(2015)
            : initial.isAfter(DateTime(2100, 12, 31))
            ? DateTime(2100, 12, 31)
            : initial,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100, 12, 31),
        helpText: '日付を選択',
      );
      if (day == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
        helpText: '時刻を選択',
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (time == null || !mounted || c.busy) return;
      field.text = formatJst(
        DateTime.utc(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ).subtract(const Duration(hours: 9)),
      );
      _invalidate();
    } finally {
      _pickingDate = false;
    }
  }

  Future<void> _extract() async {
    try {
      final condition = Conditions(
        guildId: c.selectedGuild?.id ?? '',
        channelId: c.channelId ?? '',
        roleId: c.roleId ?? '',
        start: parseJst(_start.text),
        end: _end.text.trim().isEmpty ? null : parseJstMinuteEnd(_end.text),
        minimum: int.tryParse(_minimum.text) ?? 0,
        excludeBots: _excludeBots,
        includeContent: !isPhoneLayout(context) && _content,
        includeAttachments: !isPhoneLayout(context) && _attachments,
        retainMessages: !isPhoneLayout(context),
      );
      condition.validate();
      setState(() => _validation = null);
      await c.extract(condition);
    } catch (error) {
      if (mounted) _showError(failureMessage(error));
    }
  }

  Future<void> _remove() async {
    setState(() => _validation = null);
    await c.previewRemoval();
    if (mounted && c.removalPlan != null) {
      await confirmOperation(context, c, c.removalPlan!);
    }
  }
}
