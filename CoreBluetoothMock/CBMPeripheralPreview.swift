/*
* Copyright (c) 2020, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation
import CoreBluetooth

/// A stub ``CBMPeripheral`` implementation designed only for SwiftUI Previews.
///
/// The `CBMPeripheralPreview` object has very limited functionality. The implementation
/// handles connection but all request methods just call corresponding delegate method.
///
/// All ``CBMService``s are available immediately, without the need for service discovery.
/// Bluetooth LE operations are NO OP. The device does not need to be scanned to
/// be retrievable by any ``CBMCentralManagerMock`` instance.
@objc open class CBMPeripheralPreview: NSObject, CBMPeripheral {
    private let mock: CBMPeripheralSpec
    
    public let identifier: UUID
    open var name: String? {
        mock.name
    }
    public var services: [CBMService]?
    
    public var delegate: CBMPeripheralDelegate?
    @objc dynamic public internal(set) var state: CBMPeripheralState
    
    public let canSendWriteWithoutResponse: Bool = true
    public let ancsAuthorized: Bool = false
    
    /// Creates the preview ``CBMPeripheral``.
    /// - Parameters:
    ///   - mock: The mock peripheral to base the preview on.
    ///   - state: The state to return from ``CBMPeripheral/state``.
    public init(_ mock: CBMPeripheralSpec,
                state: CBMPeripheralState = .disconnected) {
        self.mock = mock
        self.identifier = mock.identifier
        self.state = state
        super.init()
        self.services = mock.services?.map { CBMService(copy: $0, for: self) }
        CBMCentralManagerMock.registerForPreviews(self)
    }
    
    open func readRSSI() {
        delegate?.peripheral(self, didReadRSSI: mock.proximity.RSSI as NSNumber, error: nil)
    }
    
    open func discoverServices(_ serviceUUIDs: [CBMUUID]?) {
        delegate?.peripheral(self, didDiscoverServices: nil)
    }
    
    open func discoverIncludedServices(_ includedServiceUUIDs: [CBMUUID]?, for service: CBMService) {
        delegate?.peripheral(self, didDiscoverIncludedServicesFor: service, error: nil)
    }
    
    open func discoverCharacteristics(_ characteristicUUIDs: [CBMUUID]?, for service: CBMService) {
        delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: nil)
    }
    
    open func discoverDescriptors(for characteristic: CBMCharacteristic) {
        delegate?.peripheral(self, didDiscoverDescriptorsFor: characteristic, error: nil)
    }
    
    open func readValue(for characteristic: CBMCharacteristic) {
        delegate?.peripheral(self, didUpdateValueFor: characteristic, error: nil)
    }
    
    open func readValue(for descriptor: CBMDescriptor) {
        delegate?.peripheral(self, didUpdateValueFor: descriptor, error: nil)
    }
    
    open func maximumWriteValueLength(for type: CBMCharacteristicWriteType) -> Int {
        return (mock.mtu ?? 23) - 3
    }
    
    open func writeValue(_ data: Data, for characteristic: CBMCharacteristic,
                           type: CBMCharacteristicWriteType) {
        if type == .withResponse {
            delegate?.peripheral(self, didWriteValueFor: characteristic, error: nil)
        }
    }
    
    open func writeValue(_ data: Data, for descriptor: CBMDescriptor) {
        delegate?.peripheral(self, didWriteValueFor: descriptor, error: nil)
    }
    
    open func setNotifyValue(_ enabled: Bool, for characteristic: CBMCharacteristic) {
        delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic, error: nil)
    }
    
    open func openL2CAPChannel(_ PSM: CBML2CAPPSM) {
        fatalError("Not available")
    }
    
    #if !os(macOS)
    @available(iOS 27.0, *)
    open func startChannelSoundingSession(_ config: CBMChannelSoundingSessionConfiguration) {
        fatalError("Not available")
    }
    
    @available(iOS 27.0, *)
    open func cancelChannelSoundingSession() {
        fatalError("Not available")
    }
    #endif
}
/*
extension CBMPeripheralPreview: Hashable {
    
    public static func == (lhs: CBMPeripheralPreview, rhs: CBMPeripheralPreview) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    
}
*/
