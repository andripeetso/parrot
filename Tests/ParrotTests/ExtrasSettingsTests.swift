import XCTest
@testable import ParrotCore

final class ExtrasSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> ExtrasSettings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).extras
    }

    func testDefaultsHaveNoServer() throws {
        let extras = try decode("{}")
        XCTAssertNil(extras.serverURL)
        XCTAssertEqual(extras.keepRecordings, 10)
        XCTAssertEqual(extras.historyKey, .f14)
        XCTAssertEqual(extras.fileDropKey, .f15)
    }

    func testServerAndUnknownKey() throws {
        let extras = try decode(#"{"extras":{"server":"http://192.168.8.237:7886/api/transcribe","historyKey":"f99","fileDropKey":"off"}}"#)
        XCTAssertEqual(extras.serverURL?.host, "192.168.8.237")
        XCTAssertEqual(extras.historyKey, .f14)
        XCTAssertNil(extras.fileDropKey.keycode)
        XCTAssertNil(try decode(#"{"extras":{"server":"not a url"}}"#).serverURL)
    }
}
