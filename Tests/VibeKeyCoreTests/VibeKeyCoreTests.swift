import XCTest
@testable import VibeKeyCore

final class VibeKeyCoreTests: XCTestCase {
    func testTEAEncryptionAndDecryption() {
        let v0: UInt32 = 0x01500601
        let v1: UInt32 = 0x00000000

        var block = (v0, v1)
        TEACodec.encryptBlock(&block)
        
        // Decrypt back
        TEACodec.decryptBlock(&block)
        XCTAssertEqual(block.0, v0)
        XCTAssertEqual(block.1, v1)
    }
}
