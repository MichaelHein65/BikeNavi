package de.michaelhein.bikenavi

import kotlin.math.*

data class RouteProgress(
    val traveled: Double,
    val remaining: Double,
    val offRoute: Double,
    val snapped: Point?,
    val next: Maneuver?,
    val toTurn: Double
)

/** Windowed segment projection avoids jumping to the return leg of a loop. */
class RouteTracker {
    private var traveled = 0.0
    private var lastTime: Long? = null
    fun update(route: Route, position: Point, accuracy: Float, bearing: Float?, time: Long): RouteProgress? {
        if (route.points.size < 2) return null
        val cumulative = ArrayList<Double>()
        cumulative.add(0.0)
        route.points.zipWithNext().forEach { (a, b) -> cumulative.add(cumulative.last() + a.distance(b)) }
        val elapsed = ((time - (lastTime ?: time)).coerceAtLeast(0L) / 1000.0)
        val forward = if (lastTime == null) Double.POSITIVE_INFINITY else min(400.0, max(200.0, elapsed * 20))
        val scaleX = cos(Math.toRadians(position.lat)) * 111320.0
        var bestDistance = Double.POSITIVE_INFINITY
        var bestProgress = traveled
        var bestPoint: Point? = null
        var goodDirection = true
        for (i in 0 until route.points.lastIndex) {
            if (cumulative[i + 1] < max(0.0, traveled - 150) || cumulative[i] > traveled + forward) continue
            val a = route.points[i]; val b = route.points[i + 1]
            val ax = (a.lon - position.lon) * scaleX
            val ay = (a.lat - position.lat) * 111320.0
            val dx = (b.lon - a.lon) * scaleX
            val dy = (b.lat - a.lat) * 111320.0
            val t = (-(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)).coerceIn(0.0, 1.0)
            val gap = hypot(ax + t * dx, ay + t * dy)
            if (gap < bestDistance - 1) {
                bestDistance = gap
                bestProgress = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
                bestPoint = Point(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon))
                if (bearing != null && bearing >= 0) {
                    val heading = (Math.toDegrees(atan2(dx, dy)) + 360) % 360
                    val angle = abs((bearing - heading + 540) % 360 - 180)
                    goodDirection = angle <= 65
                } else goodDirection = true
            }
        }
        if (bestPoint == null) return null
        val magnet = bestDistance <= 25 && accuracy in 0f..25f && goodDirection
        if (magnet) { traveled = bestProgress; lastTime = time }
        val next = route.maneuvers.firstOrNull { it.index in cumulative.indices && cumulative[it.index] > traveled + 12 }
        return RouteProgress(traveled, max(0.0, cumulative.last() - traveled), bestDistance,
            if (magnet) bestPoint else null, next,
            next?.let { max(0.0, cumulative[it.index] - traveled) } ?: 0.0)
    }
}

class ReroutePolicy {
    private var firstOff: Long? = null
    private var count = 0
    private var lastReroute = 0L
    fun shouldReroute(progress: RouteProgress, accuracy: Float, now: Long): Boolean {
        if (accuracy !in 0f..25f || progress.offRoute < 35) {
            firstOff = null
            count = 0
            return false
        }
        if (firstOff == null) firstOff = now
        count++
        if (count < 3 || now - firstOff!! < 5000 || now - lastReroute < 10000) return false
        lastReroute = now
        firstOff = null
        count = 0
        return true
    }
}
