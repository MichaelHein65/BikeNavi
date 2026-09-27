package de.michaelhein.bikenavi

import android.Manifest
import android.app.Activity
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.LocationManager
import android.os.Bundle
import android.os.IBinder
import android.view.Gravity
import android.view.View
import android.widget.*
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import kotlin.concurrent.thread
import kotlin.math.*

class MainActivity : Activity() {
    private lateinit var map: MapView
    private lateinit var status: TextView
    private lateinit var data: LocalData
    private var start: Point? = null
    private var goal: Point? = null
    private var route: Route? = null
    private var service: RideService? = null
    private var selectedRide: SavedRide? = null
    private var busy = false
    private var following = true
    private var bound = false
    private val onLocation: (Point) -> Unit = { point -> runOnUiThread { updatePosition(point) } }
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            bound = true
            service = (binder as RideService.RideBinder).service().also {
                it.listeners.add(onLocation)
                it.last?.let { p -> updatePosition(p) }
            }
        }
        override fun onServiceDisconnected(name: ComponentName) { service = null; bound = false }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        data = LocalData(this)
        Configuration.getInstance().userAgentValue = "BikeNaviAndroid/0.1 (https://github.com/MichaelHein65/BikeNavi)"
        Configuration.getInstance().load(this, getSharedPreferences("osmdroid", MODE_PRIVATE))
        map = MapView(this).apply {
            setMultiTouchControls(true)
            controller.setZoom(14.0)
            controller.setCenter(GeoPoint(49.0, 8.8))
        }
        status = TextView(this).apply {
            textSize = 15f
            setPadding(18, 14, 18, 14)
            setBackgroundColor(Color.WHITE)
            text = "Karte lange drücken: Start, danach Ziel. Online-Karten benötigen Internet."
        }
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
        val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun button(label: String, action: () -> Unit) {
            buttons.addView(Button(this).apply { text = label; setOnClickListener { action() } },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
        button("Standort") { locate() }
        button("Route") { calculate() }
        button("Fahrt") { toggleRide() }
        button("Touren") { showRides() }
        panel.addView(status)
        panel.addView(buttons)
        val frame = FrameLayout(this)
        frame.addView(map)
        val attribution = TextView(this).apply {
            text = "© OpenStreetMap contributors"
            textSize = 11f
            setPadding(6, 3, 6, 3)
            setBackgroundColor(Color.WHITE)
        }
        frame.addView(attribution, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.RIGHT))
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(frame, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(panel)
        setContentView(root)
        map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint?) = false
            override fun longPressHelper(p: GeoPoint?): Boolean {
                if (p != null) select(Point(p.latitude, p.longitude))
                return true
            }
        }))
        route = data.activeRoute()
        redraw()
        requestLocation()
    }

    private fun select(p: Point) {
        if (start == null || goal != null) {
            start = p
            goal = null
            route = null
            status.text = "Start gesetzt. Ziel durch langes Drücken wählen."
        } else {
            goal = p
            status.text = "Ziel gesetzt. Route antippen."
        }
        redraw()
    }
    private fun redraw() {
        map.overlays.removeAll { it is Marker || it is Polyline }
        fun marker(p: Point, title: String) {
            map.overlays.add(Marker(map).apply { position = GeoPoint(p.lat, p.lon); this.title = title })
        }
        start?.let { marker(it, "Start") }
        goal?.let { marker(it, "Ziel") }
        route?.let { r ->
            map.overlays.add(Polyline().apply {
                setPoints(r.points.map { GeoPoint(it.lat, it.lon) })
                outlinePaint.color = Color.rgb(30, 93, 207)
                outlinePaint.strokeWidth = 12f
            })
        }
        map.invalidate()
    }

    private fun calculate() {
        val a = start ?: return show("Bitte Start wählen.")
        val b = goal ?: return show("Bitte Ziel wählen.")
        if (busy) return
        val south = min(a.lat, b.lat) - 0.01
        val west = min(a.lon, b.lon) - 0.01
        val north = max(a.lat, b.lat) + 0.01
        val east = max(a.lon, b.lon) + 0.01
        if (north - south > 0.15 || east - west > 0.15) return show(
            "Etappe zu lang für einen Download. Bitte kürzere Teilstrecke wählen.")
        busy = true
        status.text = "Wegenetz prüfen und Route berechnen …"
        thread {
            try {
                var json = data.region(a, b)
                if (json == null) {
                    json = Overpass.download(south, west, north, east)
                    // Compile before caching: malformed responses must not replace working data.
                    BikeGraph.compile(json)
                    data.saveRegion(Region(south, west, north, east), json)
                }
                val result = BikeGraph.compile(json).route(a, b)
                data.saveRoute(result)
                runOnUiThread {
                    route = result
                    redraw()
                    status.text = "Route: %.1f km · lokal gespeichert".format(result.meters / 1000)
                    map.zoomToBoundingBox(org.osmdroid.util.BoundingBox(north, east, south, west), true)
                }
            } catch (e: Exception) {
                runOnUiThread { show(e.message ?: "Routenplanung fehlgeschlagen.") }
            } finally { busy = false }
        }
    }

    private fun requestLocation() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION), 42)
        } else locate()
    }
    private fun locate() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestLocation()
            return
        }
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        val location = manager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            ?: manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        if (location != null) {
            val p = Point(location.latitude, location.longitude)
            map.controller.animateTo(GeoPoint(p.lat, p.lon))
            map.controller.setZoom(16.0)
            if (start == null) { start = p; redraw() }
        } else show("Noch kein Standort verfügbar. GPS einschalten oder Start auf der Karte setzen.")
    }
    private fun updatePosition(p: Point) {
        if (following) map.controller.animateTo(GeoPoint(p.lat, p.lon))
        route?.let { r ->
            val closest = r.points.indices.minByOrNull { r.points[it].distance(p) } ?: return
            val remaining = r.points.drop(closest).zipWithNext().sumOf { (a, b) -> a.distance(b) }
            val off = r.points[closest].distance(p)
            status.text = if (off > 50) "Abseits der Route (${off.toInt()} m) · Anschluss bitte neu planen"
                else "Fahrt · noch %.1f km · GPS aktiv".format(remaining / 1000)
        }
    }
    private fun toggleRide() {
        val active = service
        if (active?.recording == true) {
            val points = active.track.toList()
            stopService(Intent(this, RideService::class.java).setAction("STOP"))
            if (points.size >= 2) {
                val ride = data.saveRide(points)
                show("${ride.title} gespeichert · %.1f km".format(ride.meters / 1000))
            } else show("Keine Fahrt gespeichert: zu wenige GPS-Punkte.")
            active.track.clear()
        } else {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                requestLocation()
                return
            }
            startForegroundService(Intent(this, RideService::class.java))
            if (!bound) {
                bound = bindService(Intent(this, RideService::class.java), connection, BIND_AUTO_CREATE)
            }
            show("Fahrtaufzeichnung gestartet.")
        }
    }
    private fun showRides() {
        val rides = data.rides().reversed()
        if (rides.isEmpty()) return show("Noch keine Touren gespeichert.")
        AlertDialog.Builder(this).setTitle("Touren · GPX exportieren")
            .setItems(rides.map { "${it.title} · %.1f km".format(it.meters / 1000) }.toTypedArray()) { _, index ->
                selectedRide = rides[index]
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/gpx+xml"
                    putExtra(Intent.EXTRA_TITLE, "BikeNavi-${rides[index].id}.gpx")
                }
                startActivityForResult(intent, 7)
            }.setNegativeButton("Schließen", null).show()
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, result: Intent?) {
        super.onActivityResult(requestCode, resultCode, result)
        if (requestCode == 7 && resultCode == RESULT_OK) {
            val uri = result?.data ?: return
            val ride = selectedRide ?: return
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(data.gpx(ride).toByteArray(Charsets.UTF_8)) }
                    ?: throw java.io.IOException("Datei nicht geöffnet.")
                show("GPX exportiert.")
            } catch (e: Exception) { show("Export fehlgeschlagen: ${e.message}") }
        }
    }
    private fun show(message: String) { status.text = message }
    override fun onResume() { super.onResume(); map.onResume() }
    override fun onPause() { map.onPause(); super.onPause() }
    override fun onDestroy() {
        service?.listeners?.remove(onLocation)
        if (bound) unbindService(connection)
        map.onDetach()
        super.onDestroy()
    }
}
