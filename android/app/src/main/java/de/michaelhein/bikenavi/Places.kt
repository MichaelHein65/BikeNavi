package de.michaelhein.bikenavi

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class Place(val id: String, val name: String, val coordinate: Point)

/** Manual searches only, with a bounded result count and configurable provider. */
object PlaceSearch {
    fun search(text: String, near: Point?, endpoint: String): List<Place> {
        require(text.length in 2..200)
        val root = endpoint.trimEnd('/')
        require(root.startsWith("https://"))
        val query = "q=" + URLEncoder.encode(text, "UTF-8") + "&limit=8&lang=de" +
            (near?.let { "&lat=${it.lat}&lon=${it.lon}" } ?: "")
        val connection = URL("$root/api/?$query").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 10000
            connection.readTimeout = 12000
            connection.setRequestProperty("User-Agent",
                "BikeNaviAndroid/0.1 (https://github.com/MichaelHein65/BikeNavi)")
            if (connection.responseCode !in 200..299) throw RoutingException("Ortssuche HTTP ${connection.responseCode}")
            val bytes = connection.inputStream.use { it.readNBytes(512 * 1024 + 1) }
            if (bytes.size > 512 * 1024) throw RoutingException("Suchantwort zu groß.")
            val features = JSONObject(String(bytes, Charsets.UTF_8)).getJSONArray("features")
            return (0 until features.length()).mapNotNull { i ->
                val item = features.getJSONObject(i)
                val coordinates = item.optJSONObject("geometry")?.optJSONArray("coordinates") ?: return@mapNotNull null
                if (coordinates.length() < 2) return@mapNotNull null
                val properties = item.optJSONObject("properties") ?: JSONObject()
                val name = listOf("name", "city", "state", "country").mapNotNull {
                    properties.optString(it).takeIf(String::isNotBlank)
                }.distinct().joinToString(", ")
                if (name.isBlank()) return@mapNotNull null
                Place("photon-$i", name, Point(coordinates.getDouble(1), coordinates.getDouble(0)))
            }
        } finally { connection.disconnect() }
    }
}
