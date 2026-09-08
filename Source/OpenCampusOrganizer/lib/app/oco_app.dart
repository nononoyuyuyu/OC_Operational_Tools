import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/tool_module.dart';
import '../core/appearance.dart';
import '../core/platform/memory_store.dart';
import '../design/theme.dart';
import '../design/system_bars.dart';
import 'app_shell.dart';
import '../core/runtime_controller.dart';

class OcoApp extends StatefulWidget {
  const OcoApp({
    super.key,
    required this.modules,
    this.appearance,
    this.runtime,
  });
  final List<ToolModule> modules;
  final AppearanceController? appearance;
  final RuntimeController? runtime;
  @override
  State<OcoApp> createState() => _OcoAppState();
}

class _OcoAppState extends State<OcoApp> {
  final navigator = GlobalKey<NavigatorState>();
  late final appearance =
      widget.appearance ?? AppearanceController(MemoryStore());
  @override
  void initState() {
    super.initState();
    appearance.initialize();
    widget.runtime?.initialize();
    widget.runtime?.confirmExit = () async {
      final context = navigator.currentContext;
      if (context == null) return false;
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('アプリを終了しますか？'),
              content: Text(
                widget.runtime!.busy
                    ? '処理を保存して終了します。未完了の処理は次回起動時に再開します。'
                    : 'Open Campus Organizerを終了します。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('戻る'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('終了'),
                ),
              ],
            ),
          ) ??
          false;
    };
  }

  @override
  void dispose() {
    appearance.dispose();
    widget.runtime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      title: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'OC'
          : 'Open Campus Organizer',
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(appearance.value),
      locale: const Locale('ja'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ja')],
      builder: (context, child) => ThemedSystemBars(child: child!),
      home: AppShell(
        modules: widget.modules,
        appearance: appearance,
        runtime: widget.runtime,
      ),
    ),
  );
}
