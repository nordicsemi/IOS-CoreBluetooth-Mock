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

import CoreBluetooth

/// An implementation  of ``CBMCentralManager`` that will proxy all the requests and responses
/// to the native `CBCentralManager` object.
///
/// This manager can only interact with physical Bluetooth LE devices.
public class CBMCentralManagerNative: CBMCentralManager {
    var observation: NSKeyValueObservation?
    @objc dynamic private var manager: CBCentralManager!
    private var wrapper: CBCentralManagerDelegate!
    private var peripherals = CBMDictionary<UUID, CBMPeripheralNative>()
    
    private class CBMCentralManagerDelegateWrapper: NSObject, CBCentralManagerDelegate {
        fileprivate weak var manager: CBMCentralManagerNative! // weak to avoid cyclic reference (#9)
        
        init(_ manager: CBMCentralManagerNative) {
            self.manager = manager
        }
        
        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            manager.delegate?.centralManagerDidUpdateState(manager)
        }
        
        // This methods is moved to a separate class below. Otherwise a warning
        // is generated when setting delegate to the CBCentralManager when
        // restoration was not enabled:
        // ----
        // API MISUSE: <CBCentralManager: ...> has no restore identifier but the
        // delegate implements the centralManager:willRestoreState: method.
        // Restoring will not be supported
        // ----
        //
        // func centralManager(_ central: CBCentralManager,
        //                     willRestoreState dict: [String : Any]) {
        //     manager.delegate?.centralManager(manager, willRestoreState: dict)
        // }
        
        func centralManager(_ central: CBCentralManager,
                            didDiscover peripheral: CBPeripheral,
                            advertisementData: [String : Any],
                            rssi RSSI: NSNumber) {
            manager.delegate?.centralManager(manager,
                                             didDiscover: getPeripheral(peripheral),
                                             advertisementData: advertisementData,
                                             rssi: RSSI)
        }
        
        func centralManager(_ central: CBCentralManager,
                            didConnect peripheral: CBPeripheral) {
            manager.delegate?.centralManager(manager,
                                             didConnect: getPeripheral(peripheral))
        }
        
        func centralManager(_ central: CBCentralManager,
                            didFailToConnect peripheral: CBPeripheral,
                            error: Error?) {
            manager.delegate?.centralManager(manager,
                                             didFailToConnect: getPeripheral(peripheral),
                                             error: error)
        }
        
        // When this method is implemented, the other variant with
        // timestamp and isReconnecting flag isn't. However, the latter one
        // was added in iOS 17, so we need to selecrt the implementation
        // based on the OS version. Check out below.
        
        // func centralManager(_ central: CBCentralManager,
        //                     didDisconnectPeripheral peripheral: CBPeripheral,
        //                     error: Error?) {
        //     let p = getPeripheral(peripheral)
        //     p.mockServices = nil
        //     manager.delegate?.centralManager(manager,
        //                                      didDisconnectPeripheral: p,
        //                                      error: error)
        // }
        
        #if !os(macOS)
        @available(iOS 13.0, *)
        func centralManager(_ central: CBCentralManager,
                            didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
            manager.delegate?.centralManager(manager,
                                             didUpdateANCSAuthorizationFor: getPeripheral(peripheral))
        }
        #endif
        
        #if !os(macOS)
        @available(iOS 13.0, *)
        func centralManager(_ central: CBCentralManager,
                            connectionEventDidOccur event: CBConnectionEvent,
                            for peripheral: CBPeripheral) {
            manager.delegate?.centralManager(manager,
                                             connectionEventDidOccur: event,
                                             for: getPeripheral(peripheral))
        }
        #endif
        
        fileprivate func getPeripheral(_ peripheral: CBPeripheral) -> CBMPeripheralNative {
            guard let cachedPeripheral = manager.peripherals[peripheral.identifier] else {
                return newPeripheral(peripheral)
            }

            // CBPeripheral may be a different instance with the same identifier
            guard cachedPeripheral.peripheral === peripheral else {
                return newPeripheral(peripheral)
            }

            return cachedPeripheral
        }
        
