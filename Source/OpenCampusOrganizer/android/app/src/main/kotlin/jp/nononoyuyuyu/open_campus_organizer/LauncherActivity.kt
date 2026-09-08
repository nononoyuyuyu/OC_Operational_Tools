package jp.nononoyuyuyu.open_campus_organizer

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** 配色で無効化される入口を、操作画面のタスクに残さない。 */
class LauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 別のtaskAffinityを持つMainActivityを起動する。既存画面はsingleTaskで再利用する。
        // 外部から入口へ渡されたIntentのフラグや追加情報は転送しない。
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
}
