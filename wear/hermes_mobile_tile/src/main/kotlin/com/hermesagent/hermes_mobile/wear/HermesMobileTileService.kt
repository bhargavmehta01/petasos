package com.hermesagent.hermesMobile.wear

import android.content.Context
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Hermes glance tile: watchers that changed, promises due, overnight actions.
 * Reads GET <dashboard>/api/plugins/hermes_mobile/w4/glance (Petasos server plugin, Wave 4).
 *
 * Stub status: the URL and session token come from SharedPreferences
 * "hermes_mobile_tile" (keys "glance_url", "token"), set over adb for now. Syncing them
 * from the phone over the Wear Data Layer is the follow-up (see wear/README.md).
 */
class HermesMobileTileService : TileService() {
    private val executor = MoreExecutors.listeningDecorator(Executors.newSingleThreadExecutor())

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> = executor.submit<TileBuilders.Tile> {
        val glance = fetchGlance(this)
        TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(15 * 60 * 1000L)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout(glance)))
            .build()
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> = executor.submit<ResourceBuilders.Resources> {
        ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).build()
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    private fun text(value: String, size: Float, color: Int): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setMaxLines(2)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(androidx.wear.protolayout.DimensionBuilders.sp(size))
                    .setColor(argb(color))
                    .build(),
            )
            .build()

    private fun layout(g: Glance?): LayoutElementBuilders.LayoutElement {
        val column = LayoutElementBuilders.Column.Builder()
        if (g == null) {
            column.addContent(text("Hermes", 16f, ACCENT))
            column.addContent(text("Open Hermes on your phone to set up the tile", 12f, MUTED))
        } else {
            column.addContent(text(g.headline ?: "All quiet", 14f, WHITE))
            column.addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(6f)).build())
            column.addContent(text("${g.watchersChanged} watcher alerts", 12f, ACCENT))
            column.addContent(text("${g.commitmentsDue} due today", 12f, MUTED))
            column.addContent(text("${g.overnightActions} done overnight", 12f, MUTED))
        }
        return LayoutElementBuilders.Box.Builder().addContent(column.build()).build()
    }

    data class Glance(
        val watchersChanged: Int,
        val commitmentsDue: Int,
        val overnightActions: Int,
        val headline: String?,
    )

    companion object {
        private const val RESOURCES_VERSION = "1"
        private const val ACCENT = 0xFF6E8CF0.toInt()
        private const val WHITE = 0xFFF2F2F0.toInt()
        private const val MUTED = 0xFFA3A29E.toInt()

        fun fetchGlance(context: Context): Glance? {
            val prefs = context.getSharedPreferences("hermes_mobile_tile", Context.MODE_PRIVATE)
            val url = prefs.getString("glance_url", null) ?: return null
            return runCatching {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                prefs.getString("token", null)?.let {
                    conn.setRequestProperty("X-Hermes-Session-Token", it)
                }
                conn.inputStream.bufferedReader().use { r ->
                    val j = JSONObject(r.readText())
                    Glance(
                        j.optInt("watchers_changed"),
                        j.optInt("commitments_due"),
                        j.optInt("overnight_actions"),
                        j.optString("headline").takeIf { it.isNotBlank() && it != "null" },
                    )
                }
            }.getOrNull()
        }
    }
}
