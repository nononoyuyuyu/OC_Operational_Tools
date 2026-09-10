import 'package:flutter/material.dart';
import '../core/appearance.dart';
import '../core/tool_module.dart';
import '../design/connection_indicator.dart';
import '../design/device_layout.dart';
import '../design/theme.dart';
import '../design/widgets.dart';
import 'history_page.dart';
import 'mobile_feedback_host.dart';
import 'runtime_settings.dart';
import '../core/runtime_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.modules,
    required this.appearance,
    this.runtime,
  });
  final List<ToolModule> modules;
  final AppearanceController appearance;
  final RuntimeController? runtime;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _destination = 'tools';
  late List<ToolModule> _mountedModules;

  @override
  void initState() {
    super.initState();
    _mountedModules = List.of(widget.modules);
    for (final module in _mountedModules) {
      module.initialize();
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = List<ToolModule>.of(widget.modules);
    for (final module in _mountedModules) {
      if (!next.any((value) => identical(value, module))) module.dispose();
    }
    for (final module in next) {
      if (!_mountedModules.any((value) => identical(value, module))) {
        module.initialize();
      }
    }
    _mountedModules = next;
    if (!['tools', 'history', 'settings'].contains(_destination) &&
        !next.any((module) => module.id == _destination)) {
      _destination = 'tools';
    }
  }

  @override
  void dispose() {
    for (final module in _mountedModules) {
      module.dispose();
    }
    super.dispose();
  }

  Listenable get _changes =>
      Listenable.merge(widget.modules.map((module) => module.changes).toList());

  /// 進捗更新を必要とする部分だけを購読する。非表示ページは遷移時に再同期する。
  Widget _watch(
    Listenable changes,
    Widget Function() build, {
    bool active = true,
  }) => ListenableBuilder(
    listenable: Listenable.merge(active ? [changes] : const []),
    builder: (context, _) => build(),
  );

  /// Stack直下でIDを固定し、ツールの挿入・削除で既存ページを作り直さない。
  Widget _page(String id, Widget child) => Offstage(
    key: ValueKey('retained-$id'),
    offstage: _destination != id,
    child: TickerMode(enabled: _destination == id, child: child),
  );

  void _go(String id) => setState(() => _destination = id);
  String get _title => switch (_destination) {
    'tools' => 'ツール',
    'history' => '操作履歴',
    'settings' => '設定',
    _ => widget.modules.firstWhere((m) => m.id == _destination).title,
  };

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final phone = isPhoneLayout(context);
        final desktop = !phone && constraints.maxWidth >= 860;
        final modulePage = widget.modules.any((m) => m.id == _destination);
        final shortPhone = phone && MediaQuery.sizeOf(context).height < 480;
        return Scaffold(
          body: SafeArea(
            bottom: desktop || (shortPhone && modulePage),
            child: Row(
              children: [
                if (desktop) _sidebar(),
                Expanded(
                  key: const ValueKey('workspace'),
                  child: Column(
                    children: [
                      Container(
                        key: const ValueKey('app-header'),
                        constraints: BoxConstraints(minHeight: phone ? 56 : 64),
                        padding: EdgeInsets.symmetric(
                          horizontal: desktop ? 28 : 12,
                          vertical: phone ? (shortPhone ? 0 : 4) : 16,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          border: Border(
                            bottom: BorderSide(
                              color: context.colors.outlineVariant,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (!desktop && modulePage)
                              IconButton(
                                tooltip: 'ツール一覧',
                                onPressed: () => _go('tools'),
                                icon: const Icon(Icons.arrow_back),
                              ),
                            Expanded(
                              flex: phone ? 3 : 1,
                              child: Text(
                                _title,
                                style: phone
                                    ? Theme.of(context).textTheme.titleLarge!
                                          .copyWith(fontSize: 18)
                                    : Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (!desktop) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                flex: phone ? 4 : 1,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  heightFactor: 1,
                                  child: _connections(),
                                ),
                              ),
                            ] else
                              _watch(
                                _changes,
                                () =>
                                    widget.modules.any((module) => module.busy)
                                    ? const StatusPill('処理中', icon: Icons.sync)
                                    : const SizedBox.shrink(),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _changes,
                          builder: (context, child) => MobileFeedbackHost(
                            enabled: phone,
                            feedback: [
                              for (final module in widget.modules)
                                ?module.feedback,
                            ],
                            child: child!,
                          ),
                          // 通知だけの変化ではページ群を作り直さない。
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _page('tools', _scroll('tools', _tools())),
                              for (final module in widget.modules)
                                _page(
                                  module.id,
                                  _workspace(
                                    module.id,
                                    _watch(
                                      module.changes,
                                      module.buildPage,
                                      active: _destination == module.id,
                                    ),
                                  ),
                                ),
                              _page(
                                'history',
                                _withFeedback(
                                  'history',
                                  _watch(
                                    _changes,
                                    () => HistoryPage(
                                      modules: widget.modules,
                                      active: _destination == 'history',
                                    ),
                                    active: _destination == 'history',
                                  ),
                                  scroll: false,
                                ),
                              ),
                              _page(
                                'settings',
                                _withFeedback('settings', _settings()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
              desktop ||
                  (phone && MediaQuery.viewInsetsOf(context).bottom > 0) ||
                  (shortPhone && modulePage)
              ? null
              : NavigationBar(
                  height: phone ? 64 : null,
                  selectedIndex: _destination == 'history'
                      ? 1
                      : _destination == 'settings'
                      ? 2
                      : 0,
                  onDestinationSelected: (index) =>
                      _go(['tools', 'history', 'settings'][index]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      label: 'ツール',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history),
                      label: '操作履歴',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: '設定',
                    ),
                  ],
                ),
        );
      },
    ),
  );

  Widget _workspace(String id, Widget child) => Padding(
    key: PageStorageKey(id),
    padding: isPhoneLayout(context)
        ? const EdgeInsets.all(8)
        : MediaQuery.sizeOf(context).width >= 860
        ? const EdgeInsets.symmetric(horizontal: 24, vertical: 20)
        : const EdgeInsets.all(12),
    child: child,
  );

  Widget _withFeedback(String id, Widget child, {bool scroll = true}) => Column(
    key: ValueKey('page-$id'),
    children: [
      Expanded(child: scroll ? _scroll(id, child) : _workspace(id, child)),
      if (!isPhoneLayout(context))
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            children: [
              for (final module in widget.modules)
                _watch(
                  module.changes,
                  module.buildActivityFeedback,
                  active: _destination == id,
                ),
            ],
          ),
        ),
    ],
  );

  Widget _scroll(String id, Widget child) => SingleChildScrollView(
    key: PageStorageKey(id),
    primary: false,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width >= 860 ? 28 : 16),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 208,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      border: Border(right: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
            child: Row(
              children: [
                const OcoMark(size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'OCO',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _nav('tools', 'ツール', Icons.grid_view_outlined),
                for (final module in widget.modules)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _nav(module.id, module.title, module.icon),
                  ),
                const SizedBox(height: 28),
                _nav('history', '操作履歴', Icons.history),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _nav('settings', '設定', Icons.settings_outlined),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _connections(),
          ),
        ],
      ),
    ),
  );

  Widget _connections() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final module in widget.modules)
        _watch(module.changes, () {
          final connection = module.connection;
          return connection == null
              ? const SizedBox.shrink()
              : ConnectionIndicator(
                  key: ValueKey('connection-${module.id}'),
                  connection: connection,
                );
        }),
    ],
  );

  Widget _nav(String id, String label, IconData icon) {
    final selected = _destination == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? context.colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          selected: selected,
          selectedColor: context.colors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          key: ValueKey('nav-$id'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          minLeadingWidth: 20,
          leading: Icon(icon, size: 20),
          title: Text(label, style: const TextStyle(fontSize: 13)),
          onTap: () => _go(id),
        ),
      ),
    );
  }

  Widget _tools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final module in widget.modules)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Icon(module.icon, color: context.colors.primary),
              title: Text(
                module.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(module.description),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(module.id),
            ),
          ),
        ),
    ],
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('配色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            RadioGroup<AppAppearance>(
              groupValue: widget.appearance.value,
              onChanged: (value) {
                if (value != null) widget.appearance.select(value);
              },
              child: Column(
                children: [
                  for (final value in AppAppearance.values)
                    RadioListTile<AppAppearance>(
                      value: value,
                      title: Text(value.label),
                      contentPadding: EdgeInsets.zero,
                      secondary: _themeSample(value),
                    ),
                ],
              ),
            ),
            if (widget.appearance.error != null)
              MessageBanner(widget.appearance.error!, error: true),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (widget.runtime != null) ...[
        RuntimeSettings(controller: widget.runtime!),
        const SizedBox(height: 20),
      ],
      for (final module in widget.modules) ...[
        _watch(
          module.changes,
          module.buildSettings,
          active: _destination == 'settings',
        ),
        const SizedBox(height: 20),
      ],
      Text('バージョン 0.4.6', style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _themeSample(AppAppearance value) {
    final scheme = buildTheme(value).colorScheme;
    return Container(
      width: 44,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 4, color: scheme.primary),
      ),
    );
  }
}
