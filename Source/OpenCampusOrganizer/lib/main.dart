import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/oco_app.dart';
import 'core/appearance.dart';
import 'core/pending_task.dart';
import 'core/runtime_controller.dart';
import 'core/platform/file_export.dart';
import 'core/platform/memory_store.dart';
import 'core/platform/stores.dart';
import 'core/platform/window_appearance.dart';
import 'core/scoped_store.dart';
import 'features/kakutei/application/kakutei_controller.dart';
import 'features/kakutei/data/demo_gateway.dart';
import 'features/kakutei/data/discord_api.dart';
import 'features/kakutei/data/discord_transport.dart';
import 'features/kakutei/data/operation_journal.dart';
import 'features/kakutei/data/saved_settings.dart';
import 'features/kakutei/kakutei_module.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // ブラウザでは実BotのTokenを扱わない。ネイティブ配布とは接続先を分ける。
  const demo = kIsWeb || bool.fromEnvironment('OCO_DEMO');
  final store = demo ? MemoryStore() : createLocalStore();
  final runtime = RuntimeController(
    ScopedStore(store, 'app_v1'),
    NativeRuntimePlatform(),
  );
  final controller = KakuteiController(
    gateway: demo ? DemoGateway() : DiscordApi(DiscordTransport()),
    credentials: demo ? MemoryStore() : createCredentialStore(),
    journal: StoredOperationJournal(ScopedStore(store, 'kakutei_v1')),
    settingsStore: KakuteiSettingsStore(ScopedStore(store, 'kakutei_v1')),
    taskStore: demo ? null : PendingTaskStore(ScopedStore(store, 'kakutei_v1')),
    taskHost: runtime,
    exports: FileExport(),
    demoOnly: demo,
  );
  runtime.register(
    pause: controller.suspendTasks,
    resume: controller.resumePending,
    cancel: controller.cancel,
  );
  runApp(
    OcoApp(
      modules: [KakuteiModule(controller)],
      runtime: runtime,
      appearance: AppearanceController(
        ScopedStore(store, 'app_v1'),
        updatePlatformAppearance: updateWindowAppearance,
      ),
    ),
  );
}
