package de.michaelhein.bikenavi

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.PriorityQueue
import kotlin.math.*

data class Point(val lat: Double, val lon: Double) {
    fun distance(other: Point): Double {
        val p = Math.toRadians(lat)
        val q = Math.toRadians(other.lat)
        val a = sin((q - p) / 2).pow(2) +
            cos(p) * cos(q) * sin(Math.toRadians(other.lon - lon) / 2).pow(2)
        return 6371000.0 * 2 * asin(min(1.0, sqrt(a)))
    }
}

data class Edge(val to: Long, val way: Long, val length: Double, val surface: String, val incline: Double = 0.0)
data class Turn(val via: Long, val from: Long, val to: Set<Long>, val only: Boolean,
                val uTurn: Boolean = false)
data class Maneuver(val index: Int, val instruction: String)
data class RidingProfile(
    val bike: String = "touring",
    val electric: Boolean = true,
    val surface: String = "any",
    val gentleHills: Boolean = false
)
data class Route(
    val points: List<Point>,
    val meters: Double,
    val surfaces: List<String>,
    val maneuvers: List<Maneuver> = emptyList(),
    val waypointIndices: List<Int> = emptyList()
)

class RoutingException(message: String) : Exception(message)

/**
 * Compiles the same conservative OSM subset as server/bikenavi/offline.py:
 * gates require explicit permission, conditional access is rejected, only
 * node-via restrictions are interpreted. Unknown restrictions close from-ways.
 */
