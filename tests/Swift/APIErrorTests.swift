import Foundation
import XCTest
@testable import BikeNaviCore

final class APIErrorTests: XCTestCase {
    func testOldPiValidationExplainsMissingCarMode() throws {
        let response = try XCTUnwrap("""
        {"detail":[{"type":"literal_error","loc":["body","profile","travelMode"],"msg":"Input should be 'cycling', 'bikeAndHike', 'hiking' or 'sea'","input":"car"}]}
        """.data(using: .utf8))
        XCTAssertEqual(APIError.message(status: 422, body: response),
                       "Der Pi kennt den Auto-Modus noch nicht. Bitte das Backend aktualisieren.")
    }

    func testServerDetailAndOtherValidationRemainVisible() throws {
        let detail = try XCTUnwrap("{\"detail\":\"Kein Straßenanschluss.\"}".data(using: .utf8))
        XCTAssertEqual(APIError.message(status: 422, body: detail), "Kein Straßenanschluss.")
        let validation = try XCTUnwrap("""
        {"detail":[{"loc":["body","waypoints"],"msg":"Too few points"}]}
        """.data(using: .utf8))
        XCTAssertEqual(APIError.message(status: 422, body: validation),
                       "Der Server hat die Anfrage abgelehnt: Too few points")
    }
}
