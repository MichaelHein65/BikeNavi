import XCTest
@testable import BikeNaviCore

final class CoordinateParserTests: XCTestCase {
    func testCommonFormatsAndCopyArtifacts() {
        let inputs = ["49.4; 8.7", "49,4;8,7", "49.4, 8.7", "49,4 8,7", "49,4,8,7",
                      "49 . 4 ; 8 , 7", "(49.4,8.7)", "geo:49.4,8.7", "49.4\n8.7",
                      "49:24:00N 8:42:00E", "49°24′ N 8°42′ O", "N49 24 E8 42", "49°24'0\"N 8°42'0\"E",
                      "8.7E 49.4N", "49.4 N / 8.7 E", "49.4\u{00a0};\u{202f}8.7",
                      "49° 24,0′ N; 8° 42,0′ E"]
        for input in inputs {
            guard case .coordinate(let coordinate) = CoordinateParser.parse(input) else {
                XCTFail("Not recognized: \(input): \(CoordinateParser.parse(input))"); continue
            }
            XCTAssertEqual(coordinate.latitude, 49.4, accuracy: 1e-9, input)
            XCTAssertEqual(coordinate.longitude, 8.7, accuracy: 1e-9, input)
        }
    }

    func testUserProvidedNorthEastCoordinate() {
        for input in ["43.80104 N, 15.78955 E", "43,80104 N, 15,78955 E",
                      " 43.80104  N ,  15.78955 E ", "43,80104 N; 15,78955 O",
                      "N 43.80104 E 15.78955"] {
            XCTAssertEqual(CoordinateParser.parse(input),
                           .coordinate(Coordinate(latitude: 43.80104, longitude: 15.78955)), input)
        }
    }

    func testSignsAndBounds() {
        for input in ["−49,4;−8,7", "49.4S 8.7W", "S49.4 W8.7", "-49.4S -8.7W"] {
            XCTAssertEqual(CoordinateParser.parse(input), .coordinate(Coordinate(latitude: -49.4, longitude: -8.7)), input)
        }
        XCTAssertEqual(CoordinateParser.parse("90;180"), .coordinate(Coordinate(latitude: 90, longitude: 180)))
        XCTAssertEqual(CoordinateParser.parse("0;0"), .coordinate(Coordinate(latitude: 0, longitude: 0)))
    }

    func testInvalidAndAmbiguousInputsDoNotProduceAWrongPlace() {
        for input in ["91;8", "49;181", "49°60'N 8°42'E", "49°24'60\"N 8°42'E", "-49N;8E", "+49S;8E", "49N;8N", "49.5°24'N;8E", "49..4;8.7", "4940;870", "49;8;7"] {
            XCTAssertEqual(CoordinateParser.parse(input), .invalid, input)
        }
        XCTAssertEqual(CoordinateParser.parse("49 24 8 42"), .ambiguous)
        for input in ["Heidelberg", "Hauptstraße 49", "Café 8", "", "69117 Heidelberg", "69117"] {
            XCTAssertEqual(CoordinateParser.parse(input), .notCoordinate, input)
        }
    }
}
