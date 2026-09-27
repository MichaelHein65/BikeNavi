package de.michaelhein.bikenavi

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.tts.TextToSpeech
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
import java.util.Locale
import java.util.UUID

class MainActivity : Activity(), SensorEventListener {
    private lateinit var map: MapView
    private lateinit var status: TextView
    private lateinit var data: LocalData
    private lateinit var graphRepository: GraphRepository
    private var start: Point? = null
    private var goal: Point? = null
    private val via = ArrayList<Point>()
    private var profile = RidingProfile()
    private var route: Route? = null
    private var navigationRoute: Route? = null
    private var graph: BikeGraph? = null
    private var tracker = RouteTracker()
    private val reroutePolicy = ReroutePolicy()
    private var lastSpoken: String? = null
    private var lastNotificationSlot = -1L
    private var speech: TextToSpeech? = null
    private var voice = true
    private lateinit var bike: BikeBluetooth
    private var service: RideService? = null
    private var selectedRide: SavedRide? = null
    private var busy = false
    private var following = true
    private var sensorHeading: Float? = null
    private lateinit var sensors: SensorManager
    private var bound = false
    private val onLocation: (Point) -> Unit = { point -> runOnUiThread { updatePosition(point) } }
    private val onFix: (Location) -> Unit = { fix -> runOnUiThread { updateNavigation(fix) } }
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            bound = true
            service = (binder as RideService.RideBinder).service().also {
                it.listeners.add(onLocation)
                it.locationListeners.add(onFix)
                it.last?.let { p -> updatePosition(p) }
            }
        }
        override fun onServiceDisconnected(name: ComponentName) { service = null; bound = false }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        data = LocalData(this)
        sensors = getSystemService(SENSOR_SERVICE) as SensorManager
        graphRepository = GraphRepository(this)
        val prefs = getSharedPreferences("riding", MODE_PRIVATE)
        profile = RidingProfile(prefs.getString("bike", "touring") ?: "touring",
            prefs.getBoolean("electric", true), prefs.getString("surface", "any") ?: "any",
            prefs.getBoolean("hills", false))
        voice = prefs.getBoolean("voice", true)
        speech = TextToSpeech(this) { if (it == TextToSpeech.SUCCESS) speech?.language = Locale.GERMAN }
        bike = BikeBluetooth(this) { runOnUiThread {
            if (service?.recording == true) {
                val m = bike.measurement
                val battery = m.battery?.let { "$it %" } ?: "–"
                status.contentDescription = "Bike ${bike.status}; Akku $battery"
            }
        } }
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
        val more = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun moreButton(label: String, action: () -> Unit) {
            more.addView(Button(this).apply { text = label; textSize = 11f; setOnClickListener { action() } },
                LinearLayout.LayoutParams(0, -2, 1f))
        }
        moreButton("Suche") { search() }
        moreButton("Orte") { showPlaces() }
        moreButton("Wegpunkte") { editWaypoints() }
        moreButton("Profil") { editProfile() }
        moreButton("Details") { showRouteDetails() }
        panel.addView(more)
        val extra = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun extraButton(label: String, action: () -> Unit) {
            extra.addView(Button(this).apply { text = label; textSize = 12f; setOnClickListener { action() } },
                LinearLayout.LayoutParams(0, -2, 1f))
        }
        extraButton("Bike") { showBike() }
        extraButton("Einstellungen") { showSettings() }
        extraButton("Karte folgen") { following = !following; show(if (following) "Kartennachführung aktiv" else "Karte frei") }
        extraButton("Plan speichern") { savePlan() }
        panel.addView(extra)
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
        val current = data.currentPlan()
        if (current != null && current.stops.size >= 2) {
            start = current.stops.first()
            goal = current.stops.last()
            via.addAll(current.stops.drop(1).dropLast(1))
            route = current.route
            profile = current.profile
        } else route = data.activeRoute()
        navigationRoute = route
        redraw()
        requestLocation()
        if (!bound) bound = bindService(Intent(this, RideService::class.java), connection, 0)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 44)
    }

    private fun select(p: Point) {
        if (start == null) {
            start = p
            status.text = "Start gesetzt. Ziel durch langes Drücken wählen."
            redraw()
        } else if (goal == null) {
            goal = p
            status.text = "Ziel gesetzt. Route antippen."
            redraw()
        } else {
            AlertDialog.Builder(this).setTitle("Kartenpunkt")
                .setItems(arrayOf("Als Start", "Als Ziel", "Zwischenziel", "Als Favorit")) { _, which ->
                    when (which) {
                        0 -> { start = p; via.clear() }
                        1 -> goal = p
                        2 -> via.add(p)
                        3 -> namePlace(p)
                    }
                    if (which < 3) { route = null; navigationRoute = null; redraw() }
                }.show()
        }
    }
    private fun redraw() {
        map.overlays.removeAll { it is Marker || it is Polyline }
        fun marker(p: Point, title: String) {
            map.overlays.add(Marker(map).apply { position = GeoPoint(p.lat, p.lon); this.title = title })
        }
        start?.let { marker(it, "Start") }
        via.forEachIndexed { i, p -> marker(p, "Zwischenziel ${i + 1}") }
        goal?.let { marker(it, "Ziel") }
        (navigationRoute ?: route)?.let { r ->
            if (r.surfaces.size == r.points.size - 1) {
                var from = 0
                while (from < r.surfaces.size) {
                    var to = from + 1
                    while (to < r.surfaces.size && r.surfaces[to] == r.surfaces[from]) to++
                    map.overlays.add(Polyline().apply {
                        setPoints(r.points.subList(from, to + 1).map { GeoPoint(it.lat, it.lon) })
                        outlinePaint.color = surfaceColor(r.surfaces[from])
                        outlinePaint.strokeWidth = 12f
                    })
                    from = to
                }
            } else map.overlays.add(Polyline().apply {
                setPoints(r.points.map { GeoPoint(it.lat, it.lon) })
                outlinePaint.color = Color.GRAY
                outlinePaint.strokeWidth = 12f
            })
        }
        map.invalidate()
    }
    private fun surfaceColor(s: String) = when (s) {
        "paved", "asphalt", "concrete", "concrete:plates", "concrete:lanes" -> Color.rgb(34, 100, 215)
        "paving_stones", "sett", "cobblestone" -> Color.rgb(127, 65, 170)
        "compacted", "fine_gravel", "gravel", "pebblestone" -> Color.rgb(177, 130, 30)
        "dirt", "earth", "ground", "sand", "grass", "unpaved" -> Color.rgb(143, 85, 46)
        "metal", "wood" -> Color.rgb(30, 160, 165)
        else -> Color.GRAY
    }

    private fun calculate() {
        val a = start ?: return show("Bitte Start wählen.")
        val b = goal ?: return show("Bitte Ziel wählen.")
        if (busy) return
        val stops = listOf(a) + via + b
        val south = stops.minOf { it.lat } - 0.01
        val west = stops.minOf { it.lon } - 0.01
        val north = stops.maxOf { it.lat } + 0.01
        val east = stops.maxOf { it.lon } + 0.01
        busy = true
        status.text = "Wegenetz prüfen und Route berechnen …"
        thread {
            try {
                val newGraph = graphRepository.graphFor(stops) { done, total ->
                    runOnUiThread { status.text = "Wegenetz: $done / $total Gebiete" }
                }
                val result = newGraph.routeThrough(stops, profile)
                data.saveRoute(result)
                data.saveCurrentPlan(SavedPlan("current", "Aktuelle Planung", stops, profile, result))
                runOnUiThread {
                    graph = newGraph
                    route = result
                    navigationRoute = result
                    tracker = RouteTracker()
                    redraw()
                    val startAccess = result.points.firstOrNull()?.distance(a) ?: 0.0
                    val endAccess = result.points.lastOrNull()?.distance(b) ?: 0.0
                    status.text = if (max(startAccess, endAccess) > 25)
                        "Route: %.1f km · Zugang bis %.0f m ungeprüft; vor Ort prüfen"
                            .format(result.meters / 1000, max(startAccess, endAccess))
                    else "Route: %.1f km · lokal gespeichert".format(result.meters / 1000)
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
        if (location != null && System.currentTimeMillis() - location.time < 15_000 &&
            (!location.hasAccuracy() || location.accuracy <= 75)) {
            val p = Point(location.latitude, location.longitude)
            map.controller.animateTo(GeoPoint(p.lat, p.lon))
            map.controller.setZoom(16.0)
            if (start == null) { start = p; redraw() }
        } else {
            show("Aktueller GPS-Standort wird ermittelt …")
            try {
                manager.requestSingleUpdate(LocationManager.GPS_PROVIDER, object : LocationListener {
                    override fun onLocationChanged(fix: Location) {
                        if (isFinishing || fix.hasAccuracy() && fix.accuracy > 75) return
                        val p = Point(fix.latitude, fix.longitude)
                        map.controller.animateTo(GeoPoint(p.lat, p.lon))
                        map.controller.setZoom(16.0)
                        if (start == null) { start = p; redraw() }
                        show("Standort gefunden.")
                    }
                }, mainLooper)
            } catch (_: Exception) { show("GPS nicht verfügbar. Start auf der Karte wählen.") }
        }
    }
    private fun updatePosition(p: Point) {
        if (following && service?.recording != true) map.controller.animateTo(GeoPoint(p.lat, p.lon))
    }
    private fun updateNavigation(fix: Location) {
        if (service?.recording != true || service?.paused == true) return
        val current = navigationRoute ?: return
        val p = Point(fix.latitude, fix.longitude)
        val heading = if (fix.hasSpeed() && fix.speed >= 1f && fix.hasBearing()) fix.bearing
            else sensorHeading ?: fix.bearing.takeIf { fix.hasBearing() }
        val progress = tracker.update(current, p, fix.accuracy, heading, fix.time) ?: return
        if (following && heading != null) {
            map.setMapOrientation(-heading)
            val angle = Math.toRadians(heading.toDouble())
            val ahead = 180.0
            val center = Point(p.lat + cos(angle) * ahead / 111320.0,
                p.lon + sin(angle) * ahead / (111320.0 * cos(Math.toRadians(p.lat))))
            map.controller.animateTo(GeoPoint(center.lat, center.lon))
            if (map.height > 0) {
                val zoom = kotlin.math.log2(156543.0 * cos(Math.toRadians(p.lat)) *
                    map.height * 0.8 / 500).coerceIn(14.0, 19.0)
                map.controller.setZoom(zoom)
            }
        }
        val turn = progress.next?.let { "${it.instruction} in ${progress.toTurn.toInt()} m" }
        status.text = if (progress.offRoute > 35) "Abweichung ${progress.offRoute.toInt()} m · Anschluss wird geprüft"
            else "${turn ?: "Der Route folgen"} · noch %.1f km".format(progress.remaining / 1000)
        if (voice && turn != null && progress.toTurn < 100 && lastSpoken != progress.next.toString()) {
            speech?.speak(turn, TextToSpeech.QUEUE_FLUSH, null, "turn")
            lastSpoken = progress.next.toString()
        }
        if (fix.time / 10000 != lastNotificationSlot) {
            lastNotificationSlot = fix.time / 10000
            startService(Intent(this, RideService::class.java).setAction("NAV")
                .putExtra("message", "${turn ?: "Der Route folgen"} · %.1f km".format(progress.remaining / 1000)))
        }
        if (reroutePolicy.shouldReroute(progress, fix.accuracy, fix.time) && !busy) reconnect(p, progress)
    }
    private fun toggleRide() {
        val active = service
        if (active?.recording == true) {
            if (active.paused) {
                startService(Intent(this, RideService::class.java).setAction("RESUME"))
                show("Fahrt fortgesetzt.")
            } else AlertDialog.Builder(this).setTitle("Fahrt")
                .setItems(arrayOf("Pausieren", "Beenden und speichern", "Verwerfen", "Weiterfahren")) { _, which ->
                    when (which) {
                        0 -> { startService(Intent(this, RideService::class.java).setAction("PAUSE")); show("Fahrt pausiert.") }
                        1, 2 -> {
                            val samples = active.track.toList()
                            if (which == 1 && samples.size >= 2) {
                                val ride = data.saveRide(samples, active.bikeSamples.toList())
                                show("${ride.title} gespeichert · %.1f km".format(ride.meters / 1000))
                            } else show(if (which == 2) "Fahrt verworfen." else "Zu wenige GPS-Punkte.")
                            active.complete()
                            startService(Intent(this, RideService::class.java).setAction("STOP"))
                            navigationRoute = route
                            tracker = RouteTracker()
                        }
                    }
                }.show()
        } else {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                requestLocation()
                return
            }
            bike.stop()
            startForegroundService(Intent(this, RideService::class.java))
            if (!bound) {
                bound = bindService(Intent(this, RideService::class.java), connection, BIND_AUTO_CREATE)
            }
            show("Fahrtaufzeichnung gestartet.")
        }
    }

    private fun editWaypoints() {
        val entries = listOfNotNull(start?.let { "Start · ${format(it)}" }) +
            via.mapIndexed { i, p -> "Zwischenziel ${i + 1} · ${format(p)}" } +
            listOfNotNull(goal?.let { "Ziel · ${format(it)}" })
        AlertDialog.Builder(this).setTitle("Deine Wegpunkte")
            .setItems((entries + listOf("Tour umkehren", "Planung zurücksetzen")).toTypedArray()) { _, index ->
                when (index) {
                    entries.size -> {
                        val old = start; start = goal; goal = old
                        via.reverse()
                        route = null; navigationRoute = null; redraw()
                        if (start != null && goal != null) calculate()
                    }
                    entries.size + 1 -> {
                        start = null; goal = null; via.clear(); route = null; navigationRoute = null
                        data.clearCurrentPlan(); redraw()
                    }
                    else -> if (index in 1..via.size) AlertDialog.Builder(this)
                        .setMessage("Zwischenziel entfernen?")
                        .setPositiveButton("Entfernen") { _, _ -> via.removeAt(index - 1); route = null; redraw() }
                        .setNegativeButton("Abbrechen", null).show()
                }
            }.setNegativeButton("Schließen", null).show()
    }
    private fun format(p: Point) = "%.5f, %.5f".format(Locale.ROOT, p.lat, p.lon)

    private fun editProfile() {
        val bikes = arrayOf("Tourenrad", "Gravel", "Mountainbike", "Rennrad")
        val codes = arrayOf("touring", "gravel", "mountain", "road")
        AlertDialog.Builder(this).setTitle("Fahrprofil")
            .setSingleChoiceItems(bikes, codes.indexOf(profile.bike)) { dialog, index ->
                profile = profile.copy(bike = codes[index]); saveProfile(); dialog.dismiss(); editSurface()
            }.setNeutralButton("Belag / Hügel") { _, _ -> editSurface() }
            .setNegativeButton("Schließen", null).show()
    }
    private fun editSurface() {
        val labels = arrayOf("Alle Wege", "Befestigte bevorzugen", "Nur bekannte befestigte Wege")
        val values = arrayOf("any", "preferPaved", "pavedOnly")
        AlertDialog.Builder(this).setTitle("Wegbeschaffenheit")
            .setSingleChoiceItems(labels, values.indexOf(profile.surface)) { dialog, which ->
                profile = profile.copy(surface = values[which]); saveProfile(); dialog.dismiss(); editOptions()
            }.setNeutralButton("Weitere Optionen") { _, _ -> editOptions() }.show()
    }
    private fun editOptions() {
        val choices = booleanArrayOf(profile.electric, profile.gentleHills, voice)
        AlertDialog.Builder(this).setTitle("Weitere Optionen")
            .setMultiChoiceItems(arrayOf("E-Bike", "Sanfte Hügel", "Sprachanweisungen"), choices) { _, i, checked ->
                choices[i] = checked
            }.setPositiveButton("Speichern") { _, _ ->
                profile = profile.copy(electric = choices[0], gentleHills = choices[1])
                voice = choices[2]
                saveProfile()
            }.show()
    }
    private fun saveProfile() {
        getSharedPreferences("riding", MODE_PRIVATE).edit()
            .putString("bike", profile.bike).putString("surface", profile.surface)
            .putBoolean("electric", profile.electric).putBoolean("hills", profile.gentleHills)
            .putBoolean("voice", voice).apply()
        if (route != null && start != null && goal != null) show("Profil geändert. Route neu berechnen.")
    }

    private fun namePlace(point: Point) {
        val input = EditText(this).apply { hint = "Name, z. B. Zuhause" }
        AlertDialog.Builder(this).setTitle("Ort speichern").setView(input)
            .setPositiveButton("Speichern") { _, _ ->
                val name = input.text.toString().trim().take(100)
                if (name.isNotEmpty()) {
                    data.savePlace(Place(UUID.randomUUID().toString(), name, point))
                    show("Ort „$name“ gespeichert.")
                    redraw()
                }
            }.setNegativeButton("Abbrechen", null).show()
    }
    private fun showPlaces() {
        val places = data.places()
        if (places.isEmpty()) return show("Noch keine Orte gespeichert. Kartenpunkt lange drücken.")
        AlertDialog.Builder(this).setTitle("Meine Orte")
            .setItems(places.map { it.name }.toTypedArray()) { _, index ->
                val place = places[index]
                AlertDialog.Builder(this).setTitle(place.name)
                    .setItems(arrayOf("Zur Tour hinzufügen", "Auf Karte zeigen", "Umbenennen", "Löschen")) { _, action ->
                        when (action) {
                            0 -> { if (goal == null) goal = place.coordinate else via.add(place.coordinate); redraw() }
                            1 -> map.controller.animateTo(GeoPoint(place.coordinate.lat, place.coordinate.lon))
                            2 -> {
                                val input = EditText(this).apply { setText(place.name) }
                                AlertDialog.Builder(this).setTitle("Ort umbenennen").setView(input)
                                    .setPositiveButton("Speichern") { _, _ ->
                                        data.savePlace(place.copy(name = input.text.toString().trim().take(100)))
                                    }.setNegativeButton("Abbrechen", null).show()
                            }
                            3 -> AlertDialog.Builder(this).setMessage("„${place.name}“ löschen?")
                                .setPositiveButton("Löschen") { _, _ -> data.deletePlace(place.id) }
                                .setNegativeButton("Abbrechen", null).show()
                        }
                    }.show()
            }.show()
    }
    private fun search() {
        val input = EditText(this).apply { hint = "Ort oder Adresse"; setSingleLine(true) }
        AlertDialog.Builder(this).setTitle("Ortssuche").setView(input)
            .setPositiveButton("Suchen") { _, _ ->
                val query = input.text.toString().trim()
                if (query.length < 2) return@setPositiveButton show("Mindestens zwei Zeichen eingeben.")
                show("Orte werden gesucht …")
                thread {
                    try {
                        val endpoint = getSharedPreferences("riding", MODE_PRIVATE)
                            .getString("photon", "https://photon.komoot.io") ?: "https://photon.komoot.io"
                        val results = PlaceSearch.search(query, service?.last, endpoint)
                        runOnUiThread {
                            if (results.isEmpty()) show("Kein Ort gefunden.")
                            else AlertDialog.Builder(this).setTitle("Suchergebnisse")
                                .setItems(results.map { it.name }.toTypedArray()) { _, index ->
                                    val place = results[index]
                                    AlertDialog.Builder(this).setTitle(place.name)
                                        .setItems(arrayOf("Als Ziel", "Als Zwischenziel", "Als Start", "Als Favorit")) { _, action ->
                                            when (action) {
                                                0 -> goal = place.coordinate
                                                1 -> via.add(place.coordinate)
                                                2 -> start = place.coordinate
                                                3 -> namePlace(place.coordinate)
                                            }
                                            if (action < 3) { route = null; navigationRoute = null; redraw() }
                                            map.controller.animateTo(GeoPoint(place.coordinate.lat, place.coordinate.lon))
                                        }.show()
                                }.show()
                        }
                    } catch (e: Exception) { runOnUiThread { show("Suche fehlgeschlagen: ${e.message}") } }
                }
            }.setNegativeButton("Abbrechen", null).show()
    }

    private fun showRouteDetails() {
        val r = route ?: return show("Noch keine Route berechnet.")
        val surfaces = HashMap<String, Double>()
        r.points.zipWithNext().forEachIndexed { i, (a, b) ->
            val name = r.surfaces.getOrNull(i) ?: "unbekannt"
            surfaces[name] = (surfaces[name] ?: 0.0) + a.distance(b)
        }
        val details = surfaces.entries.sortedByDescending { it.value }
            .joinToString("\n") { "${it.key}: %.1f km".format(it.value / 1000) }
        AlertDialog.Builder(this).setTitle("Routendetails")
            .setMessage("Länge: %.1f km\nAbbieger: ${r.maneuvers.size}\nZwischenziele: ${via.size}\n\nBeläge:\n$details"
                .format(r.meters / 1000))
            .setPositiveButton("Schließen", null).show()
    }

    private fun showBike() {
        if (Build.VERSION.SDK_INT >= 31 && (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)) {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT), 43)
            show("Bluetooth-Berechtigung erteilen und Bike nochmals öffnen.")
            return
        }
        val current = service?.bike ?: bike
        val m = current.measurement
        val snapshot = "${current.status}\nAkku: ${m.battery?.toString() ?: "–"} % · Modus: ${m.assistMode ?: "–"}\n" +
            "Fahrer: ${m.riderWatts ?: "–"} W · Motor: ${m.motorWatts ?: "–"} W\n" +
            "Kadenz: ${m.cadence ?: "–"} U/min · Tempo: ${m.speedKph ?: "–"} km/h"
        AlertDialog.Builder(this).setTitle("Bosch Bike · Bluetooth").setMessage(snapshot)
            .setPositiveButton("Suchen") { _, _ ->
                current.search()
                android.os.Handler(mainLooper).postDelayed({ showBikeCandidates() }, 4500)
            }
            .setNeutralButton("Trennen") { _, _ -> current.stop() }
            .setNegativeButton("Schließen", null).show()
    }
    private fun showBikeCandidates() {
        val current = service?.bike ?: bike
        val entries = current.candidates.entries.toList()
        if (entries.isEmpty()) return show("Noch kein Bosch Bike gefunden. Flow verbinden und erneut suchen.")
        AlertDialog.Builder(this).setTitle("Bike auswählen")
            .setItems(entries.map { it.value }.toTypedArray()) { _, index ->
                current.connect(entries[index].key)
                show("Verbinde ${entries[index].value} …")
            }.setNegativeButton("Schließen", null).show()
    }
    private fun showSettings() {
        val prefs = getSharedPreferences("riding", MODE_PRIVATE)
        AlertDialog.Builder(this).setTitle("Einstellungen · ohne Pi")
            .setItems(arrayOf("Ortssuche: Photon-Dienst", "Sprache ${if (voice) "ein" else "aus"}",
                "Kartencache", "Über BikeNavi")) { _, which ->
                when (which) {
                    0 -> {
                        val input = EditText(this).apply {
                            setText(prefs.getString("photon", "https://photon.komoot.io"))
                        }
                        AlertDialog.Builder(this).setTitle("Photon-HTTPS-Server").setView(input)
                            .setPositiveButton("Speichern") { _, _ ->
                                val endpoint = input.text.toString().trim().trimEnd('/')
                                if (endpoint.startsWith("https://"))
                                    prefs.edit().putString("photon", endpoint).apply()
                                else show("Nur HTTPS-Adressen erlaubt.")
                            }.setNegativeButton("Abbrechen", null).show()
                    }
                    1 -> { voice = !voice; saveProfile() }
                    2 -> show("Kartenkacheln und OSM-Gebiete bleiben im App-Speicher; neue Gebiete benötigen Internet.")
                    3 -> AlertDialog.Builder(this).setTitle("BikeNavi Android")
                        .setMessage("Lokale Planung und Touren. Kein Pi, kein Konto, keine Synchronisation. " +
                            "OSM-Daten © OpenStreetMap contributors; Ortssuche von Photon.")
                        .setPositiveButton("Schließen", null).show()
                }
            }.show()
    }

    private fun reconnect(position: Point, progress: RouteProgress) {
        val original = route ?: return
        val network = graph ?: return // A stored route can be followed without rebuilding the graph.
        busy = true
        thread {
            try {
                val cumulative = mutableListOf(0.0)
                original.points.zipWithNext().forEach { (a, b) -> cumulative.add(cumulative.last() + a.distance(b)) }
                val nextMandatory = original.waypointIndices.firstOrNull {
                    it in cumulative.indices && cumulative[it] >= progress.traveled - 3
                } ?: original.points.lastIndex
                val candidates = (1..nextMandatory).filter {
                    cumulative[it] > progress.traveled + 3 &&
                        original.points[it].distance(position) < 1500
                }.filterIndexed { i, _ -> i % 10 == 0 }.take(12).toMutableList()
                if (original.points[nextMandatory].distance(position) < 3000 &&
                    nextMandatory !in candidates) candidates.add(nextMandatory)
                val deadline = System.nanoTime() + 2_000_000_000L
                val best = candidates.mapNotNull { index ->
                    if (System.nanoTime() > deadline) return@mapNotNull null
                    try {
                        val connector = network.route(position, original.points[index], profile)
                        if (connector.points.last().distance(original.points[index]) > 20) null
                        else Triple(index, connector, connector.meters + original.meters - cumulative[index])
                    } catch (_: Exception) { null }
                }.minByOrNull { it.third } ?: throw RoutingException("Kein sicherer Anschluss gefunden.")
                val combined = best.second
                val join = best.first
                val offset = combined.points.lastIndex
                val merged = Route(
                    combined.points + original.points.drop(join + 1),
                    combined.meters + original.meters - cumulative[join],
                    combined.surfaces + original.surfaces.drop(join),
                    combined.maneuvers.filter { it.index < offset } +
                        Maneuver(offset, "Der Tour folgen") +
                        original.maneuvers.filter { it.index > join }.map { it.copy(index = offset + it.index - join) },
                    original.waypointIndices.filter { it >= join }.map { offset + it - join })
                runOnUiThread {
                    navigationRoute = merged
                    tracker = RouteTracker()
                    lastSpoken = null
                    redraw()
                    show("Lokaler Anschluss an die Tour gefunden.")
                }
            } catch (e: Exception) { runOnUiThread { show(e.message ?: "Rückführung fehlgeschlagen.") } }
            finally { busy = false }
        }
    }
    private fun showRides() {
        val rides = data.rides().reversed()
        val plans = data.plans().reversed()
        if (rides.isEmpty() && plans.isEmpty()) return show("Noch keine Touren oder Pläne gespeichert.")
        val labels = plans.map { "Plan · ${it.title} · %.1f km".format(it.route.meters / 1000) } +
            rides.map { "Fahrt · ${it.title} · %.1f km".format(it.meters / 1000) }
        AlertDialog.Builder(this).setTitle("Deine Touren")
            .setItems(labels.toTypedArray()) { _, index ->
                if (index < plans.size) showPlan(plans[index]) else showRideDetail(rides[index - plans.size])
            }.setNegativeButton("Schließen", null).show()
    }
    private fun savePlan() {
        val current = route ?: return show("Zuerst Route berechnen.")
        val stops = listOfNotNull(start) + via + listOfNotNull(goal)
        if (stops.size < 2) return show("Start und Ziel fehlen.")
        val input = EditText(this).apply {
            setText("${data.places().find { it.coordinate.distance(stops.first()) < 100 }?.name ?: "Start"} → " +
                (data.places().find { it.coordinate.distance(stops.last()) < 100 }?.name ?: "Ziel"))
        }
        AlertDialog.Builder(this).setTitle("Plan speichern").setView(input)
            .setPositiveButton("Speichern") { _, _ ->
                val name = input.text.toString().trim().take(200)
                if (name.isNotEmpty()) {
                    data.savePlan(SavedPlan(UUID.randomUUID().toString(), name, stops, profile, current))
                    show("Plan „$name“ gespeichert.")
                }
            }.setNegativeButton("Abbrechen", null).show()
    }
    private fun showPlan(plan: SavedPlan) {
        AlertDialog.Builder(this).setTitle(plan.title)
            .setItems(arrayOf("Plan laden", "Löschen")) { _, which ->
                if (which == 0) {
                    start = plan.stops.first()
                    goal = plan.stops.last()
                    via.clear(); via.addAll(plan.stops.drop(1).dropLast(1))
                    route = plan.route; navigationRoute = route; profile = plan.profile
                    data.saveCurrentPlan(plan)
                    tracker = RouteTracker(); redraw()
                    val p = start!!
                    map.controller.animateTo(GeoPoint(p.lat, p.lon))
                    show("Plan geladen · ohne Pi.")
                } else AlertDialog.Builder(this).setMessage("Plan löschen?")
                    .setPositiveButton("Löschen") { _, _ -> data.deletePlan(plan.id) }
                    .setNegativeButton("Abbrechen", null).show()
            }.show()
    }
    private fun showRideDetail(ride: SavedRide) {
        val duration = if (ride.samples.size > 1)
            (ride.samples.last().time - ride.samples.first().time) / 60000 else 0
        val heights = ride.samples.mapNotNull { it.altitude }
        val ascent = heights.zipWithNext().sumOf { (a, b) -> max(0.0, b - a) }
        AlertDialog.Builder(this).setTitle(ride.title)
            .setMessage("Strecke: %.1f km\nDauer: %d min\nAnstieg: %.0f m\nBike-Messungen: %d"
                .format(ride.meters / 1000, duration, ascent, ride.bikeSamples.size))
            .setPositiveButton("GPX") { _, _ ->
                selectedRide = ride
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/gpx+xml"
                    putExtra(Intent.EXTRA_TITLE, "BikeNavi-${ride.id}.gpx")
                }
                startActivityForResult(intent, 7)
            }.setNeutralButton("Auf Karte") { _, _ ->
                navigationRoute = Route(ride.points, ride.meters, emptyList())
                redraw()
                ride.points.firstOrNull()?.let { map.controller.animateTo(GeoPoint(it.lat, it.lon)) }
            }.setNegativeButton("Mehr") { _, _ ->
                AlertDialog.Builder(this).setTitle(ride.title)
                    .setItems(arrayOf("Diagramme", "Fahrt löschen")) { _, which ->
                        if (which == 0) showRideCharts(ride)
                        else AlertDialog.Builder(this).setMessage("Fahrt endgültig löschen?")
                            .setPositiveButton("Löschen") { _, _ -> data.deleteRide(ride.id) }
                            .setNegativeButton("Abbrechen", null).show()
                    }.show()
            }.show()
    }
    private fun showRideCharts(ride: SavedRide) {
        val scroll = HorizontalScrollView(this)
        scroll.addView(RideCharts(this, ride))
        AlertDialog.Builder(this).setTitle("Höhe und Leistung")
            .setView(scroll).setPositiveButton("Schließen", null).show()
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
    override fun onResume() {
        super.onResume()
        map.onResume()
        sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let {
            sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }
    override fun onPause() {
        sensors.unregisterListener(this)
        map.onPause()
        super.onPause()
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
        val rotation = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        val magnetic = (Math.toDegrees(SensorManager.getOrientation(rotation, FloatArray(3))[0].toDouble())
            .toFloat() + 360f) % 360f
        val p = service?.last
        val declination = p?.let { GeomagneticField(it.lat.toFloat(), it.lon.toFloat(), 0f,
            System.currentTimeMillis()).declination } ?: 0f
        sensorHeading = (magnetic + declination + 360f) % 360f
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }
    override fun onDestroy() {
        service?.listeners?.remove(onLocation)
        service?.locationListeners?.remove(onFix)
        if (bound) unbindService(connection)
        bike.stop()
        speech?.shutdown()
        map.onDetach()
        super.onDestroy()
    }
}
