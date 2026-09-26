import Foundation
import VibeKeyCore

print("VibeKey Elements CLI v0.1.0")
print("Target device: VID 0x\(String(VibeKeyDeviceInfo.vendorID, radix: 16, uppercase: true)), PID 0x\(String(VibeKeyDeviceInfo.productID, radix: 16, uppercase: true))")
