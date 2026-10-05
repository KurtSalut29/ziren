package com.ziren.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val releaseScreen = Runnable {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenPolicy(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyLockScreenPolicy(intent)
    }

    /** Leaving the screen ends the exception: the next wake needs the unlock. */
    override fun onStop() {
        super.onStop()
        applyLockScreenPolicy(null)
    }

    /**
     * A responder's alarm (an assignment, or an incident near them) opens the
     * app over the lock screen and wakes the display, the way an incoming call
     * does. Only then: set on the activity permanently (manifest
     * showWhenLocked) it would also put Ziren - names, reports, addresses -
     * over the lock screen of any phone left on that screen, for anyone who
     * picks it up. The payload is the one flutter_local_notifications puts on
     * the notification's intent ("assignment:<id>" / "nearby:<id>").
     */
    private fun applyLockScreenPolicy(intent: Intent?) {
        val payload = intent?.getStringExtra("payload") ?: ""
        val fromAlert = payload.startsWith("assignment:") || payload.startsWith("nearby:")
        // Keep the screen on while the alert is up, for up to two minutes. The
        // lock screen's own timeout is a few seconds: on-device check
        // 2026-10-06, the alert came up over the lock screen and the display
        // went dark again before anyone could have read it.
        handler.removeCallbacks(releaseScreen)
        if (fromAlert) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            handler.postDelayed(releaseScreen, 120_000L)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(fromAlert)
            setTurnScreenOn(fromAlert)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (fromAlert) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
