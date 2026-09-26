import Foundation

public struct VibeKeyDeviceInfo: Equatable {
    public static let vendorID: UInt16 = 0xFFF1
    public static let productID: UInt16 = 0x00DD
    public static let usagePage: UInt16 = 0xFFFC
    public static let usage: UInt16 = 0x0001
    public static let reportID: UInt8 = 0x55
}

/// 32-round Tiny Encryption Algorithm (TEA) codec for Ulanzi AU05.
public enum TEACodec {
    public static let delta: UInt32 = 0x9E3779B9
    public static let key: [UInt32] = [
        0xCAA5BACA,
        0xBC2A8A6D,
        0xCA5A9EBA,
        0x9BB88BCA
    ]

    public static func encryptBlock(_ block: inout (UInt32, UInt32)) {
        var v0 = block.0
        var v1 = block.1
        var sum: UInt32 = 0

        for _ in 0..<32 {
            sum = sum &+ delta
            v0 = v0 &+ (((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1]))
            v1 = v1 &+ (((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3]))
        }

        block = (v0, v1)
    }

    public static func decryptBlock(_ block: inout (UInt32, UInt32)) {
        var v0 = block.0
        var v1 = block.1
        var sum: UInt32 = 0xC6EF3720

        for _ in 0..<32 {
            v1 = v1 &- (((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3]))
            v0 = v0 &- (((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1]))
            sum = sum &- delta
        }

        block = (v0, v1)
    }
}
