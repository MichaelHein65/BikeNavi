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

data class SavedRide(val id: String, val title: String, val time: Long, val points: List<Point>, val meters: Double)

/** Internal app storage only. Atomic replacement prevents a failed download from damaging a cached region. */
class LocalData(private val context: Context) {
    private val regionFile = File(context.filesDir, "osm-region.json")
    private val ridesFile = File(context.filesDir, "rides.json")
    private val routeFile = File(context.filesDir, "active-route.json")

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
                json.optJSONArray("surfaces")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList())
        } catch (_: Exception) { null }
    }

    fun saveRoute(route: Route) {
        atomic(routeFile, JSONObject().put("points", jsonPoints(route.points))
            .put("meters", route.meters).put("surfaces", JSONArray(route.surfaces)).toString())
    }

    fun rides(): List<SavedRide> {
        if (!ridesFile.exists()) return emptyList()
        return try {
            val array = JSONArray(ridesFile.readText())
            (0 until array.length()).map { i ->
                val item = array.getJSONObject(i)
                SavedRide(item.getString("id"), item.getString("title"), item.getLong("time"),
                    points(item.getJSONArray("points")), item.getDouble("meters"))
            }
        } catch (_: Exception) { emptyList() }
    }

    fun saveRide(track: List<Point>): SavedRide {
        require(track.size >= 2)
        val distance = track.zipWithNext().sumOf { (a, b) -> a.distance(b) }
        val ride = SavedRide(UUID.randomUUID().toString(), "Fahrt ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date())}",
            System.currentTimeMillis(), track, distance)
        val rides = rides() + ride
        val array = JSONArray()
        rides.forEach { item ->
            array.put(JSONObject().put("id", item.id).put("title", item.title).put("time", item.time)
                .put("meters", item.meters).put("points", jsonPoints(item.points)))
        }
        atomic(ridesFile, array.toString())
        return ride
    }

    fun gpx(ride: SavedRide): String {
        val name = xml(ride.title)
        val points = ride.points.joinToString("") { "<trkpt lat=\"${it.lat}\" lon=\"${it.lon}\"/>" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<gpx version=\"1.1\" creator=\"BikeNavi Android\" xmlns=\"http://www.topografix.com/GPX/1/1\">" +
            "<trk><name>$name</name><trkseg>$points</trkseg></trk></gpx>"
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
