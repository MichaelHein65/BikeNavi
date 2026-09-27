package de.michaelhein.bikenavi

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class Region(val south: Double, val west: Double, val north: Double, val east: Double) {
    fun contains(point: Point) = point.lat in south..north && point.lon in west..east
    fun json() = JSONObject().put("south", south).put("west", west).put("north", north).put("east", east)
}

data class RidePoint(val point: Point, val time: Long, val altitude: Double?, val speed: Float?, val segment: Int)
data class BikeSample(val time: Long, val segment: Int, val value: BikeMeasurement)
data class SavedRide(
    val id: String, val title: String, val time: Long, val points: List<Point>, val meters: Double,
    val samples: List<RidePoint> = emptyList(), val bikeSamples: List<BikeSample> = emptyList()
)
data class SavedPlan(val id: String, val title: String, val stops: List<Point>,
                     val profile: RidingProfile, val route: Route)

/** Internal app storage only. Atomic replacement prevents a failed download from damaging a cached region. */
class LocalData(private val context: Context) {
    private val regionFile = File(context.filesDir, "osm-region.json")
    private val ridesFile = File(context.filesDir, "rides.json")
    private val routeFile = File(context.filesDir, "active-route.json")
    private val placesFile = File(context.filesDir, "places.json")
    private val plansFile = File(context.filesDir, "plans.json")

    fun region(start: Point, end: Point): JSONObject? {
        if (!regionFile.exists()) return null
        val container = JSONObject(regionFile.readText())
        val b = container.getJSONObject("bounds")
        val bounds = Region(b.getDouble("south"), b.getDouble("west"), b.getDouble("north"), b.getDouble("east"))
        return if (bounds.contains(start) && bounds.contains(end)) container.getJSONObject("osm") else null
    }

    fun saveRegion(bounds: Region, value: JSONObject) {
        atomic(regionFile, JSONObject().put("bounds", bounds.json()).put("osm", value).toString())
    }

    fun activeRoute(): Route? {
        if (!routeFile.exists()) return null
        return try {
            val json = JSONObject(routeFile.readText())
            Route(points(json.getJSONArray("points")), json.getDouble("meters"),
                json.optJSONArray("surfaces")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
                json.optJSONArray("maneuvers")?.let { a -> (0 until a.length()).map {
                    val m = a.getJSONObject(it); Maneuver(m.getInt("index"), m.getString("instruction"))
                } } ?: emptyList(),
                json.optJSONArray("waypointIndices")?.let { a -> (0 until a.length()).map { a.getInt(it) } } ?: emptyList())
        } catch (_: Exception) { null }
    }

    fun saveRoute(route: Route) {
        atomic(routeFile, routeJson(route).toString())
    }

    fun plans(): List<SavedPlan> {
        if (!plansFile.exists()) return emptyList()
        return try {
            val a = JSONArray(plansFile.readText())
            (0 until a.length()).map { i ->
                val item = a.getJSONObject(i)
                val p = item.getJSONObject("profile")
                SavedPlan(item.getString("id"), item.getString("title"),
                    points(item.getJSONArray("stops")),
                    RidingProfile(p.optString("bike", "touring"), p.optBoolean("electric", true),
                        p.optString("surface", "any"), p.optBoolean("hills")),
                    parseRoute(item.getJSONObject("route")))
            }
        } catch (_: Exception) { emptyList() }
    }
    fun savePlan(plan: SavedPlan) { writePlans(plans().filterNot { it.id == plan.id } + plan) }
    fun deletePlan(id: String) { writePlans(plans().filterNot { it.id == id }) }
    fun deleteRide(id: String) { writeRides(rides().filterNot { it.id == id }) }
    private fun writePlans(items: List<SavedPlan>) {
        atomic(plansFile, JSONArray().also { a -> items.forEach { item ->
            a.put(JSONObject().put("id", item.id).put("title", item.title)
                .put("stops", jsonPoints(item.stops))
                .put("profile", JSONObject().put("bike", item.profile.bike)
                    .put("electric", item.profile.electric).put("surface", item.profile.surface)
                    .put("hills", item.profile.gentleHills))
                .put("route", routeJson(item.route)))
        } }.toString())
    }

    fun rides(): List<SavedRide> {
        if (!ridesFile.exists()) return emptyList()
        return try {
            val array = JSONArray(ridesFile.readText())
            (0 until array.length()).map { i ->
                val item = array.getJSONObject(i)
                SavedRide(item.getString("id"), item.getString("title"), item.getLong("time"),
                    points(item.getJSONArray("points")), item.getDouble("meters"),
                    item.optJSONArray("samples")?.let { a -> (0 until a.length()).map { n ->
                        val s = a.getJSONObject(n)
                        RidePoint(Point(s.getDouble("lat"), s.getDouble("lon")),
                            s.getLong("time"), if (s.isNull("altitude")) null else s.getDouble("altitude"),
                            if (s.isNull("speed")) null else s.getDouble("speed").toFloat(), s.optInt("segment"))
                    } } ?: emptyList(),
                    item.optJSONArray("bikeSamples")?.let { a -> (0 until a.length()).map { n ->
                        val s = a.getJSONObject(n)
                        val m = s.getJSONObject("value")
                        BikeSample(s.getLong("time"), s.getInt("segment"), BikeMeasurement(
                            m.takeInt("battery"), m.takeInt("rider"), m.takeInt("motor"),
                            m.takeInt("mode"), m.takeInt("cadence"),
                            m.takeDouble("speed")))
                    } } ?: emptyList())
            }
        } catch (_: Exception) { emptyList() }
    }

