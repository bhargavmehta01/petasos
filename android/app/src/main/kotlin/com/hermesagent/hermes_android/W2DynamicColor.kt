package com.hermesagent.hermes_android

import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Wave 2: exposes the Material You wallpaper accents to the Petasos theme. */
object W2DynamicColor {
    private const val CHANNEL = "hermes_mobile/w2_dynamic_color"

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "accents" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val res = app.resources
                        result.success(
                            mapOf(
                                "light" to res.getColor(android.R.color.system_accent1_600, app.theme),
                                "dark" to res.getColor(android.R.color.system_accent1_200, app.theme),
                                "lightSoft" to res.getColor(android.R.color.system_accent1_100, app.theme),
                                "darkSoft" to res.getColor(android.R.color.system_accent1_800, app.theme),
                            ),
                        )
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
