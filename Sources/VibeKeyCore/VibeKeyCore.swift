import Foundation

public struct VibeKeyDeviceInfo: Equatable, Sendable {
    public static let vendorID: UInt16 = 0xFFF1
    public static let productID: UInt16 = 0x00DD
    public static let usagePage: UInt16 = 0xFFFC
    public static let usage: UInt16 = 0x0001
    public static let reportID: UInt8 = 0x55
    public static let packetLength = 64
}

public enum TEACodecError: Error, Equatable, LocalizedError {
    case invalidPlaintextLength(actual: Int)
    case invalidCiphertextLength(actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidPlaintextLength(actual):
            return "Plaintext length must be a multiple of 8 (or exactly 64), got \(actual)."
        case let .invalidCiphertextLength(actual):
            return "Ciphertext length must be a multiple of 8, got \(actual)."
        }
    }
}

/// Pure-Swift 32-round Tiny Encryption Algorithm (TEA) codec for Ulanzi AU05.
public enum TEACodec {
    public static let delta: UInt32 = 0x9E3779B9
    public static let key: [UInt32] = [
        0xCAA5BACA,
        0xBC2A8A6D,
        0xCA5A9EBA,
        0x9BB88BCA
    ]

    public static func encrypt(_ plaintext: [UInt8]) throws -> [UInt8] {
        guard !plaintext.isEmpty && plaintext.count.isMultiple(of: 8) else {
            throw TEACodecError.invalidPlaintextLength(actual: plaintext.count)
        }

        var encrypted = [UInt8]()
        encrypted.reserveCapacity(plaintext.count)

        for offset in stride(from: 0, to: plaintext.count, by: 8) {
            var left = readLittleEndianWord(plaintext, offset: offset)
            var right = readLittleEndianWord(plaintext, offset: offset + 4)
            var sum: UInt32 = 0

            for _ in 0..<32 {
                sum = sum &+ delta
                left = left &+ (
                    ((right << 4) &+ key[0])
                        ^ (right &+ sum)
                        ^ ((right >> 5) &+ key[1])
                )
                right = right &+ (
                    ((left << 4) &+ key[2])
                        ^ (left &+ sum)
                        ^ ((left >> 5) &+ key[3])
                )
            }

            appendLittleEndianWord(left, to: &encrypted)
            appendLittleEndianWord(right, to: &encrypted)
        }

        return encrypted
    }

    public static func decrypt(_ ciphertext: [UInt8]) throws -> [UInt8] {
        guard !ciphertext.isEmpty && ciphertext.count.isMultiple(of: 8) else {
            throw TEACodecError.invalidCiphertextLength(actual: ciphertext.count)
        }

        var plaintext = [UInt8]()
        plaintext.reserveCapacity(ciphertext.count)

        for offset in stride(from: 0, to: ciphertext.count, by: 8) {
            var left = readLittleEndianWord(ciphertext, offset: offset)
            var right = readLittleEndianWord(ciphertext, offset: offset + 4)
            var sum: UInt32 = 0xC6EF3720

            for _ in 0..<32 {
                right = right &- (
                    ((left << 4) &+ key[2])
                        ^ (left &+ sum)
                        ^ ((left >> 5) &+ key[3])
                )
                left = left &- (
                    ((right << 4) &+ key[0])
                        ^ (right &+ sum)
                        ^ ((right >> 5) &+ key[1])
                )
                sum = sum &- delta
            }

            appendLittleEndianWord(left, to: &plaintext)
            appendLittleEndianWord(right, to: &plaintext)
        }

        return plaintext
    }

    /// Builds a 64-byte HID output report: [0x55] + encryptedPlaintext[0..62].
    /// Note: The hardware report descriptor specifies a 63-byte output payload.
    /// All critical control fields reside well within the first 56 bytes (7 complete TEA blocks).
    public static func buildOutputReport(encrypting plaintext: [UInt8]) throws -> [UInt8] {
        var normalized = plaintext
        if normalized.count < VibeKeyDeviceInfo.packetLength {
            normalized.append(contentsOf: [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength - normalized.count))
        }
        let ciphertext = try encrypt(normalized)
        return [VibeKeyDeviceInfo.reportID] + ciphertext.prefix(VibeKeyDeviceInfo.packetLength - 1)
    }

    /// Decrypts an input report.
    /// When report length is not a multiple of 8 and starts with 0x55, strips the report ID.
    /// If hasReportID is explicitly provided, follows that flag to prevent 0x55 collision.
    public static func decryptInputReport(_ report: [UInt8], hasReportID: Bool? = nil) throws -> [UInt8] {
        let shouldDropFirst: Bool
        if let explicit = hasReportID {
            shouldDropFirst = explicit
        } else {
            // If the count is 64 and first is 0x55, or count is not divisible by 8, strip 0x55
            shouldDropFirst = (report.count == 64 && report.first == VibeKeyDeviceInfo.reportID)
                || (!report.count.isMultiple(of: 8) && report.first == VibeKeyDeviceInfo.reportID)
        }

        let payload = shouldDropFirst ? Array(report.dropFirst()) : report
        let blockCount = payload.count / 8
        guard blockCount > 0 else {
            throw TEACodecError.invalidCiphertextLength(actual: payload.count)
        }
        let bytesToDecrypt = Array(payload.prefix(blockCount * 8))
        return try decrypt(bytesToDecrypt)
    }

    private static func readLittleEndianWord(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func appendLittleEndianWord(_ word: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: word))
        bytes.append(UInt8(truncatingIfNeeded: word >> 8))
        bytes.append(UInt8(truncatingIfNeeded: word >> 16))
        bytes.append(UInt8(truncatingIfNeeded: word >> 24))
    }
}
