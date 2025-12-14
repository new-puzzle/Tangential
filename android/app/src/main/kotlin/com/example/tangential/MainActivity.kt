package com.example.tangential

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.tangential/background"
    private val TAG = "TangentialBackground"
    
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var methodChannel: MethodChannel? = null
    private var screenReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackground" -> {
                    val success = acquireWakeLock()
                    registerScreenReceiver()
                    Log.d(TAG, "startBackground called, success: $success")
                    result.success(success)
                }
                "stopBackground" -> {
                    releaseWakeLock()
                    unregisterScreenReceiver()
                    Log.d(TAG, "stopBackground called")
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    private fun acquireWakeLock(): Boolean {
        return try {
            // Acquire CPU wake lock
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Tangential::ConversationWakeLock"
            )
            // Acquire for 2 hours max (safety limit)
            wakeLock?.acquire(2 * 60 * 60 * 1000L)
            Log.d(TAG, "Wake lock acquired (PARTIAL_WAKE_LOCK)")
            
            // Acquire WiFi lock to keep network alive
            try {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Tangential::WifiLock")
                wifiLock?.acquire()
                Log.d(TAG, "WiFi lock acquired (WIFI_MODE_FULL_HIGH_PERF)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to acquire WiFi lock: ${e.message}")
                // Continue without WiFi lock - not critical
            }
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock: ${e.message}")
            false
        }
    }

    private fun releaseWakeLock() {
        // Release WiFi lock
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
                Log.d(TAG, "WiFi lock released")
            }
            wifiLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release WiFi lock: ${e.message}")
        }
        
        // Release CPU wake lock
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "Wake lock released")
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock: ${e.message}")
        }
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) return
        
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        Log.d(TAG, "Screen OFF detected")
                        methodChannel?.invokeMethod("onScreenOff", null)
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        Log.d(TAG, "Screen ON detected")
                        methodChannel?.invokeMethod("onScreenOn", null)
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        Log.d(TAG, "Screen receiver registered")
    }

    private fun unregisterScreenReceiver() {
        try {
            screenReceiver?.let {
                unregisterReceiver(it)
                Log.d(TAG, "Screen receiver unregistered")
            }
            screenReceiver = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister screen receiver: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        unregisterScreenReceiver()
        super.onDestroy()
    }
}
