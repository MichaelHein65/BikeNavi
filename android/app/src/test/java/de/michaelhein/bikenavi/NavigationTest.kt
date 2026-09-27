package de.michaelhein.bikenavi

import org.junit.Assert.*
import org.junit.Test

class NavigationTest {
    private val a = Point(49.0, 8.0)
    private val b = Point(49.0, 8.001)
    private val c = Point(49.001, 8.001)
    private val route = Route(listOf(a, b, c), a.distance(b) + b.distance(c),
        listOf("asphalt", "gravel"), listOf(Maneuver(1, "Links abbiegen"), Maneuver(2, "Ziel erreicht")))

    @Test fun progressAndTurnAreProjectedOntoSegments() {
        val result = RouteTracker().update(route, Point(49.0, 8.0005), 5f, null, 10000)!!
        assertEquals(a.distance(b) / 2, result.traveled, 3.0)
        assertEquals("Links abbiegen", result.next?.instruction)
        assertNotNull(result.snapped)
    }

    @Test fun rerouteNeedsThreeGoodFixesAcrossFiveSeconds() {
        val policy = ReroutePolicy()
        val off = RouteProgress(0.0, 500.0, 40.0, null, null, 0.0)
        assertFalse(policy.shouldReroute(off, 5f, 100000))
        assertFalse(policy.shouldReroute(off, 5f, 102000))
        assertTrue(policy.shouldReroute(off, 5f, 105000))
        assertFalse(policy.shouldReroute(off, 5f, 106000))
    }
}
