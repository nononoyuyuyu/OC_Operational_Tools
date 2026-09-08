package jp.nononoyuyuyu.open_campus_organizer

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assert.*

@Suppress("DEPRECATION")
class LauncherAppearanceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    @Test
    fun testAllThemesKeepOneLauncherAndMainActivity() {
        val context = instrumentation.targetContext
        val manager = context.packageManager
        val components = LauncherAppearance.THEMES.map {
            ComponentName(context.packageName, "${context.packageName}.Launcher_$it")
        }
        val original = components.associateWith { manager.getComponentEnabledSetting(it) }
        try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName)
            val icons = mutableSetOf<Int>()
            repeat(2) {
                for (theme in LauncherAppearance.THEMES) {
                    instrumentation.runOnMainSync { LauncherAppearance.applyTheme(context, theme) }
                    val activities = manager.queryIntentActivities(intent, 0)
                    assertEquals("公開する起動アイコンは1個", 1, activities.size)
                    val activity = activities.single().activityInfo
                    assertEquals("${context.packageName}.Launcher_$theme", activity.name)
                    assertEquals("${context.packageName}.LauncherActivity", activity.targetActivity)
                    assertNotNull(activity.loadIcon(manager))
                    assertEquals("OC", activity.loadLabel(manager).toString())
                    icons.add(activity.icon)
                    val main = manager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
                    assertTrue("通知からの起動先を無効化しない", main.enabled)
                    assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, manager.getComponentEnabledSetting(ComponentName(context, MainActivity::class.java)))
                }
            }
            assertEquals(5, icons.size)
            try {
                LauncherAppearance.applyTheme(context, "unknown")
                fail("不明な配色を拒否する")
            } catch (_: IllegalArgumentException) { }
            assertEquals("${context.packageName}.Launcher_orange", manager.queryIntentActivities(intent, 0).single().activityInfo.name)
        } finally {
            // テスト前の設定へ戻す。有効な入口を先に戻す。
            original.entries.sortedBy { if (it.value == PackageManager.COMPONENT_ENABLED_STATE_DISABLED) 1 else 0 }.forEach {
                manager.setComponentEnabledSetting(it.key, it.value, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