        private func newPeripheral(_ peripheral: CBPeripheral) -> CBMPeripheralNative {
            let p = CBMPeripheralNative(peripheral)
            manager.peripherals[peripheral.identifier] = p
            return p
        }
    }
    
    private class CBMCentralManagerDelegateWrapperIOS12: CBMCentralManagerDelegateWrapper {
        
        override init(_ manager: CBMCentralManagerNative) {
            super.init(manager)
        }
        
        func centralManager(_ central: CBCentralManager,
                            didDisconnectPeripheral peripheral: CBPeripheral,
                            error: Error?) {
            let p = getPeripheral(peripheral)
            p.mockServices = nil
            // Call only the "new" method with timestamp and isReconnecting.
            // If that is not implemented in the delegate, the default
            // implementation will call the old one.
            manager.delegate?.centralManager(manager,
                                             didDisconnectPeripheral: p,
                                             timestamp: CFAbsoluteTimeGetCurrent(),
                                             isReconnecting: false,
                                             error: error)
        }
    }
    
    private class CBMCentralManagerDelegateWrapperIOS17: CBMCentralManagerDelegateWrapper {
        
        override init(_ manager: CBMCentralManagerNative) {
            super.init(manager)
        }
        
        func centralManager(_ central: CBCentralManager,
                            didDisconnectPeripheral peripheral: CBPeripheral,
                            timestamp: CFAbsoluteTime,
                            isReconnecting: Bool,
                            error: (any Error)?) {
            let p = getPeripheral(peripheral)
            p.mockServices = nil
            
            manager.delegate?.centralManager(manager,
                                             didDisconnectPeripheral: p,
                                             timestamp: timestamp,
                                             isReconnecting: isReconnecting,
                                             error: error)
        }
    }
    
    private class CBMCentralManagerDelegateWrapperIOS12WithRestoration:
        CBMCentralManagerDelegateWrapperIOS12 {
        
        override init(_ manager: CBMCentralManagerNative) {
            super.init(manager)
        }
        
        func centralManager(_ central: CBCentralManager,
                            willRestoreState dict: [String : Any]) {
            var state = dict
            
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                state[CBMCentralManagerRestoredStatePeripheralsKey] = peripherals.map {
                    CBMPeripheralNative($0)
                }
            }
                        
            manager.delegate?.centralManager(manager, willRestoreState: state)
        }
    }
    
    private class CBMCentralManagerDelegateWrapperIOS17WithRestoration:
        CBMCentralManagerDelegateWrapperIOS17 {
        
        override init(_ manager: CBMCentralManagerNative) {
            super.init(manager)
        }
        
        func centralManager(_ central: CBCentralManager,
                            willRestoreState dict: [String : Any]) {
            var state = dict
            
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                let nativePeripherals = peripherals.map { CBMPeripheralNative($0) }
                state[CBMCentralManagerRestoredStatePeripheralsKey] = nativePeripherals
                nativePeripherals.forEach { peripheral in
                    manager.peripherals[peripheral.identifier] = peripheral
                }
            }
                        
            manager.delegate?.centralManager(manager, willRestoreState: state)
        }
    }
    
    public override var state: CBMManagerState {
        return CBMManagerState(rawValue: manager.state.rawValue) ?? .unknown
    }
    
    @available(iOS 9.0, *)
    public override var isScanning: Bool {
        get {
            manager.isScanning
        }
        set {
            
        }
    }
    
    @available(iOS, introduced: 13.0, deprecated: 13.1)
    @available(macOS, introduced: 10.15)
    @available(tvOS, introduced: 13.0, deprecated: 13.1)
    @available(watchOS, introduced: 6.0, deprecated: 6.1)
    public override var authorization: CBMManagerAuthorization {
        return manager.authorization
    }
    
    @available(iOS 13.1, macOS 10.15, tvOS 13.1, watchOS 6.1, *)
    public override class var authorization: CBMManagerAuthorization {
        return CBCentralManager.authorization
    }
    
    #if !os(macOS)
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public override class func supports(_ features: CBMCentralManager.Feature) -> Bool {
        return CBCentralManager.supports(features)
    }
    #endif
    
    public convenience init() {
        self.init(delegate: nil, queue: nil, options: nil)
    }
    
    public convenience init(delegate: CBMCentralManagerDelegate?,
                            queue: DispatchQueue?) {
        self.init(delegate: delegate, queue: queue, options: nil)
    }
    
    @available(iOS 7.0, *)
    public init(delegate: CBMCentralManagerDelegate?,
                queue: DispatchQueue?,
                options: [String : Any]?) {
        super.init(true)
        
        // CBConnectPeripheralOptionEnableAutoReconnect is available from iOS 17.0.
        var iOS17 = false
        if #available(iOS 17.0, *) {
            iOS17 = true
        }
        
        // State restoration is enabled using CBMCentralManagerOptionRestoreIdentifierKey option.
        let restoration = options?[CBMCentralManagerOptionRestoreIdentifierKey] != nil
       
        if iOS17 {
            self.wrapper = restoration ?
                CBMCentralManagerDelegateWrapperIOS17WithRestoration(self) :
                CBMCentralManagerDelegateWrapperIOS17(self)
        } else {
            self.wrapper = restoration ?
                CBMCentralManagerDelegateWrapperIOS12WithRestoration(self) :
                CBMCentralManagerDelegateWrapperIOS12(self)
        }
        self.manager = CBCentralManager(delegate: wrapper, queue: queue, options: options)
        self.delegate = delegate
        
        self.addManagerObserver()
    }
    
    public override func scanForPeripherals(withServices serviceUUIDs: [CBMUUID]?,
                                            options: [String : Any]? = nil) {
        manager.scanForPeripherals(withServices: serviceUUIDs, options: options)
    }
    
    public override func stopScan() {
        manager.stopScan()
    }
    
    public override func connect(_ peripheral: CBMPeripheral, options: [String : Any]?) {
        if let peripheral = peripherals[peripheral.identifier] {
            manager.connect(peripheral.peripheral, options: options)
        }
    }
    
    public override func cancelPeripheralConnection(_ peripheral: CBMPeripheral) {
        if let peripheral = peripherals[peripheral.identifier] {
            manager.cancelPeripheralConnection(peripheral.peripheral)
        }
    }
    
    @available(iOS 7.0, *)
    public override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBMPeripheral] {
        let retrievedPeripherals = manager.retrievePeripherals(withIdentifiers: identifiers)
        retrievedPeripherals
            .forEach { peripherals[$0.identifier] = CBMPeripheralNative($0) }
        return peripherals
            .filter { identifiers.contains($0.key) }
            .map { $0.value }
    }
    
    @available(iOS 7.0, *)
    public override func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBMUUID]) -> [CBMPeripheral] {
        let retrievedPeripherals = manager.retrieveConnectedPeripherals(withServices: serviceUUIDs)
        retrievedPeripherals
            .forEach { peripherals[$0.identifier] = CBMPeripheralNative($0) }
        return peripherals
            .filter { entry in retrievedPeripherals.contains(where: { $0.identifier == entry.key }) }
            .map { $0.value }
    }
    
    #if !os(macOS)
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public override func registerForConnectionEvents(options: [CBMConnectionEventMatchingOption : Any]? = nil) {
        manager.registerForConnectionEvents(options: options)
    }
    #endif
    
    /// Add observer for `\.CBCentralManager.isScanning`  and change `Self.isScanning` correspondingly.
    private func addManagerObserver() {
        observation = observe(\.manager?.isScanning, options: [.old, .new]) { _, change in
            change.newValue?.flatMap { [weak self] new in
                self?.isScanning = new
            }
        }
    }
}

