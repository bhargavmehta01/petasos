package com.hermesagent.hermes_android

// --- wave4 --- Petasos context triggers (opt-in). See docs/hermes-mobile-wave4-novel.md.

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Listens for the on-device moments the user opted into (charging, car
 * Bluetooth, arriving home, a calendar event ending) and tells Dart through
 * `signal`. Dart decides whether to run anything (night window, cooldown,
 * proactivity). Listeners live only while the app process is alive; nothing is
 * registered until the user turns a trigger on, and nothing leaves the phone
 * except the prompt Dart sends to Hermes.
 */
class HermesMobileContextTriggers private constructor(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    private val app: Context = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var powerReceiver: BroadcastReceiver? = null
    private var btReceiver: BroadcastReceiver? = null
    private var homeReceiver: BroadcastReceiver? = null
    private var homeIntent: PendingIntent? = null
    private var calendarPoll: Runnable? = null
    private var lastCalendarCheck = System.currentTimeMillis()

    companion object {
        private const val CHANNEL = "com.hermesagent.hermes_android/hermes_mobile_context"
        private const val HOME_ACTION = "com.hermesagent.hermes_android.HERMES_MOBILE_ARRIVE_HOME"
        private const val PERMISSION_REQUEST = 4404
        private const val CALENDAR_POLL_MS = 60_000L
        private const val HOME_RADIUS_M = 150f

        fun install(activity: Activity, engine: FlutterEngine): HermesMobileContextTriggers {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            val plugin = HermesMobileContextTriggers(activity, channel)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        val raw = call.argument<List<Map<String, Any?>>>("triggers") ?: emptyList()
                        plugin.configure(raw)
                        result.success(true)
                    }
                    "requestPermission" -> {
                        result.success(plugin.requestPermission(call.argument<String>("kind") ?: ""))
                    }
                    else -> result.notImplemented()
                }
            }
            return plugin
        }
    }

    private fun signal(kind: String, param: String? = null) {
        main.post {
            runCatching { channel.invokeMethod("signal", mapOf("kind" to kind, "param" to param)) }
        }
    }

    private fun granted(permission: String): Boolean =
        app.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionsFor(kind: String): Array<String> = when (kind) {
        "arrive_home" -> arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        "car_bluetooth" ->
            if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_CONNECT) else emptyArray()
        "calendar_end" -> arrayOf(Manifest.permission.READ_CALENDAR)
        else -> emptyArray()
    }

    /** True when already granted; otherwise asks and returns false for now. */
    fun requestPermission(kind: String): Boolean {
        val needed = permissionsFor(kind).filterNot(::granted)
        if (needed.isEmpty()) return true
        if (!activity.isFinishing) {
            runCatching { activity.requestPermissions(needed.toTypedArray(), PERMISSION_REQUEST) }
        }
        return false
    }

    fun configure(triggers: List<Map<String, Any?>>) {
        val on = triggers.filter { it["enabled"] == true }.associateBy { it["kind"] as? String ?: "" }
        if (on.containsKey("charging_night")) startPower() else stopPower()
        if (on.containsKey("car_bluetooth")) startBluetooth() else stopBluetooth()
        val home = on["arrive_home"]?.get("param") as? String
        if (home != null) startHome(home) else stopHome()
        if (on.containsKey("calendar_end")) startCalendar() else stopCalendar()
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun register(receiver: BroadcastReceiver, filter: IntentFilter, exported: Boolean) {
        if (Build.VERSION.SDK_INT >= 33) {
            val flag = if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED
            app.registerReceiver(receiver, filter, flag)
        } else {
            app.registerReceiver(receiver, filter)
        }
    }

    private fun unregister(receiver: BroadcastReceiver?) {
        if (receiver != null) runCatching { app.unregisterReceiver(receiver) }
    }

    // ── charging ────────────────────────────────────────────────────────

    private fun startPower() {
        if (powerReceiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_POWER_CONNECTED) signal("charging_night")
            }
        }
        register(r, IntentFilter(Intent.ACTION_POWER_CONNECTED), exported = true)
        powerReceiver = r
    }

    private fun stopPower() {
        unregister(powerReceiver)
        powerReceiver = null
    }

    // ── car Bluetooth ───────────────────────────────────────────────────

    private fun startBluetooth() {
        if (btReceiver != null) return
        val r = object : BroadcastReceiver() {
            @SuppressLint("MissingPermission")
            override fun onReceive(context: Context?, intent: Intent?) {
                val i = intent ?: return
                if (i.action != BluetoothDevice.ACTION_ACL_CONNECTED) return
                val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                    i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    i.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                }
                val canName = Build.VERSION.SDK_INT < 31 || granted(Manifest.permission.BLUETOOTH_CONNECT)
                val name = if (canName) runCatching { device?.name }.getOrNull() else null
                // Only car kits: audio/video major class, or an unknown device we cannot name.
                val major = runCatching { device?.bluetoothClass?.majorDeviceClass }.getOrNull()
                val isCarLike = major == null || major == android.bluetooth.BluetoothClass.Device.Major.AUDIO_VIDEO
                if (isCarLike) signal("car_bluetooth", name)
            }
        }
        register(r, IntentFilter(BluetoothDevice.ACTION_ACL_CONNECTED), exported = true)
        btReceiver = r
    }

    private fun stopBluetooth() {
        unregister(btReceiver)
        btReceiver = null
    }

    // ── arrive home (proximity alert) ───────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startHome(param: String) {
        stopHome()
        val parts = param.split(",").map { it.trim() }
        val lat = parts.getOrNull(0)?.toDoubleOrNull() ?: return
        val lng = parts.getOrNull(1)?.toDoubleOrNull() ?: return
        val radius = parts.getOrNull(2)?.toFloatOrNull() ?: HOME_RADIUS_M
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) return
        val lm = app.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val entering = intent?.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false) ?: false
                if (entering) signal("arrive_home")
            }
        }
        register(r, IntentFilter(HOME_ACTION), exported = false)
        homeReceiver = r
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getBroadcast(
            app,
            4405,
            Intent(HOME_ACTION).setPackage(app.packageName),
            flags,
        )
        homeIntent = pi
        runCatching { lm.addProximityAlert(lat, lng, radius, -1L, pi) }
    }

    @SuppressLint("MissingPermission")
    private fun stopHome() {
        val pi = homeIntent
        if (pi != null) {
            val lm = app.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            runCatching { lm?.removeProximityAlert(pi) }
        }
        homeIntent = null
        unregister(homeReceiver)
        homeReceiver = null
    }

    // ── calendar event end ──────────────────────────────────────────────

    private fun startCalendar() {
        if (calendarPoll != null) return
        lastCalendarCheck = System.currentTimeMillis()
        val poll = object : Runnable {
            override fun run() {
                checkCalendar()
                main.postDelayed(this, CALENDAR_POLL_MS)
            }
        }
        calendarPoll = poll
        main.postDelayed(poll, CALENDAR_POLL_MS)
    }

    private fun stopCalendar() {
        calendarPoll?.let { main.removeCallbacks(it) }
        calendarPoll = null
    }

    private fun checkCalendar() {
        val now = System.currentTimeMillis()
        val since = lastCalendarCheck
        lastCalendarCheck = now
        if (!granted(Manifest.permission.READ_CALENDAR)) return
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            android.content.ContentUris.appendId(it, since - 86_400_000L)
            android.content.ContentUris.appendId(it, now + 60_000L)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
        )
        runCatching {
            app.contentResolver.query(uri, projection, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val title = c.getString(0)
                    val end = c.getLong(1)
                    val allDay = c.getInt(2) == 1
                    if (!allDay && end in (since + 1)..now) {
                        signal("calendar_end", title)
                        break
                    }
                }
            }
        }
    }
}
