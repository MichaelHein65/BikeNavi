package de.michaelhein.bikenavi

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RoutingTest {
    private fun graph(ways: String, relation: String = "") = BikeGraph.compile(JSONObject(
        """{"elements":[
          {"type":"node","id":1,"lat":45.8000,"lon":15.9000},
          {"type":"node","id":2,"lat":45.8000,"lon":15.9010},
          {"type":"node","id":3,"lat":45.8000,"lon":15.9020},
          {"type":"node","id":4,"lat":45.8010,"lon":15.9010},
          {"type":"node","id":5,"lat":45.8010,"lon":15.9020}
          $ways $relation
        ]}"""
    ))

    @Test fun allowedGateAndOneWay() {
        val g = BikeGraph.compile(JSONObject("""{"elements":[
          {"type":"node","id":1,"lat":43.8,"lon":15.6,"tags":{"barrier":"gate","access":"yes"}},
          {"type":"node","id":2,"lat":43.8,"lon":15.601},
          {"type":"way","id":10,"nodes":[1,2],"tags":{"highway":"cycleway","oneway":"yes"}}
        ]}"""))
        assertTrue(g.route(Point(43.8, 15.6), Point(43.8, 15.601)).meters > 0)
        try {
            g.route(Point(43.8, 15.601), Point(43.8, 15.6))
            fail("Wrong-way trip must fail")
        } catch (_: RoutingException) { }
    }

    @Test fun lockedGateClosesRoad() {
        val g = BikeGraph.compile(JSONObject("""{"elements":[
          {"type":"node","id":1,"lat":43.8,"lon":15.6,"tags":{"barrier":"gate","access":"yes","locked":"yes"}},
          {"type":"node","id":2,"lat":43.8,"lon":15.601},
          {"type":"way","id":10,"nodes":[1,2],"tags":{"highway":"cycleway"}}
        ]}"""))
        assertTrue(g.edges.isEmpty())
    }

    @Test fun bicycleTurnRestrictionIsEnforced() {
        val g = graph(""",
          {"type":"way","id":10,"nodes":[1,2],"tags":{"highway":"cycleway"}},
          {"type":"way","id":20,"nodes":[2,3],"tags":{"highway":"cycleway"}},
          {"type":"way","id":30,"nodes":[2,4,5,3],"tags":{"highway":"cycleway"}}""",
          """,{"type":"relation","id":100,"tags":{"type":"restriction","restriction:bicycle":"no_right_turn"},
             "members":[{"type":"way","role":"from","ref":10},{"type":"node","role":"via","ref":2},
                        {"type":"way","role":"to","ref":20}]}""")
        val route = g.route(Point(45.8, 15.9), Point(45.8, 15.902))
        assertTrue(route.points.contains(Point(45.801, 15.901)))
    }

    @Test fun noUTurnAllowsContinuingAlongSameWay() {
        val g = graph(""",
          {"type":"way","id":10,"nodes":[1,2,3],"tags":{"highway":"cycleway"}}""",
          """,{"type":"relation","id":101,"tags":{"type":"restriction","restriction:bicycle":"no_u_turn"},
             "members":[{"type":"way","role":"from","ref":10},{"type":"node","role":"via","ref":2},
                        {"type":"way","role":"to","ref":10}]}""")
        assertTrue(g.route(Point(45.8, 15.9), Point(45.8, 15.902)).meters > 0)
    }

    @Test fun realTisnoBridgeFixtureCrossesBothPermittedGates() {
        val input = javaClass.classLoader!!.getResourceAsStream("tisno_bridge_osm.json")!!
            .bufferedReader().use { it.readText() }
        val g = BikeGraph.compile(JSONObject(input))
        val ids = listOf(272268068L, 275001050L)
        assertTrue(g.nodes.containsKey(ids[0]))
        assertTrue(g.nodes.containsKey(ids[1]))
        val from = g.nodes[ids[0]]!!
        val to = g.nodes[ids[1]]!!
        assertTrue(g.route(from, to).meters > 0)
        assertTrue(g.route(to, from).meters > 0)
    }

    @Test fun shortTripOnSameOneWayEdgeIsNotZeroLength() {
        val g = BikeGraph.compile(JSONObject("""{"elements":[
          {"type":"node","id":1,"lat":49.0,"lon":8.0},
          {"type":"node","id":2,"lat":49.0,"lon":8.001},
          {"type":"way","id":10,"nodes":[1,2],"tags":{"highway":"cycleway","oneway":"yes","surface":"asphalt"}}
        ]}"""))
        val from = Point(49.0, 8.0001)
        val to = Point(49.0, 8.0002)
        val route = g.route(from, to)
        assertTrue(route.meters > 5)
        assertEquals(from, route.points.first())
        assertEquals(to, route.points.last())
        try { g.route(to, from); fail("Against one-way") } catch (_: RoutingException) { }
    }
}