    fun places(): List<Place> {
        if (!placesFile.exists()) return emptyList()
        return try {
            val array = JSONArray(placesFile.readText())
            (0 until array.length()).map { i ->
                val item = array.getJSONObject(i)
                Place(item.getString("id"), item.getString("name"),
                    Point(item.getDouble("lat"), item.getDouble("lon")))
            }
        } catch (_: Exception) { emptyList() }
    }

    fun savePlace(place: Place) {
        val next = places().filterNot { it.id == place.id } + place
        savePlaces(next)
    }

    fun deletePlace(id: String) { savePlaces(places().filterNot { it.id == id }) }

    private fun savePlaces(places: List<Place>) {
        atomic(placesFile, JSONArray().also { array -> places.forEach {
            array.put(JSONObject().put("id", it.id).put("name", it.name)
                .put("lat", it.coordinate.lat).put("lon", it.coordinate.lon))
        } }.toString())
    }

    fun saveRide(track: List<RidePoint>, bike: List<BikeSample> = emptyList()): SavedRide {
        require(track.size >= 2)
        val geometry = track.map { it.point }
        val distance = track.zipWithNext().sumOf { (a, b) ->
            if (a.segment == b.segment) a.point.distance(b.point) else 0.0
        }
        val ride = SavedRide(UUID.randomUUID().toString(), "Fahrt ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date())}",
            track.first().time, geometry, distance, track, bike)
        writeRides(rides() + ride)
        return ride
    }
    private fun writeRides(rides: List<SavedRide>) {
        val array = JSONArray()
        rides.forEach { item ->
            array.put(JSONObject().put("id", item.id).put("title", item.title).put("time", item.time)
                .put("meters", item.meters).put("points", jsonPoints(item.points))
                .put("samples", JSONArray().also { samples -> item.samples.forEach { sample ->
                    samples.put(JSONObject().put("lat", sample.point.lat).put("lon", sample.point.lon)
                        .put("time", sample.time).put("altitude", sample.altitude)
                        .put("speed", sample.speed).put("segment", sample.segment))
                } })
                .put("bikeSamples", JSONArray().also { samples -> item.bikeSamples.forEach { s ->
                    samples.put(JSONObject().put("time", s.time).put("segment", s.segment)
                        .put("value", JSONObject().put("battery", s.value.battery)
                            .put("rider", s.value.riderWatts).put("motor", s.value.motorWatts)
                            .put("mode", s.value.assistMode).put("cadence", s.value.cadence)
                            .put("speed", s.value.speedKph)))
                } }))
        }
        atomic(ridesFile, array.toString())
    }

    fun gpx(ride: SavedRide): String {
        val name = xml(ride.title)
        val samples = ride.samples.ifEmpty { ride.points.map { p -> RidePoint(p, ride.time, null, null, 0) } }
        val segments = samples.groupBy { it.segment }.values.joinToString("") { group ->
            "<trkseg>" + group.joinToString("") { s ->
                "<trkpt lat=\"${s.point.lat}\" lon=\"${s.point.lon}\">" +
                    (s.altitude?.let { "<ele>$it</ele>" } ?: "") +
                    "<time>${java.time.Instant.ofEpochMilli(s.time)}</time></trkpt>"
            } + "</trkseg>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<gpx version=\"1.1\" creator=\"BikeNavi Android\" xmlns=\"http://www.topografix.com/GPX/1/1\">" +
            "<trk><name>$name</name>$segments</trk></gpx>"
    }

    private fun xml(s: String) = s.replace("&", "&amp;").replace("<", "&lt;")
        .replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")
    private fun JSONObject.takeInt(key: String) = if (isNull(key)) null else getInt(key)
    private fun JSONObject.takeDouble(key: String) = if (isNull(key)) null else getDouble(key)
    private fun routeJson(route: Route) = JSONObject().put("points", jsonPoints(route.points))
        .put("meters", route.meters).put("surfaces", JSONArray(route.surfaces))
        .put("maneuvers", JSONArray().also { a -> route.maneuvers.forEach {
            a.put(JSONObject().put("index", it.index).put("instruction", it.instruction))
        } }).put("waypointIndices", JSONArray(route.waypointIndices))
    private fun parseRoute(json: JSONObject) = Route(points(json.getJSONArray("points")),
        json.getDouble("meters"),
        json.optJSONArray("surfaces")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
        json.optJSONArray("maneuvers")?.let { a -> (0 until a.length()).map {
            val m = a.getJSONObject(it); Maneuver(m.getInt("index"), m.getString("instruction"))
        } } ?: emptyList(),
        json.optJSONArray("waypointIndices")?.let { a -> (0 until a.length()).map { a.getInt(it) } } ?: emptyList())
    private fun points(a: JSONArray) = (0 until a.length()).map {
        val p = a.getJSONArray(it)
        Point(p.getDouble(0), p.getDouble(1))
    }
    private fun jsonPoints(points: List<Point>) = JSONArray().also { array ->
        points.forEach { array.put(JSONArray().put(it.lat).put(it.lon)) }
    }
    private fun atomic(file: File, data: String) {
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(data)
        if (!temp.renameTo(file)) {
            temp.delete()
            throw java.io.IOException("Lokale Datei konnte nicht gespeichert werden.")
        }
    }
}
