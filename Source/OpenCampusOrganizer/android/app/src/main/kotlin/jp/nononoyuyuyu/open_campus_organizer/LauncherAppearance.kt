package jp.nononoyuyuyu.open_campus_organizer

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** 起動先のActivityと、ホーム画面に公開するアイコンを分離する。 */
class LauncherAppearance(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "jp.nononoyuyuyu.open_campus_organizer/appearance")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setTheme") {
                result.notImplemented()
            } else if (call.arguments !is String || call.arguments !in THEMES) {
                result.error("invalid_theme", "配色を確認してください。", null)
            } else {
                try {
                    applyTheme(context, call.arguments as String)
                    result.success(null)
                } catch (_: Exception) {
                    result.error("icon_unavailable", "アイコンを変更できませんでした。", null)
                }
            }
        }
    }

    fun dispose() = channel.setMethodCallHandler(null)

    companion object {
        val THEMES = listOf("dark", "light", "warm", "sage", "orange")

        fun applyTheme(context: Context, theme: String) {
            require(theme in THEMES)
            val manager = context.packageManager
            val selected = ComponentName(context.packageName, "${context.packageName}.Launcher_$theme")
            val states = THEMES.map { name ->
                val component = ComponentName(context.packageName, "${context.packageName}.Launcher_$name")
                component to if (component == selected) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }.filter { (component, state) -> manager.getComponentEnabledSetting(component) != state }
            if (states.isEmpty()) return
            if (Build.VERSION.SDK_INT >= 33) {
                manager.setComponentEnabledSettings(states.map { (component, state) ->
                    PackageManager.ComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
                })
            } else {
                // 旧OSでは有効化を先行し、切替途中でも起動口を失わない。
                states.sortedBy { if (it.first == selected) 0 else 1 }.forEach { (component, state) ->
                    manager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
                }
            }
        }
    }
}