class BikeGraph private constructor(
    val nodes: Map<Long, Point>,
    val edges: Map<Long, List<Edge>>,
    val turns: List<Turn>
) {
    companion object {
        private val allow = setOf("yes", "designated", "official", "permissive")
        private val roads = setOf("cycleway", "residential", "living_street", "unclassified",
            "service", "tertiary", "tertiary_link", "secondary", "secondary_link",
            "primary", "primary_link", "track")
        private val impassable = setOf("impassable", "very_horrible", "horrible")

        private fun tags(o: JSONObject) = o.optJSONObject("tags") ?: JSONObject()
        private fun conditional(t: JSONObject): Boolean = t.keys().asSequence().any {
            it.contains("conditional") && it.substringBefore(':') in
                setOf("access", "bicycle", "vehicle", "oneway", "restriction")
        }
        private fun access(t: JSONObject, direction: String? = null, default: Boolean = true): Boolean {
            for (key in listOf("bicycle", "vehicle", "access")) {
                val directional = direction?.let { t.optString("$key:$it").takeIf(String::isNotEmpty) }
                val value = directional ?: t.optString(key).takeIf(String::isNotEmpty)
                if (value != null) return value in allow
            }
            return default
        }

        fun compile(root: JSONObject): BikeGraph {
            if (root.has("remark")) throw RoutingException("Unvollständige Overpass-Antwort.")
            val data = root.optJSONArray("elements") ?: throw RoutingException("Keine OSM-Wegedaten.")
            val nodes = HashMap<Long, Point>()
            val ways = HashMap<Long, JSONObject>()
            val relations = ArrayList<JSONObject>()
            val blockedNodes = HashSet<Long>()
            for (i in 0 until data.length()) {
                val o = data.getJSONObject(i)
                when (o.optString("type")) {
                    "node" -> {
                        if (!o.has("lat") || !o.has("lon")) continue
                        val id = o.getLong("id")
                        nodes[id] = Point(o.getDouble("lat"), o.getDouble("lon"))
                        val t = tags(o)
                        val barrier = t.optString("barrier")
                        val gate = barrier in setOf("gate", "lift_gate", "swing_gate")
                        if (!access(t) || conditional(t) || t.optString("locked") == "yes" ||
                            (barrier.isNotEmpty() && barrier !in setOf("no", "bollard", "entrance") &&
                                !(gate && access(t, default = false)) && t.optString("bicycle") !in allow))
                            blockedNodes.add(id)
                    }
                    "way" -> if (o.has("nodes")) ways[o.getLong("id")] = o
                    "relation" -> relations.add(o)
                }
            }
            val blockedWays = HashSet<Long>()
            val turns = ArrayList<Turn>()
            for (rel in relations) {
                val t = tags(rel)
                if (t.optString("type") != "restriction") continue
                if ("bicycle" in t.optString("except").split(";") && !t.has("restriction:bicycle")) continue
                val kind = t.optString("restriction:bicycle", t.optString("restriction"))
                if (kind.isEmpty() && !conditional(t)) continue
                val members = rel.optJSONArray("members") ?: JSONArray()
                val from = ArrayList<Long>()
                val to = HashSet<Long>()
                val viaNodes = ArrayList<Long>()
                val viaWays = ArrayList<Long>()
                for (i in 0 until members.length()) {
                    val m = members.getJSONObject(i)
                    when (m.optString("role") to m.optString("type")) {
                        "from" to "way" -> from.add(m.getLong("ref"))
                        "to" to "way" -> to.add(m.getLong("ref"))
                        "via" to "node" -> viaNodes.add(m.getLong("ref"))
                        "via" to "way" -> viaWays.add(m.getLong("ref"))
                    }
                }
                if (conditional(t) || viaNodes.size != 1 || viaWays.isNotEmpty() ||
                    from.isEmpty() || to.isEmpty() || !(kind.startsWith("no_") || kind.startsWith("only_"))) {
                    blockedWays.addAll(from)
                    blockedWays.addAll(viaWays)
                    continue
                }
                from.forEach { turns.add(Turn(viaNodes.first(), it, to,
                    kind.startsWith("only_"), kind in setOf("no_u_turn", "only_u_turn"))) }
            }
            val result = HashMap<Long, MutableList<Edge>>()
            for ((id, way) in ways) {
                val t = tags(way)
                val highway = t.optString("highway")
                if (id in blockedWays || highway.isEmpty() || highway in setOf("motorway",
                        "motorway_link", "trunk", "trunk_link", "steps", "construction",
                        "proposed", "raceway") || conditional(t) || !access(t) ||
                    t.optString("smoothness") in impassable || t.optString("ford") == "yes" ||
                    t.optString("motorroad") == "yes" ||
                    (highway !in roads && t.optString("bicycle") !in allow)) continue
                val one = t.optString("oneway:bicycle",
                    t.optString("oneway", if (t.optString("junction") == "roundabout") "yes" else "no"))
                if (one !in setOf("yes", "1", "true", "no", "0", "false", "-1")) continue
                val sequence = way.getJSONArray("nodes")
                for (i in 0 until sequence.length() - 1) {
                    val a = sequence.getLong(i)
                    val b = sequence.getLong(i + 1)
                    val p = nodes[a] ?: continue
                    val q = nodes[b] ?: continue
                    if (a == b || a in blockedNodes || b in blockedNodes) continue
                    val length = p.distance(q)
                    val surface = t.optString("surface", "unknown")
                    val incline = t.optString("incline", "0").removeSuffix("%").toDoubleOrNull()
                        ?.coerceIn(-40.0, 40.0) ?: 0.0
                    if (one != "-1" && access(t, "forward"))
                        result.getOrPut(a) { ArrayList() }.add(Edge(b, id, length, surface, incline))
                    if (one !in setOf("yes", "1", "true") && access(t, "backward"))
                        result.getOrPut(b) { ArrayList() }.add(Edge(a, id, length, surface, -incline))
                }
            }
            if (nodes.size > 150_000 || result.values.sumOf { it.size } > 350_000)
                throw RoutingException("Gebiet zu groß. Wähle eine kürzere Etappe.")
            return BikeGraph(nodes, result, turns)
        }
    }

    private val paved = setOf("paved", "asphalt", "concrete", "concrete:plates",
        "concrete:lanes", "paving_stones", "sett", "cobblestone", "metal", "wood")

    fun routeThrough(points: List<Point>, profile: RidingProfile = RidingProfile()): Route {
        require(points.size >= 2)
        var remainingUnpaved = 100
        val legs = points.zipWithNext().map { (a, b) ->
            val leg = route(a, b, profile, remainingUnpaved)
            if (profile.surface == "pavedOnly") {
                val consumed = leg.points.zipWithNext().mapIndexed { i, (p, q) ->
                    if (leg.surfaces.getOrNull(i) in paved) 0 else ceil(p.distance(q)).toInt()
                }.sum()
                remainingUnpaved = (remainingUnpaved - consumed).coerceAtLeast(0)
            }
            leg
        }
        val all = ArrayList<Point>()
        val surfaces = ArrayList<String>()
        val instructions = ArrayList<Maneuver>()
        val stops = ArrayList<Int>()
        legs.forEachIndexed { index, leg ->
            val offset = if (index == 0) 0 else all.size - 1
            if (index == 0) all.addAll(leg.points) else all.addAll(leg.points.drop(1))
            surfaces.addAll(leg.surfaces)
            instructions.addAll(leg.maneuvers.filter { it.index < leg.points.size - 1 }
                .map { it.copy(index = it.index + offset) })
            stops.add(all.lastIndex)
            if (index < legs.lastIndex) instructions.add(Maneuver(all.lastIndex, "Zwischenziel erreicht"))
        }
        instructions.add(Maneuver(all.lastIndex, "Ziel erreicht"))
        return Route(all, legs.sumOf { it.meters }, surfaces, instructions, stops)
    }

    fun route(start: Point, goal: Point, profile: RidingProfile = RidingProfile(),
              maxUnpavedMeters: Int = 100): Route {
        if (edges.isEmpty()) throw RoutingException("Keine befahrbaren Wege im Gebiet.")
        val reachable = edges.keys + edges.values.flatten().map { it.to }
        fun nearest(p: Point): Pair<Long, Double> = reachable.asSequence()
            .map { it to (nodes[it]?.distance(p) ?: Double.POSITIVE_INFINITY) }
            .minByOrNull { it.second } ?: throw RoutingException("Kein Weg gefunden.")
        val (origin, startGap) = nearest(start)
        val (destination, endGap) = nearest(goal)
        if (startGap > 500 || endGap > 500)
            throw RoutingException("Start oder Ziel liegt mehr als 500 m vom Wegenetz entfernt.")
        if (origin == destination) {
            // A short trip can have the same nearest vertex at both ends.
            // Resolve it along a directed OSM edge, preserving its one-way rule.
            val direct = edges.asSequence().flatMap { (from, outgoing) ->
                outgoing.asSequence().mapNotNull { edge ->
                    val a = nodes[from] ?: return@mapNotNull null
                    val b = nodes[edge.to] ?: return@mapNotNull null
                    val first = project(start, a, b)
                    val last = project(goal, a, b)
                    if (first.second > 250 || last.second > 250 || first.first >= last.first - 1e-6)
                        return@mapNotNull null
                    if (profile.surface == "pavedOnly" && edge.surface !in paved &&
                        edge.length * (last.first - first.first) > maxUnpavedMeters) return@mapNotNull null
                    val routePoints = ArrayList<Point>()
                    val sections = ArrayList<String>()
                    fun append(p: Point, surface: String) {
                        if (routePoints.lastOrNull()?.distance(p)?.let { it < 0.05 } == true) return
                        if (routePoints.isNotEmpty()) sections.add(surface)
                        routePoints.add(p)
                    }
                    append(start, "unknown")
                    append(interpolate(a, b, first.first), "unknown")
                    append(interpolate(a, b, last.first), edge.surface)
                    append(goal, "unknown")
                    if (routePoints.size < 2) null else Route(routePoints,
                        routePoints.zipWithNext().sumOf { (p, q) -> p.distance(q) },
                        sections, listOf(Maneuver(routePoints.lastIndex, "Ziel erreicht")))
                }
            }.minByOrNull { it.meters }
            return direct ?: throw RoutingException(
                "Start und Ziel fallen auf denselben Netzknoten. Wähle präzisere Punkte.")
        }
        data class State(val node: Long, val previous: Long, val incoming: Long, val unpavedBucket: Int)
        data class Candidate(val state: State, val score: Double)
        val startState = State(origin, -1, -1, 0)
        val distance = HashMap<State, Double>()
        val previous = HashMap<State, Pair<State, Edge>>()
        val queue = PriorityQueue<Candidate>(compareBy { it.score })
        distance[startState] = 0.0
        queue.add(Candidate(startState, 0.0))
        var reached: State? = null
        while (queue.isNotEmpty()) {
            val (current, score) = queue.remove()
            val spent = distance[current] ?: continue
            if (score > spent + (nodes[current.node]?.distance(nodes[destination]!!) ?: 0.0) + 0.01) continue
            if (current.node == destination) { reached = current; break }
            for (edge in edges[current.node].orEmpty()) {
                val rules = turns.filter { it.via == current.node && it.from == current.incoming }
                if (rules.any { rule ->
                        if (rule.only) edge.way !in rule.to ||
                            (rule.uTurn && edge.to != current.previous) ||
                            (!rule.uTurn && edge.to == current.previous)
                        else edge.way in rule.to && (!rule.uTurn || edge.to == current.previous)
                    }) continue
                val offRoad = edge.surface !in paved
                val unpavedBucket = if (profile.surface == "pavedOnly")
                    current.unpavedBucket + if (offRoad) ceil(edge.length / 10.0).toInt() else 0
                else 0
                if (unpavedBucket * 10 > maxUnpavedMeters) continue
                val next = State(edge.to, current.node, edge.way, unpavedBucket)
                val penalty = (if (profile.surface == "preferPaved" && offRoad) 8.0 else 0.0) +
                    (if (profile.bike == "road" && offRoad) 3.0 else 0.0) +
                    (if (profile.gentleHills) max(0.0, edge.incline) / 5.0 else 0.0)
                val newCost = spent + edge.length * (1.0 + penalty)
                if (newCost >= (distance[next] ?: Double.POSITIVE_INFINITY)) continue
                distance[next] = newCost
                previous[next] = current to edge
                queue.add(Candidate(next, newCost + nodes[edge.to]!!.distance(nodes[destination]!!)))
            }
        }
        var state = reached ?: throw RoutingException("Keine durchgehende Fahrradroute gefunden.")
        val path = ArrayList<Point>()
        val surfaces = ArrayList<String>()
        path.add(nodes[state.node]!!)
        while (state != startState) {
            val (before, edge) = previous[state] ?: throw RoutingException("Route unterbrochen.")
            surfaces.add(edge.surface)
            state = before
            path.add(nodes[state.node]!!)
        }
        path.reverse()
        surfaces.reverse()
        val maneuvers = ArrayList<Maneuver>()
        for (i in 1 until path.size - 1) {
            val incoming = bearing(path[i - 1], path[i])
            val outgoing = bearing(path[i], path[i + 1])
            val angle = (outgoing - incoming + 540.0) % 360.0 - 180.0
            if (abs(angle) >= 40) maneuvers.add(Maneuver(i,
                if (abs(angle) >= 150) "Wenden" else if (angle > 0) "Rechts abbiegen" else "Links abbiegen"))
        }
        maneuvers.add(Maneuver(path.lastIndex, "Ziel erreicht"))
        return Route(path, path.zipWithNext().sumOf { (a, b) -> a.distance(b) }, surfaces, maneuvers)
    }

    private fun bearing(a: Point, b: Point): Double {
        val delta = Math.toRadians(b.lon - a.lon)
        val y = sin(delta) * cos(Math.toRadians(b.lat))
        val x = cos(Math.toRadians(a.lat)) * sin(Math.toRadians(b.lat)) -
            sin(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * cos(delta)
        return (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
    }
    private fun interpolate(a: Point, b: Point, t: Double) =
        Point(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t)
    private fun project(p: Point, a: Point, b: Point): Pair<Double, Double> {
        val cosLat = cos(Math.toRadians(p.lat))
        val dx = (b.lon - a.lon) * cosLat
        val dy = b.lat - a.lat
        val t = (((p.lon - a.lon) * cosLat * dx + (p.lat - a.lat) * dy) /
            max(1e-20, dx * dx + dy * dy)).coerceIn(0.0, 1.0)
        return t to p.distance(interpolate(a, b, t))
    }
}

/** Public OSM source accessed directly by the phone; the Raspberry Pi is never consulted. */
object Overpass {
    private val endpoints = listOf("https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter")

    fun download(south: Double, west: Double, north: Double, east: Double): JSONObject {
        require(north > south && east > west && north - south <= 0.15 && east - west <= 0.15)
        val query = "[out:json][timeout:25][maxsize:67108864];" +
            "way[\"highway\"]($south,$west,$north,$east)->.roads;" +
            "rel(bw.roads)[\"type\"=\"restriction\"]->.rules;" +
            "(.roads;node(w.roads);.rules;);out body;"
        var last: Exception? = null
        for (endpoint in endpoints) {
            try {
                val connection = URL(endpoint).openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"
                    connection.connectTimeout = 15000
                    connection.readTimeout = 40000
                    connection.doOutput = true
                    connection.setRequestProperty("User-Agent", "BikeNaviAndroid/0.1 (https://github.com/MichaelHein65/BikeNavi)")
                    connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                    connection.outputStream.use { it.write(("data=" + URLEncoder.encode(query, "UTF-8")).toByteArray()) }
                    if (connection.responseCode !in 200..299) throw RoutingException("Overpass HTTP ${connection.responseCode}")
                    val bytes = connection.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            if (output.size() > 32 * 1024 * 1024)
                                throw RoutingException("OSM-Antwort zu groß.")
                        }
                        output.toByteArray()
                    }
                    val root = JSONObject(String(bytes, Charsets.UTF_8))
                    if (root.has("remark") || !root.has("elements"))
                        throw RoutingException("Overpass lieferte unvollständige Daten.")
                    return root
                } finally { connection.disconnect() }
            } catch (e: Exception) { last = e }
        }
        throw RoutingException("OSM-Wegedaten nicht erreichbar: ${last?.message}")
    }
}
