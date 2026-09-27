package de.michaelhein.bikenavi

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.*

/**
 * Persistent, independent OSM regions. Downloads are atomic and keyed by
 * geographic tile; stale or partial responses never replace complete data.
 */
class GraphRepository(context: Context) {
    private val folder = File(context.filesDir, "osm-tiles-v1").also { it.mkdirs() }
    private val tileDegrees = 0.05
    private data class Tile(val x: Int, val y: Int) {
        val box get() = Region(y * 0.05 - 90.0, x * 0.05 - 180.0,
            (y + 1) * 0.05 - 90.0, (x + 1) * 0.05 - 180.0)
    }
    private fun tile(p: Point) = Tile(floor((p.lon + 180) / tileDegrees).toInt(),
        floor((p.lat + 90) / tileDegrees).toInt())

    fun graphFor(waypoints: List<Point>, onProgress: (Int, Int) -> Unit = { _, _ -> }): BikeGraph {
        require(waypoints.size >= 2)
        val selected = LinkedHashSet<Tile>()
        for ((a, b) in waypoints.zipWithNext()) {
            val meters = a.distance(b)
            // Sample every 1.5 km, include neighboring cells for plausible detours.
            val steps = ceil(meters / 1500.0).toInt().coerceAtLeast(1)
            for (i in 0..steps) {
                val f = i.toDouble() / steps
                val base = tile(Point(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f))
                for (dx in -1..1) for (dy in -1..1) selected.add(Tile(base.x + dx, base.y + dy))
            }
        }
        if (selected.size > 90)
            throw RoutingException("Gebiet zu groß für eine Planung. Bitte in kürzere Etappen teilen.")
        val merged = LinkedHashMap<String, JSONObject>()
        selected.forEachIndexed { index, key ->
            val file = File(folder, "${key.x}_${key.y}.json")
            val data = if (file.exists()) {
                try { JSONObject(file.readText()) } catch (_: Exception) { download(file, key.box) }
            } else download(file, key.box)
            val elements = data.getJSONArray("elements")
            for (j in 0 until elements.length()) {
                val element = elements.getJSONObject(j)
                merged["${element.optString("type")}:${element.optLong("id")}"] = element
            }
            onProgress(index + 1, selected.size)
        }
        return BikeGraph.compile(JSONObject().put("elements", JSONArray().also { array ->
            merged.values.forEach { array.put(it) }
        }))
    }

    private fun download(file: File, bounds: Region): JSONObject {
        val result = Overpass.download(bounds.south, bounds.west, bounds.north, bounds.east)
        BikeGraph.compile(result) // Validate before retaining.
        val temp = File(folder, file.name + ".tmp")
        temp.writeText(result.toString())
        if (!temp.renameTo(file)) {
            temp.delete()
            throw java.io.IOException("OSM-Gebiet konnte nicht gespeichert werden.")
        }
        return result
    }
}
