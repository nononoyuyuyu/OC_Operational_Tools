package jp.nononoyuyuyu.open_campus_organizer

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class OcoApplication : Application() {
    private var cachedEngine: FlutterEngine? = null
    private var appearance: LauncherAppearance? = null
    var runtime: OcoRuntime? = null
        private set
    @Synchronized fun engine(): FlutterEngine {
        cachedEngine?.let { return it }
        val next = FlutterEngine(this)
        cachedEngine = next
        runtime = OcoRuntime(this, next.dartExecutor.binaryMessenger)
        appearance = LauncherAppearance(this, next.dartExecutor.binaryMessenger)
        next.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return next
    }
    fun finishInBackground() {
        val current = runtime ?: return
        if (current.foreground || current.active) return
        current.activity?.finishAndRemoveTask()
        // UIとサービスが共有したエンジンを、処理の保存・通知後にだけ破棄する。
        android.os.Handler(mainLooper).postDelayed({
            if (runtime === current && !current.foreground && !current.active) {
                current.dispose()
                appearance?.dispose()
                appearance = null
                cachedEngine?.destroy()
                cachedEngine = null
                runtime = null
            }
        }, 500)
    }
}
