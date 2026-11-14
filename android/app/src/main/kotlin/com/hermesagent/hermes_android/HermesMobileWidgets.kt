package com.hermesagent.hermes_android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Wave 1 home-screen widgets. The Flutter side (HermesMobileWidgetBridge) writes the
 * values into the app's SharedPreferences ("FlutterSharedPreferences", keys
 * prefixed "flutter.") and calls `update` on this channel; the providers read
 * those values directly, so a widget also redraws from the last values after a
 * reboot without starting Flutter.
 */
object HermesMobileWidgets {
    const val CHANNEL = "com.hermesagent.hermesMobile/widgets"
    const val EXTRA_ACTION = "hermes_mobile_action"
    private const val QUICK_CHAT = "com.hermesagent.hermes_android.action.QUICK_CHAT"

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    runCatching { updateAll(app) }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        listOf(
            HermesMobileBriefWidget::class.java,
            HermesMobilePanelWidget::class.java,
            HermesMobileNeedsYouWidget::class.java,
            HermesMobileQuickAskWidget::class.java,
        ).forEach { cls ->
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, cls).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun str(context: Context, key: String, fallback: String = ""): String =
        (prefs(context).all["flutter.$key"] as? String) ?: fallback

    fun num(context: Context, key: String): Long =
        (prefs(context).all["flutter.$key"] as? Number)?.toLong() ?: 0L

    /** Opens Hermes with a Petasos launch action (see MainActivity.launchActionFor). */
    fun launch(context: Context, hermesMobileAction: String?, requestCode: Int): PendingIntent {
        val intent = if (hermesMobileAction == null) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
        } else {
            Intent(context, MainActivity::class.java).apply {
                action = QUICK_CHAT
                putExtra(EXTRA_ACTION, hermesMobileAction)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

abstract class HermesMobileWidgetBase : AppWidgetProvider() {
    abstract fun build(context: Context): RemoteViews

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = runCatching { build(context) }.getOrNull() ?: return
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}

class HermesMobileBriefWidget : HermesMobileWidgetBase() {
    override fun build(context: Context) =
        RemoteViews(context.packageName, R.layout.hermes_mobile_widget_brief).apply {
            setTextViewText(R.id.hermes_mobile_brief_title, HermesMobileWidgets.str(context, "hermes_mobile.widget.brief_title", "Hermes brief"))
            setTextViewText(R.id.hermes_mobile_brief_body, HermesMobileWidgets.str(context, "hermes_mobile.widget.brief_body", "Open Hermes to load today's brief."))
            val updated = HermesMobileWidgets.str(context, "hermes_mobile.widget.updated")
            setTextViewText(R.id.hermes_mobile_brief_updated, if (updated.isEmpty()) "" else "Updated $updated")
            setOnClickPendingIntent(R.id.hermes_mobile_root, HermesMobileWidgets.launch(context, "brief", 7101))
        }
}

class HermesMobilePanelWidget : HermesMobileWidgetBase() {
    override fun build(context: Context) =
        RemoteViews(context.packageName, R.layout.hermes_mobile_widget_panel).apply {
            setTextViewText(R.id.hermes_mobile_panel_title, HermesMobileWidgets.str(context, "hermes_mobile.widget.panel_title", "Hermes panel"))
            setTextViewText(R.id.hermes_mobile_panel_value, HermesMobileWidgets.str(context, "hermes_mobile.widget.panel_value", "—"))
            setTextViewText(R.id.hermes_mobile_panel_sub, HermesMobileWidgets.str(context, "hermes_mobile.widget.panel_sub"))
            setOnClickPendingIntent(R.id.hermes_mobile_root, HermesMobileWidgets.launch(context, null, 7102))
        }
}

class HermesMobileNeedsYouWidget : HermesMobileWidgetBase() {
    override fun build(context: Context) =
        RemoteViews(context.packageName, R.layout.hermes_mobile_widget_needs).apply {
            setTextViewText(R.id.hermes_mobile_needs_count, HermesMobileWidgets.num(context, "hermes_mobile.widget.needs_you").toString())
            setTextViewText(R.id.hermes_mobile_needs_top, HermesMobileWidgets.str(context, "hermes_mobile.widget.needs_top", "All caught up"))
            setOnClickPendingIntent(R.id.hermes_mobile_root, HermesMobileWidgets.launch(context, "needs", 7103))
        }
}

class HermesMobileQuickAskWidget : HermesMobileWidgetBase() {
    override fun build(context: Context) =
        RemoteViews(context.packageName, R.layout.hermes_mobile_widget_ask).apply {
            setOnClickPendingIntent(R.id.hermes_mobile_ask, HermesMobileWidgets.launch(context, "ask", 7104))
            setOnClickPendingIntent(R.id.hermes_mobile_voice, HermesMobileWidgets.launch(context, "voice", 7105))
        }
}