/// A native implementation of ``CBMPeripheral`` that will proxy all requests to an underlying `CBPeripheral`.
///
/// This implementation will be used when creating peripherals by ``CBMCentralManagerNative``.
///
/// Unless required, this class should not be accessed directly, but rather by the common protocol ``CBMPeripheral``.
public class CBMPeripheralNative: CBMPeer, CBMPeripheral {
    
    private class CBPeripheralDelegateWrapper: NSObject, CBPeripheralDelegate {
        private var impl: CBMPeripheralNative
        
        init(_ peripheral: CBMPeripheralNative) {
            self.impl = peripheral
        }
        
        func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
            impl.delegate?.peripheralDidUpdateName(impl)
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverServices error: Error?) {
            smartCopy(peripheral.services)
            impl.delegate?.peripheral(impl, didDiscoverServices: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverIncludedServicesFor service: CBService,
                        error: Error?) {
            smartCopy(peripheral.services)
            usingMock(of: service) { peripheral, delegate, service in
                delegate.peripheral(peripheral,
                                    didDiscoverIncludedServicesFor: service,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverCharacteristicsFor service: CBService,
                        error: Error?) {
            smartCopy(peripheral.services)
            usingMock(of: service) { peripheral, delegate, service in
                delegate.peripheral(peripheral,
                                    didDiscoverCharacteristicsFor: service,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
                        error: Error?) {
            smartCopy(peripheral.services)
            usingMock(of: characteristic) { peripheral, delegate, characteristic in
                delegate.peripheral(peripheral,
                                    didDiscoverDescriptorsFor: characteristic,
                                    error: error)
            }
        }

        @available(iOS 7.0, *)
        func peripheral(_ peripheral: CBPeripheral,
                        didModifyServices invalidatedServices: [CBService]) {
            var invalidatedServiceMocks: [CBMService] = []
            invalidatedServices.forEach { service in
                if let services = impl.mockServices,
                   let index = services
                    .firstIndex(where: { $0.service == service}) {
                    invalidatedServiceMocks.append(services[index])
                    impl.mockServices?.remove(at: index)
                }
            }
            impl.delegate?.peripheral(impl, didModifyServices: invalidatedServiceMocks)
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateNotificationStateFor characteristic: CBCharacteristic,
                        error: Error?) {
            usingMock(of: characteristic) { peripheral, delegate, mock in
                mock.isNotifying = characteristic.isNotifying
                delegate.peripheral(peripheral,
                                    didUpdateNotificationStateFor: mock,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didWriteValueFor characteristic: CBCharacteristic,
                        error: Error?) {
            usingMock(of: characteristic) { peripheral, delegate, characteristic in
                delegate.peripheral(peripheral,
                                    didWriteValueFor: characteristic,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didWriteValueFor descriptor: CBDescriptor,
                        error: Error?) {
            usingMock(of: descriptor) { peripheral, delegate, descriptor in
                delegate.peripheral(peripheral,
                                    didWriteValueFor: descriptor,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateValueFor characteristic: CBCharacteristic,
                        error: Error?) {
            usingMock(of: characteristic) { peripheral, delegate, mockCharacteristic in
                mockCharacteristic.value = characteristic.value
                delegate.peripheral(peripheral,
                                    didUpdateValueFor: mockCharacteristic,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateValueFor descriptor: CBDescriptor,
                        error: Error?) {
            usingMock(of: descriptor) { peripheral, delegate, mockDescriptor in
                mockDescriptor.value = descriptor.value
                delegate.peripheral(peripheral,
                                    didUpdateValueFor: mockDescriptor,
                                    error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didReadRSSI RSSI: NSNumber,
                        error: Error?) {
            impl.delegate?.peripheral(impl, didReadRSSI: RSSI, error: error)
        }

        func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
            if #available(iOS 11.0, tvOS 11.0, watchOS 4.0, *) {
                impl.delegate?.peripheralIsReady(toSendWriteWithoutResponse: impl)
            }
        }
        
        @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
        func peripheral(_ peripheral: CBPeripheral,
                        didOpen channel: CBL2CAPChannel?,
                        error: Error?) {
            impl.delegate?.peripheral(impl, didOpen: channel, error: error)
        }
        
        #if !os(macOS)
        @available(iOS 27.0, *)
        func peripheral(_ peripheral: CBPeripheral,
                        didReceive results: CBChannelSoundingProcedureResults?,
                        error: Error?) {
            impl.delegate?.peripheral(impl, didReceive: results, error: error)
        }
        
        @available(iOS 27.0, *)
        func peripheral(_ peripheral: CBPeripheral,
                        didCompleteChannelSoundingSession error: Error?) {
            impl.delegate?.peripheral(impl, didCompleteChannelSoundingSession: error)
        }
        #endif
        
        /// Updates the local list of services with received ones.
        /// - Parameter services: New list of services.
        private func smartCopy(_ services: [CBService]?) {
            guard let services = services, !services.isEmpty else {
                return
            }
            impl.mockServices = impl.mockServices ?? []
            for service in services {
                // Check if the service was already discovered.
                if let s = mock(of: service) {
                    s.update(service)
                } else {
                    // If not, create a new wrapper.
                    let mockService = CBMServiceNative(service, in: impl)
                    impl.mockServices?.append(mockService)
                }
            }
        }
        
        /// Returns the wrapper for the native `CBService`.
        /// - Parameter service: The native service.
        private func mock(of service: CBService?) -> CBMServiceNative? {
            return impl.mockServices?.first { $0.service == service }
        }
        
        /// Returns the wrapper for the native `CBCharacteristic`.
        /// - Parameter characteristic: The native characteristic.
        private func mock(of characteristic: CBCharacteristic?) -> CBMCharacteristicNative? {
            let service = mock(of: characteristic?.service)
            return (service?._characteristics as? [CBMCharacteristicNative])?
                .first { $0.characteristic == characteristic }
        }
        
        /// Returns the wrapper for the native `CBDescriptor`.
        /// - Parameter descriptor: The native descriptor.
        private func mock(of descriptor: CBDescriptor?) -> CBMDescriptorNative? {
            let characteristic = mock(of: descriptor?.characteristic)
            return (characteristic?._descriptors as? [CBMDescriptorNative])?
                .first { $0.descriptor == descriptor }
        }
        
        /// Calls the action with mock service.
        /// - Parameters:
        ///   - service: The native service.
        ///   - action: The action to perform on its mock.
        private func usingMock(of service: CBService?,
                               action: @escaping (CBMPeripheral, CBMPeripheralDelegate, CBMService) -> ()) {
            if let delegate = impl.delegate,
               let serviceMock = mock(of: service) {
                action(impl, delegate, serviceMock)
            }
        }
        
        /// Calls the action with mock characteristic.
        /// - Parameters:
        ///   - service: The native characteristic.
        ///   - action: The action to perform on its mock.
        private func usingMock(of characteristic: CBCharacteristic?,
                               action: @escaping (CBMPeripheral, CBMPeripheralDelegate, CBMCharacteristic) -> ()) {
            usingMock(of: characteristic?.service) { p, d, s in
                if let characteristicMock = self.mock(of: characteristic) {
                    action(p, d, characteristicMock)
                }
            }
        }
        
        /// Calls the action with mock descriptor.
        /// - Parameters:
        ///   - service: The native descriptor.
        ///   - action: The action to perform on its mock.
        private func usingMock(of descriptor: CBDescriptor?,
                               action: @escaping (CBMPeripheral, CBMPeripheralDelegate, CBMDescriptor) -> ()) {
            usingMock(of: descriptor?.characteristic) { p, d, c in
                if let descriptorMock = self.mock(of: descriptor) {
                    action(p, d, descriptorMock)
                }
            }
        }
    }
    
    private var wrapper: CBPeripheralDelegate?
    public weak var delegate: CBMPeripheralDelegate? {
        didSet {
            if let _ = delegate {
                // We need to hold a strong reference to the wrapper, otherwise
                // it would be immediately deallocated.
                wrapper = CBPeripheralDelegateWrapper(self)
                peripheral.delegate = wrapper
            } else {
                wrapper = nil
                peripheral.delegate = nil
            }
        }
    }
    
    /// The unique, persistent identifier associated with the peer.
    public override var identifier: UUID {
        return peripheral.identifier
    }
    
    public var name: String? {
        return peripheral.name
    }
    
    public var state: CBMPeripheralState {
        return peripheral.state
    }
    
    fileprivate var mockServices: [CBMServiceNative]?
    public var services: [CBMService]? {
        return mockServices
    }
    
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public var canSendWriteWithoutResponse: Bool {
        return peripheral.canSendWriteWithoutResponse
    }
    
    #if !os(macOS)
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public var ancsAuthorized: Bool {
        return peripheral.ancsAuthorized
    }
    #endif
    
    public let peripheral: CBPeripheral
    
    fileprivate init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
    
    public func readRSSI() {
        peripheral.readRSSI()
    }
    
    public func discoverServices(_ serviceUUIDs: [CBMUUID]?) {
        peripheral.discoverServices(serviceUUIDs)
    }
    
    public func discoverIncludedServices(_ includedServiceUUIDs: [CBMUUID]?,
                                         for service: CBMService) {
        if let n = service as? CBMServiceNative {
            peripheral.discoverIncludedServices(includedServiceUUIDs, for: n.service)
        }
    }
    
    public func discoverCharacteristics(_ characteristicUUIDs: [CBMUUID]?,
                                        for service: CBMService) {
        if let n = service as? CBMServiceNative {
            peripheral.discoverCharacteristics(characteristicUUIDs, for: n.service)
        }
    }
    
    public func discoverDescriptors(for characteristic: CBMCharacteristic) {
        if let n = characteristic as? CBMCharacteristicNative {
            peripheral.discoverDescriptors(for: n.characteristic)
        }
    }
    
    public func readValue(for characteristic: CBMCharacteristic) {
        if let n = characteristic as? CBMCharacteristicNative {
            peripheral.readValue(for: n.characteristic)
        }
    }
    
    public func readValue(for descriptor: CBMDescriptor) {
        if let n = descriptor as? CBMDescriptorNative {
            peripheral.readValue(for: n.descriptor)
        }
    }
    
    @available(iOS 9.0, *)
    public func maximumWriteValueLength(for type: CBMCharacteristicWriteType) -> Int {
        return peripheral.maximumWriteValueLength(for: type)
    }
    
    public func writeValue(_ data: Data, for characteristic: CBMCharacteristic,
                           type: CBMCharacteristicWriteType) {
        if let n = characteristic as? CBMCharacteristicNative {
            peripheral.writeValue(data, for: n.characteristic, type: type)
        }
    }
    
    public func writeValue(_ data: Data, for descriptor: CBMDescriptor) {
        if let n = descriptor as? CBMDescriptorNative {
            peripheral.writeValue(data, for: n.descriptor)
        }
    }
    
    public func setNotifyValue(_ enabled: Bool,
                               for characteristic: CBMCharacteristic) {
        if let n = characteristic as? CBMCharacteristicNative {
            peripheral.setNotifyValue(enabled, for: n.characteristic)
        }
    }
    
    #if !os(macOS)
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public func openL2CAPChannel(_ PSM: CBML2CAPPSM) {
        peripheral.openL2CAPChannel(PSM)
    }
    
    @available(iOS 27.0, *)
    public func startChannelSoundingSession(_ config: CBMChannelSoundingSessionConfiguration) {
        peripheral.startChannelSoundingSession(config)
    }
    
    @available(iOS 27.0, *)
    public func cancelChannelSoundingSession() {
        peripheral.cancelChannelSoundingSession()
    }
    #endif
    
    public override var hash: Int {
        return identifier.hashValue
    }
    
    public override var debugDescription: String {
        return peripheral.debugDescription
            .replacingOccurrences(of: "CBPeripheral", with: "CBMPeripheral")
    }
}
