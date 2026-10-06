import XCTest
@testable import BikeNaviCore

final class PlusCodeTests: XCTestCase {
    func testRodgauShortCodeAndEquivalentFullCode() throws {
        let short = try XCTUnwrap(PlusCode("  2wf2 + 8f   Rodgau  "))
        XCTAssertEqual(short.locality, "Rodgau")
        XCTAssertTrue(short.isShort)
        XCTAssertNil(short.coordinate())
        let coordinate = try XCTUnwrap(short.coordinate(near: Coordinate(latitude: 50.026, longitude: 8.885)))
        // Expected center independently calculated with Google's open-location-code reference implementation.
        XCTAssertEqual(coordinate.latitude, 50.0233125, accuracy: 1e-10)
        XCTAssertEqual(coordinate.longitude, 8.9011875, accuracy: 1e-10)
        XCTAssertEqual(PlusCode("9F2C2WF2+8F")?.coordinate(), coordinate)
    }

    func testLocalityIsSearchedInsteadOfCodeAndAllCandidatesRemainSelectable() async throws {
        let code = try XCTUnwrap(PlusCode("2WF2+8F Rodgau"))
        let places = try await code.places { query in
            XCTAssertEqual(query, "Rodgau")
            return [Waypoint(name: "Rodgau, Hessen", coordinate: Coordinate(latitude: 50.026, longitude: 8.885)),
                    Waypoint(name: "Weiterer Ort", coordinate: Coordinate(latitude: 51, longitude: 9))]
        }
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[0].name, "2WF2+8F · Rodgau, Hessen")
        XCTAssertEqual(places[0].coordinate.latitude, 50.0233125, accuracy: 1e-10)
        let full = try XCTUnwrap(PlusCode("9F2C2WF2+8F"))
        let offline = try await full.places { _ in XCTFail("Full codes must not search online"); return [] }
        XCTAssertEqual(offline.count, 1)
    }

    func testReferenceVectorsForPolesPaddingAndPrecisionGrid() throws {
        // Centers generated independently with Google's Python reference implementation.
        let vectors: [(String, Double, Double)] = [
            ("6F000000+", 0.0, 10.0),
            ("6FG20000+", 0.5, 0.5),
            ("6FG22200+", 0.025, 0.025),
            ("6FG22222+", 0.00125, 0.00125),
            ("6FG22222+22", 6.25e-05, 6.25e-05),
            ("6FG22222+222", 1.25e-05, 1.5625e-05),
            ("6FG22222+2222222", 2e-08, 6.1035155e-08),
            ("CV000000+", 80.0, 170.0),
            ("CVXX0000+", 89.5, 179.5),
            ("CVXXXX00+", 89.975, 179.975),
            ("CVXXXXXX+", 89.99875, 179.99875),
            ("CVXXXXXX+XX", 89.9999375, 179.9999375),
            ("CVXXXXXX+XX6", 89.9999125, 179.999890625),
            ("CVXXXXXX+XX65252", 89.99990002, 179.99989996337888),
            ("22000000+", -80.0, -170.0),
            ("22220000+", -89.5, -179.5),
            ("22222200+", -89.975, -179.975),
            ("22222222+", -89.99875, -179.99875),
            ("22222222+22", -89.9999375, -179.9999375),
            ("22222222+22X", -89.9998875, -179.999890625),
            ("22222222+22X2525", -89.99989998, -179.99989996337894),
            ("9F000000+", 60.0, 10.0),
            ("9F2C0000+", 50.5, 8.5),
            ("9F2C2V00+", 50.025, 8.875),
            ("9F2C2VGP+", 50.026250000000005, 8.88625),
            ("9F2C2VGP+C2", 50.0260625, 8.8850625),
            ("9F2C2VGP+C22", 50.0260125, 8.885015625000001),
            ("9F2C2VGP+C222222", 50.026000020000005, 8.885000061035154),
            ("4R000000+", -40.0, 150.0),
            ("4RRH0000+", -33.5, 151.5),
            ("4RRH4600+", -33.875, 151.225),
            ("4RRH46R2+", -33.85875, 151.20125),
            ("4RRH46R2+22", -33.8599375, 151.2000625),
            ("4RRH46R2+222", -33.8599875, 151.200015625),
            ("4RRH46R2+2222222", -33.85999998, 151.20000006103515)
        ]
        for (code, latitude, longitude) in vectors {
            let coordinate = try XCTUnwrap(PlusCode(code)?.coordinate(), code)
            XCTAssertEqual(coordinate.latitude, latitude, accuracy: 1e-10, code)
            XCTAssertEqual(coordinate.longitude, longitude, accuracy: 1e-10, code)
        }
    }

    func testRecoveryAcrossCellBoundaries() throws {
        let vectors: [(String, Double, Double, Double, Double)] = [
            ("2WF2+8F", 49.999, 8.999, 50.0233125, 8.9011875),
            ("F2+8F", 50.023, 8.899, 50.0233125, 8.9011875),
            ("2WF2+8F", 50.5, 8.3, 50.0233125, 7.9011875),
            ("XXXX+XX", 89.99, 179.99, 89.9999375, 179.9999375),
            ("2222+22", -89.99, -179.99, -89.9999375, -179.9999375)
        ]
        for (code, refLat, refLon, latitude, longitude) in vectors {
            let coordinate = try XCTUnwrap(PlusCode(code)?.coordinate(near: Coordinate(latitude: refLat, longitude: refLon)))
            XCTAssertEqual(coordinate.latitude, latitude, accuracy: 1e-10, code)
            XCTAssertEqual(coordinate.longitude, longitude, accuracy: 1e-10, code)
        }
    }

    func testInvalidCodesAndPadding() {
        for input in ["2WF2+8", "2WF+8F", "ZZZZZZZZ+ZZ", "9F2C2WF2++8F", "9F2C0WF2+8F", "2W00+", "FF2C2WF2+8F"] {
            XCTAssertNil(PlusCode(input), input)
        }
        XCTAssertNotNil(PlusCode("9F000000+")?.coordinate())
        XCTAssertNotNil(PlusCode("9F2C2WF2+8FX")?.coordinate())
    }
}
