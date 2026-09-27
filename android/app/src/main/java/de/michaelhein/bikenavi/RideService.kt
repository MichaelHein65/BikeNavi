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
import java.util.concurrent.CopyOnWriteArrayList

/** Continues GPS recording while the screen is locked; notification remains visible. */
class RideService : Service(), LocationListener {
    inner class RideBinder : Binder() { fun service() = this@RideService }
    private val binder = RideBinder()
    private lateinit var locationManager: LocationManager
    val track = CopyOnWriteArrayList<Point>()
    val listeners = CopyOnWriteArrayList<(Point) -> Unit>()
    var last: Point? = null
        private set
    var recording = false
        private set

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val channel = NotificationChannel("rides", "Fahrtaufzeichnung", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
    override fun onBind(intent: Intent): IBinder = binder
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            recording = false
            locationManager.removeUpdates(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val pending = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, "rides").setContentTitle("BikeNavi")
            .setContentText("Fahrtaufzeichnung aktiv").setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pending).build()
        startForeground(12, notification)
        recording = true
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
        if (recording && (track.lastOrNull()?.distance(point) ?: 10.0) >= 3.0) track.add(point)
        listeners.forEach { it(point) }
    }
    override fun onDestroy() {
        locationManager.removeUpdates(this)
        super.onDestroy()
    }
}
