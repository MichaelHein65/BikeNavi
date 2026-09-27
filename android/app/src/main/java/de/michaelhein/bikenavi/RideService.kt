package de.michaelhein.bikenavi

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Binder
import android.os.IBinder
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/** Continues GPS recording while the screen is locked; notification remains visible. */
class RideService : Service(), LocationListener {
    inner class RideBinder : Binder() { fun service() = this@RideService }
    private val binder = RideBinder()
    private lateinit var locationManager: LocationManager
    val track = CopyOnWriteArrayList<RidePoint>()
    val listeners = CopyOnWriteArrayList<(Point) -> Unit>()
    val locationListeners = CopyOnWriteArrayList<(Location) -> Unit>()
    var last: Point? = null
        private set
    var recording = false
        private set
    var paused = false
        private set
    private var segment = 0
    private val partialFile by lazy { File(filesDir, "unfinished-ride.json") }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        if (partialFile.exists()) {
            try {
                val saved = JSONObject(partialFile.readText())
                val array = saved.getJSONArray("samples")
                for (i in 0 until array.length()) {
                    val p = array.getJSONObject(i)
                    track.add(RidePoint(Point(p.getDouble("lat"), p.getDouble("lon")),
                        p.getLong("time"), if (p.isNull("altitude")) null else p.getDouble("altitude"),
                        if (p.isNull("speed")) null else p.getDouble("speed").toFloat(), p.getInt("segment")))
                }
                segment = (track.maxOfOrNull { it.segment } ?: 0) + 1
                paused = true // Explicitly resume after a process restart.
            } catch (_: Exception) { track.clear() }
        }
        val channel = NotificationChannel("rides", "Fahrtaufzeichnung", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
    override fun onBind(intent: Intent): IBinder = binder
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            recording = false
            paused = false
            locationManager.removeUpdates(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == "PAUSE") {
            paused = true
            persist()
            return START_STICKY
        }
        if (intent?.action == "RESUME") {
            segment++
            paused = false
            recording = true
            return START_STICKY
        }
        if (recording) return START_STICKY
        val pending = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, "rides").setContentTitle("BikeNavi")
            .setContentText("Fahrtaufzeichnung aktiv").setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pending).build()
        startForeground(12, notification)
        recording = true
        paused = false
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 3f, this)
        }
        return START_STICKY
    }
    override fun onLocationChanged(location: Location) {
        if (location.hasAccuracy() && location.accuracy > 75f) return
        val point = Point(location.latitude, location.longitude)
        last = point
        if (recording && !paused && (track.lastOrNull()?.point?.distance(point) ?: 10.0) >= 3.0) {
            track.add(RidePoint(point, location.time,
                location.altitude.takeIf { location.hasAltitude() },
                location.speed.takeIf { location.hasSpeed() }, segment))
            if (track.size % 5 == 0) persist()
        }
        listeners.forEach { it(point) }
        locationListeners.forEach { it(location) }
    }
    fun discard() { track.clear(); partialFile.delete() }
    fun complete() { persist(); partialFile.delete(); track.clear() }
    private fun persist() {
        val samples = JSONArray().also { a -> track.forEach {
            a.put(JSONObject().put("lat", it.point.lat).put("lon", it.point.lon)
                .put("time", it.time).put("altitude", it.altitude)
                .put("speed", it.speed).put("segment", it.segment))
        } }
        val temp = File(filesDir, "unfinished-ride.tmp")
        temp.writeText(JSONObject().put("samples", samples).toString())
        if (!temp.renameTo(partialFile)) temp.delete()
    }
    override fun onDestroy() {
        locationManager.removeUpdates(this)
        if (track.isNotEmpty()) persist()
        super.onDestroy()
    }
}
