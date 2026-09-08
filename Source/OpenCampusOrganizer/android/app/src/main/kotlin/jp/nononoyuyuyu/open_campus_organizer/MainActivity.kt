package jp.nononoyuyuyu.open_campus_organizer

import io.flutter.embedding.android.FlutterActivity
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val app get() = application as OcoApplication
    override fun provideFlutterEngine(context: Context): FlutterEngine = app.engine()
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        app.runtime?.activity = this
    }
    override fun onResume() {
        super.onResume()
        app.runtime?.activity = this
        app.runtime?.foreground = true
        app.runtime?.event("foreground")
    }
    override fun onStop() {
        app.runtime?.foreground = false
        app.runtime?.event("background")
        super.onStop()
    }
    override fun onDestroy() {
        if (app.runtime?.activity === this) app.runtime?.activity = null
        super.onDestroy()
    }
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == OcoRuntime.PERMISSION_REQUEST) app.runtime?.permissionResult()
    }
}
