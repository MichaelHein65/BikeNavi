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
data class SavedRide(
    val id: String, val title: String, val time: Long, val points: List<Point>, val meters: Double,
    val samples: List<RidePoint> = emptyList()
)

/** Internal app storage only. Atomic replacement prevents a failed download from damaging a cached region. */
class LocalData(private val context: Context) {
    private val regionFile = File(context.filesDir, "osm-region.json")
    private val ridesFile = File(context.filesDir, "rides.json")
    private val routeFile = File(context.filesDir, "active-route.json")
    private val placesFile = File(context.filesDir, "places.json")

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
        val maneuvers = JSONArray().also { a -> route.maneuvers.forEach {
            a.put(JSONObject().put("index", it.index).put("instruction", it.instruction))
        } }
        atomic(routeFile, JSONObject().put("points", jsonPoints(route.points))
            .put("meters", route.meters).put("surfaces", JSONArray(route.surfaces))
            .put("maneuvers", maneuvers).put("waypointIndices", JSONArray(route.waypointIndices)).toString())
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

    fun saveRide(track: List<RidePoint>): SavedRide {
        require(track.size >= 2)
        val geometry = track.map { it.point }
        val distance = track.zipWithNext().sumOf { (a, b) ->
            if (a.segment == b.segment) a.point.distance(b.point) else 0.0
        }
        val ride = SavedRide(UUID.randomUUID().toString(), "Fahrt ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date())}",
            track.first().time, geometry, distance, track)
        val rides = rides() + ride
        val array = JSONArray()
        rides.forEach { item ->
            array.put(JSONObject().put("id", item.id).put("title", item.title).put("time", item.time)
                .put("meters", item.meters).put("points", jsonPoints(item.points))
                .put("samples", JSONArray().also { samples -> item.samples.forEach { sample ->
                    samples.put(JSONObject().put("lat", sample.point.lat).put("lon", sample.point.lon)
                        .put("time", sample.time).put("altitude", sample.altitude)
                        .put("speed", sample.speed).put("segment", sample.segment))
                } }))
        }
        atomic(ridesFile, array.toString())
        return ride
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
