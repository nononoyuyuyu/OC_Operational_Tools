package jp.nononoyuyuyu.open_campus_organizer

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class OcoRuntime(private val app: OcoApplication, messenger: BinaryMessenger) {
    companion object { const val PERMISSION_REQUEST = 6104; const val PROGRESS_ID = 6105 }
    private val channel = MethodChannel(messenger, "jp.nononoyuyuyu.open_campus_organizer/runtime")
    private val notifications = app.getSystemService(NotificationManager::class.java)
    var activity: MainActivity? = null
    var foreground = true
    var active = false
        private set
    private var permissionCompletion: (() -> Unit)? = null
    private var title = "Open Campus Organizer"
    private var message = "準備中"
    private var done = 0
    private var total = 0
    private var lastNotification = 0L

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel("oco_progress", "処理の進捗", NotificationManager.IMPORTANCE_LOW))
            notifications.createNotificationChannel(NotificationChannel("oco_results", "処理結果", NotificationManager.IMPORTANCE_DEFAULT))
        }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> { result.success(null) }
                    "begin" -> {
                        title = call.argument<String>("title") ?: "Open Campus Organizer"
                        message = "準備中"; done = 0; total = 0
                        val begin = {
                            try {
                                val intent = Intent(app, OcoTaskService::class.java)
                                if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
                                active = true
                                result.success(null)
                            } catch (_: Exception) { result.error("background_unavailable", "バックグラウンド処理を開始できません。アプリを開いて再開してください。", null) }
                        }
                        val current = activity
                        if (Build.VERSION.SDK_INT >= 33 && current != null &&
                            app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            permissionCompletion = begin
                            current.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
                        } else begin()
                    }
                    "progress" -> {
                        message = call.argument<String>("message") ?: message
                        done = call.argument<Number>("done")?.toInt() ?: 0
                        total = call.argument<Number>("total")?.toInt() ?: 0
                        val now = android.os.SystemClock.elapsedRealtime()
                        if (active && now - lastNotification >= 500) {
                            notify(PROGRESS_ID, progressNotification()); lastNotification = now
                        }
                        result.success(null)
                    }
                    "finish" -> {
                        val remaining = call.argument<Number>("remaining")?.toInt() ?: 0
                        val id = call.argument<String>("id") ?: "result"
                        val content = call.argument<String>("message") ?: "処理が終了しました。"
                        if (remaining == 0) {
                            active = false
                            app.stopService(Intent(app, OcoTaskService::class.java))
                        }
                        notify(10000 + (id.hashCode() and 0x0fffffff), builder("oco_results")
                            .setContentTitle(title).setContentText(content)
                            .setStyle(Notification.BigTextStyle().bigText(content)).setAutoCancel(true).build())
                        result.success(null)
                        if (remaining == 0 && call.argument<Boolean>("autoClose") == true && !foreground) app.finishInBackground()
                    }
                    "exit" -> { result.success(null); activity?.finishAndRemoveTask() }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("runtime_unavailable", "通知またはバックグラウンド処理を利用できません。", null) }
        }
    }
    fun permissionResult() {
        if (Build.VERSION.SDK_INT >= 33 && app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) event("notificationsDenied")
        val completion = permissionCompletion; permissionCompletion = null; completion?.invoke()
    }
    fun event(name: String) { Handler(Looper.getMainLooper()).post { channel.invokeMethod(name, null) } }
    private fun notify(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= 33 && app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        if (Build.VERSION.SDK_INT >= 24 && !notifications.areNotificationsEnabled()) return
        try { notifications.notify(id, notification) } catch (_: SecurityException) { event("notificationsDenied") }
    }
    private fun builder(channelId: String): Notification.Builder {
        val open = PendingIntent.getActivity(app, 0, Intent(app, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(app, channelId) else Notification.Builder(app))
            .setSmallIcon(R.drawable.ic_stat_oco).setContentIntent(open).setOnlyAlertOnce(true)
    }
    fun progressNotification(): Notification {
        val cancel = PendingIntent.getService(app, 1, Intent(app, OcoTaskService::class.java).setAction("cancel"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val text = if (total > 0) "$message · $done / $total" else message
        return builder("oco_progress").setContentTitle(title).setContentText(text).setOngoing(true)
            .setProgress(total, done, total <= 0)
            .addAction(Notification.Action.Builder(null, "中止", cancel).build()).build()
    }
    fun suspendedBySystem() {
        active = false
        event("suspend")
        notify(PROGRESS_ID + 1, builder("oco_results").setContentTitle("処理を保存しました")
            .setContentText("アプリを開くと再開します。").setAutoCancel(true).build())
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
