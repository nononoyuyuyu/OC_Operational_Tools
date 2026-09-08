package jp.nononoyuyuyu.open_campus_organizer

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Intent
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.*
import org.junit.Test

class LauncherLifecycleTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private fun resumedMain(): MainActivity? {
        var activity: MainActivity? = null
        instrumentation.runOnMainSync {
            activity = ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED).filterIsInstance<MainActivity>().singleOrNull()
        }
        return activity
    }

    private fun openLauncher(): MainActivity {
        val context = instrumentation.targetContext
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val deadline = SystemClock.elapsedRealtime() + 15000
        while (SystemClock.elapsedRealtime() < deadline) {
            resumedMain()?.let { return it }
            SystemClock.sleep(100)
        }
        throw AssertionError("ホーム画面の入口から操作画面が開く")
    }

    @Test
    fun themeChangeKeepsLauncherStartedActivityResumed() {
        val context = instrumentation.targetContext
        instrumentation.runOnMainSync { LauncherAppearance.applyTheme(context, "dark") }
        val activity = openLauncher()
        try {
            val app = context.applicationContext as OcoApplication
            val engine = app.engine()
            // 初回の既定色ではFlutterの保存配色読込も待ち、続けて全色を切り替える。
            for (theme in listOf("dark", "orange", "sage", "warm", "light", "dark")) {
                instrumentation.runOnMainSync { LauncherAppearance.applyTheme(context, theme) }
                // DONT_KILL_APPのパッケージ変更通知は遅延するため、その配信後も確認する。
                SystemClock.sleep(12000)
                assertFalse("テーマ変更でActivityを終了しない: $theme", activity.isFinishing)
                assertFalse("テーマ変更でActivityを破棄しない: $theme", activity.isDestroyed)
                assertSame("操作中の画面を前面に保つ: $theme", activity, resumedMain())
                instrumentation.runOnMainSync {
                    assertSame("共有エンジンを作り直さない", engine, app.engine())
                    assertTrue("背景への誤通知を起こさない", app.runtime!!.foreground)
                }
                val tasks = context.getSystemService(ActivityManager::class.java).appTasks
                    .mapNotNull { it.taskInfo }
                assertEquals("入口のタスクを残さない", 1, tasks.size)
                assertEquals(ComponentName(context, MainActivity::class.java), tasks.single().baseActivity)
                assertEquals("選んだアイコンを公開する", "${context.packageName}.Launcher_$theme",
                    context.packageManager.getLaunchIntentForPackage(context.packageName)!!.component!!.className)

                instrumentation.runOnMainSync { activity.moveTaskToBack(true) }
                SystemClock.sleep(500)
                assertNull("ホームへ戻る", resumedMain())
                assertSame("変更後のアイコンから同じ操作画面へ戻る", activity, openLauncher())
            }
            // 通知が直接MainActivityを開く経路でも同じ画面に復帰する。
            instrumentation.runOnMainSync { activity.moveTaskToBack(true) }
            SystemClock.sleep(500)
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val deadline = SystemClock.elapsedRealtime() + 5000
            while (resumedMain() == null && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
            assertSame("通知から同じ画面へ復帰する", activity, resumedMain())
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }
}
