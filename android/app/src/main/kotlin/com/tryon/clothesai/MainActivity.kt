package com.tryon.clothesai

import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.Window
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.tryon.clothesai/native_api_key"
    private val nativeProvider = NativeApiKeyProvider()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        unlockMaximumRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        unlockMaximumRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApiKey" -> {
                    val providerName = call.argument<String>("provider") ?: ""
                    val apiKey = nativeProvider.getApiKey(providerName)
                    result.success(apiKey)
                }
                "getMaxFps" -> {
                    result.success(getCurrentDisplayRefreshRate())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Unlocks the maximum display refresh rate supported by the user's phone
     * (e.g. 120Hz, 144Hz, 90Hz, 60Hz).
     */
    private fun unlockMaximumRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }

                if (display != null) {
                    val supportedModes = display.supportedModes
                    var maxRateMode: Display.Mode? = null
                    var highestRate = 0f

                    for (mode in supportedModes) {
                        if (mode.refreshRate > highestRate) {
                            highestRate = mode.refreshRate
                            maxRateMode = mode
                        }
                    }

                    if (maxRateMode != null) {
                        val params = window.attributes
                        params.preferredDisplayModeId = maxRateMode.modeId
                        window.attributes = params
                    }

                }
            } catch (_: Exception) {
                // Graceful fallback
            }
        }
    }

    private fun getCurrentDisplayRefreshRate(): Double {
        return try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            display?.refreshRate?.toDouble() ?: 60.0
        } catch (_: Exception) {
            60.0
        }
    }
}
