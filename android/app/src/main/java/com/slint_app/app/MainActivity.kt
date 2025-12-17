package com.slint_app.app

import android.app.NativeActivity
import android.os.Bundle
import android.view.KeyEvent
import android.util.Log

class MainActivity : NativeActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Custom initialization if needed
        Log.d("MainActivity", "onCreate called")
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            // Handle back button or gesture here
            Log.d("MainActivity", "Back button pressed")
            // TODO: Add custom back handling logic
            return true // Consume the event
        }
        return super.onKeyDown(keyCode, event)
    }
}