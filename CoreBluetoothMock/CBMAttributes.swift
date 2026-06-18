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

/// A representation of common aspects of services offered by a peripheral.
///
/// Concrete subclasses of `CBMAttribute` (and their mutable counterparts) represent the services a peripheral
/// offers, the characteristics of those services, and the descriptors attached to those characteristics. The concrete
/// subclasses are:
/// * ``CBMService``
/// * ``CBMCharacteristic``
/// * ``CBMDescriptor``
open class CBMAttribute: NSObject {
    
    /// The Bluetooth-specific UUID of the attribute.
    var uuid: CBMUUID {
        fatalError()
    }
}

/// A collection of data and associated behaviors that accomplish a function or feature of a device.
///
/// `CBMService` objects represent services of a remote peripheral. Services are either primary or secondary and
/// may contain multiple characteristics or included services (references to other services).
open class CBMService: CBMAttribute {
    internal let identifier: UUID
    private let _uuid: CBMUUID
    
    internal var _includedServices: [CBMService]?
    internal var _characteristics: [CBMCharacteristic]?

    #if swift(>=5.5)
    /// A back-pointer to the peripheral this service belongs to.
    open internal(set) weak var peripheral: CBMPeripheral?
    #else
    /// A back-pointer to the peripheral this service belongs to.
    open internal(set) unowned var peripheral: CBMPeripheral
    #endif
    
    /// The type of the service (primary or secondary).
    open fileprivate(set) var isPrimary: Bool
    
    open override var uuid: CBMUUID {
        return _uuid
    }
    
    /// A list of included services that have so far been discovered in this service.
    open var includedServices: [CBMService]? {
        return _includedServices
    }

    /// A list of characteristics that have so far been discovered in this service.
    open var characteristics: [CBMCharacteristic]? {
        return _characteristics
    }
    
    /// Returns a service, initialized with a service type and UUID.
    /// - Parameters:
    ///   - uuid: The Bluetooth UUID of the service.
    ///   - isPrimary: The type of the service (primary or secondary).
    init(type uuid: CBMUUID, primary isPrimary: Bool) {
        self.identifier = UUID()
        self.peripheral = uninitializedPeripheral
        self._uuid = uuid
        self.isPrimary = isPrimary
    }
    
    init(shallowCopy service: CBMService,
         for peripheral: CBMPeripheral) {
        self.identifier = service.identifier
        self.peripheral = peripheral
        self._uuid = service._uuid
        self.isPrimary = service.isPrimary
    }
    
    convenience init(copy service: CBMService,
                     for peripheral: CBMPeripheral) {
        self.init(shallowCopy: service, for: peripheral)
        self._includedServices = service._includedServices?.map { includedService in
            CBMService(copy: includedService, for: peripheral)
        }
        self._characteristics = service._characteristics?.map { characteristic in
            CBMCharacteristic(copy: characteristic, in: self)
        }
    }
}

internal class CBMServiceNative: CBMService {
    let service: CBService
    
    init(_ service: CBService, in peripheral: CBMPeripheral) {
        self.service = service
        super.init(type: service.uuid, primary: service.isPrimary)
        self.peripheral = peripheral
        self.isPrimary = service.isPrimary
                
        let nativeCharacteristics = safeCharacteristics(of: service)
        if !nativeCharacteristics.isEmpty {
            _characteristics = nativeCharacteristics.map { CBMCharacteristicNative($0, in: self) }
        }
        
        if let nativeSecondaryServices = service.includedServices {
            _includedServices = nativeSecondaryServices.map { CBMServiceNative($0, in: peripheral) }
        }
    }
    
    /// This method is updates the wrapper with the current version of `CBService`.
    ///
    /// The method is called when user discovers new service, characteristic or a descriptor.
    /// The internal wrappers need to reflect the change and add missing attributes.
    func update(_ service: CBService) {
        for includedService in service.includedServices ?? [] {
            if _includedServices == nil { _includedServices = [] }
            if let existing = (_includedServices as? [CBMServiceNative])?.first(where: { $0.service == includedService }) {
                existing.update(includedService)
            } else {
                let newService = CBMServiceNative(includedService, in: peripheral!)
                _includedServices!.append(newService)
            }
        }
        
        for characteristic in safeCharacteristics(of: service) {
            if _characteristics == nil { _characteristics = [] }
            if let existing = (_characteristics as? [CBMCharacteristicNative])?.first(where: { $0.characteristic == characteristic }) {
                existing.update(characteristic)
            } else {
                let newCharacteristic = CBMCharacteristicNative(characteristic, in: self)
                _characteristics!.append(newCharacteristic)
            }
        }
    }
    
    /// There is a case when for some reason one of the item in characteristics array is CBService.
    private func safeCharacteristics(of service: CBService) -> [CBCharacteristic] {
        let characteristics: [CBCharacteristic]

        if let rawArray = service.characteristics as NSArray? {
            characteristics = rawArray.compactMap { $0 as? CBCharacteristic }
        } else {
            characteristics = []
        }
        
        return characteristics
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMServiceNative {
            return service == other.service
        }
        return false
    }
    
}

/// Mock implementation of ``CBMService``.
open class CBMServiceMock: CBMService {
    
    /// Returns a service, initialized with a service type and UUID.
    /// - Parameters:
    ///   - uuid: The Bluetooth UUID of the service.
    ///   - isPrimary: The type of the service (primary or secondary).
    ///   - includedServices: Optional list of included services.
    ///   - characteristics: Optional list of characteristics.
    public convenience init(type uuid: CBMUUID, primary isPrimary: Bool,
                            includedServices: CBMServiceMock...,
                            characteristics: CBMCharacteristicMock...) {
        self.init(type: uuid,
                  primary: isPrimary,
                  includedServices: includedServices,
                  characteristics: characteristics)
    }

    /// Returns a service, initialized with a service type and UUID.
    /// - Parameters:
    ///   - uuid: The Bluetooth UUID of the service.
    ///   - isPrimary: The type of the service (primary or secondary).
    ///   - includedServices: Optional array of included services.
    ///   - characteristics: Optional array of characteristics.
    public init(type uuid: CBMUUID, primary isPrimary: Bool,
                includedServices: [CBMServiceMock]? = nil,
                characteristics: [CBMCharacteristicMock]? = nil) {
        super.init(type: uuid, primary: isPrimary)
        if let includedServices = includedServices {
            self._includedServices = includedServices
            // Note: includedServices[..].peripheral is still nil at this point.
        }
        if let characteristics = characteristics {
            self._characteristics = characteristics
            // Assign parent service instance.
            self._characteristics?.forEach { $0.service = self }
        }
    }

    open override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMServiceMock {
            return identifier == other.identifier
        }
        return false
    }
}

/// A characteristic of a remote peripheral’s service.
///
/// `CBMCharacteristic` represents further information about a peripheral’s service. In particular, `CBMCharacteristic`
/// objects represent the characteristics of a remote peripheral’s service. A characteristic contains a single value and any number
/// of descriptors describing that value. The properties of a characteristic determine how you can use a characteristic’s value,
/// and how you access the descriptors.
open class CBMCharacteristic: CBMAttribute {
    internal let identifier: UUID
    private let _uuid: CBMUUID
    
    internal var _descriptors: [CBMDescriptor]?
    
    open override var uuid: CBMUUID {
        return _uuid
    }

    #if swift(>=5.5)
    /// A back-pointer to the service this characteristic belongs to.
    open internal(set) weak var service: CBMService?
    #else
    /// A back-pointer to the service this characteristic belongs to.
    open internal(set) unowned var service: CBMService
    #endif
    
    /// Casts the sometimes weak, sometimes unowned service to
    /// always optional object.
    internal var optionalService: CBMService? {
        return service
    }
    
    /// The properties of the characteristic.
    public let properties: CBMCharacteristicProperties

    /// The value of the characteristic.
    open internal(set) var value: Data?

    /// A list of the descriptors that have so far been discovered
    /// in this characteristic.
    open var descriptors: [CBMDescriptor]? {
        return _descriptors
    }

    /// Whether the characteristic is currently notifying or not.
    open internal(set) var isNotifying: Bool

    /// Returns an initialized characteristic.
    /// - Parameters:
    ///   - uuid: The Bluetooth UUID of the characteristic.
    ///   - properties: The properties of the characteristic.
    init(type uuid: CBMUUID, properties: CBMCharacteristicProperties) {
        self.identifier = UUID()
        self.service = uninitializedService
        self._uuid = uuid
        self.properties = properties
        self.isNotifying = false
    }
    
    init(shallowCopy characteristic: CBMCharacteristic, in service: CBMService) {
        self.identifier = characteristic.identifier
        self.service = service
        self._uuid = characteristic._uuid
        self.properties = characteristic.properties
        self.isNotifying = false
    }
    
    convenience init(copy characteristic: CBMCharacteristic, in service: CBMService) {
        self.init(shallowCopy: characteristic, in: service)
        self._descriptors = characteristic._descriptors?.map { descriptor in
            CBMDescriptor(copy: descriptor, in: self)
        }
    }
}

internal class CBMCharacteristicNative: CBMCharacteristic {
    let characteristic: CBCharacteristic
    
    init(_ characteristic: CBCharacteristic, in service: CBMService) {
        self.characteristic = characteristic
        super.init(type: characteristic.uuid, properties: characteristic.properties)
        self.service = service
        self.value = characteristic.value
        self.isNotifying = characteristic.isNotifying
        
        if let nativeDescriptors = characteristic.descriptors {
            _descriptors = nativeDescriptors.map { CBMDescriptorNative($0, in: self) }
        }
    }
    
    func update(_ characteristic: CBCharacteristic) {
        for descriptor in characteristic.descriptors ?? [] {
            if _descriptors == nil { _descriptors = [] }
            if let existing = (_descriptors as? [CBMDescriptorNative])?.first(where: { $0.descriptor == descriptor }) {
                existing.update(descriptor)
            } else {
                let newDescriptor = CBMDescriptorNative(descriptor, in: self)
                _descriptors!.append(newDescriptor)
            }
        }
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMCharacteristicNative {
            return characteristic == other.characteristic
        }
        return false
    }
}

/// Mock implementation of ``CBMCharacteristic``.
open class CBMCharacteristicMock: CBMCharacteristic {

    open override var descriptors: [CBMDescriptor]? {
        set {
            _descriptors = newValue
            _descriptors?.forEach { $0.characteristic = self }
        }
        get { return _descriptors }
    }
    
    /// Returns an initialized characteristic.
    /// - Parameters:
    ///   - uuid: The Bluetooth UUID of the characteristic.
    ///   - properties: The properties of the characteristic.
    ///   - descriptors: Optional list of descriptors.
    public init(type uuid: CBMUUID, properties: CBMCharacteristicProperties,
                descriptors: CBMDescriptorMock...) {
        super.init(type: uuid, properties: properties)
        self.descriptors = descriptors
    }
    
    open override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMCharacteristicMock {
            return identifier == other.identifier
        }
        return false
    }
}

/// An object that provides further information about a remote peripheral’s characteristic.
///
/// `CBMDescriptor` represents a descriptor of a peripheral’s characteristic. In particular, `CBMDescriptor` objects
/// represent the descriptors of a remote peripheral’s characteristic. Descriptors provide further information about a
/// characteristic’s value. For example, they may describe the value in human-readable form and describe how to format
/// the value for presentation purposes. Characteristic descriptors also indicate whether a characteristic’s value indicates
/// or notifies a client (a central) when the value of the characteristic changes.
///
/// ``CBMUUID`` details six predefined descriptors and their corresponding value types. `CBMDescriptor` lists the
/// predefined descriptors and the ``CBMUUID`` constants that represent them.
open class CBMDescriptor: CBMAttribute {
    internal let identifier: UUID
    private let _uuid: CBMUUID
    
    open override var uuid: CBMUUID {
        return _uuid
    }
    
    #if swift(>=5.5)
    /// A back-pointer to the characteristic this descriptor belongs to.
    open internal(set) weak var characteristic: CBMCharacteristic?
    #else
    /// A back-pointer to the characteristic this descriptor belongs to.
    open internal(set) unowned var characteristic: CBMCharacteristic
    #endif
    
    /// Casts the sometimes weak, sometimes unowned characteristic to
    /// always optional object.
    internal var optionalCharacteristic: CBMCharacteristic? {
        return characteristic
    }

    /// The value of the descriptor.
    open internal(set) var value: Any?
    
    /// Returns `true` if the descriptor is a Client Configuration Characteristic Descriptor (CCCD); otherwise `false`.
    internal var isCCCD: Bool {
        return uuid.uuidString == "2902"
    }
    
    init(type uuid: CBMUUID) {
        self.identifier = UUID()
        self.characteristic = uninitializedCharacteristic
        self._uuid = uuid
    }
    
    init(shallowCopy descriptor: CBMDescriptor, in characteristic: CBMCharacteristic) {
        self.identifier = descriptor.identifier
        self.characteristic = characteristic
        self._uuid = descriptor._uuid
    }
    
    convenience init(copy descriptor: CBMDescriptor, in characteristic: CBMCharacteristic) {
        self.init(shallowCopy: descriptor, in: characteristic)
    }
}

internal class CBMDescriptorNative: CBMDescriptor {
    let descriptor: CBDescriptor
    
    init(_ descriptor: CBDescriptor, in characteristic: CBMCharacteristic) {
        self.descriptor = descriptor
        super.init(type: descriptor.uuid)
        self.characteristic = characteristic
        self.value = descriptor.value
    }
    
    func update(_ descriptor: CBDescriptor) {
        self.value = descriptor.value
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMDescriptorNative {
            return descriptor == other.descriptor
        }
        return false
    }
}

/// Mock implementation of ``CBMDescriptor``.
open class CBMDescriptorMock: CBMDescriptor {
    
    public override init(type uuid: CBMUUID) {
        super.init(type: uuid)
    }
    
    open override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? CBMDescriptorMock {
            return identifier == other.identifier
        }
        return false
    }
}

/// A mock implementation of Client Characteristic Configuration descriptor (CCCD).
///
/// This descriptor should be added to characteristics with `.notify` or `.indicate` properties.
open class CBMClientCharacteristicConfigurationDescriptorMock: CBMDescriptorMock {
    
    public init() {
        super.init(type: CBMUUID(string: "2902"))
    }
}

/// A type alias of ``CBMClientCharacteristicConfigurationDescriptorMock``.
public typealias CBMCCCDescriptorMock = CBMClientCharacteristicConfigurationDescriptorMock

// MARK: - Utilities

internal extension Array where Element == CBMServiceMock {
    
    func find(mockOf service: CBMService) -> CBMServiceMock? {
        return first { $0.identifier == service.identifier }
    }
    
    func find(mockOf characteristic: CBMCharacteristic) -> CBMCharacteristicMock? {
        guard let service = characteristic.optionalService,
              let mockService = find(mockOf: service),
              let mockCharacteristic = mockService.characteristics?.first(where: {
                $0.identifier == characteristic.identifier
              }) else {
            return nil
        }
        return mockCharacteristic as? CBMCharacteristicMock
    }
    
    func find(mockOf descriptor: CBMDescriptor) -> CBMDescriptorMock? {
        guard let characteristic = descriptor.optionalCharacteristic,
              let service = characteristic.optionalService,
              let mockService = find(mockOf: service),
              let mockCharacteristic = mockService.characteristics?.first(where: {
                $0.identifier == characteristic.identifier
              }),
              let mockDescriptor = mockCharacteristic.descriptors?.first(where: {
                $0.identifier == descriptor.identifier
              }) else {
            return nil
        }
        return mockDescriptor as? CBMDescriptorMock
    }
    
}

// MARK: - Mocking uninitialized objects

fileprivate let uninitializedPeripheral   = CBMPeripheralUninitialized()
fileprivate let uninitializedService        = CBMServiceUninitialized()
fileprivate let uninitializedCharacteristic = CBMCharacteristicUninitialized()

fileprivate class CBMPeripheralUninitialized: CBMPeripheral, CustomDebugStringConvertible {
    let debugDescription: String = "<uninitialized>"
    
    var identifier: UUID { uninitialized() }
    var name: String? { uninitialized() }
    var state: CBMPeripheralState { uninitialized() }
    var services: [CBMService]? { uninitialized() }
    var canSendWriteWithoutResponse: Bool { uninitialized() }
    var ancsAuthorized: Bool { uninitialized() }
    var delegate: CBMPeripheralDelegate? {
        get { uninitialized() }
        set { uninitialized() }
    }
    
    func readRSSI() {
        uninitialized()
    }
    
    func discoverServices(_ serviceUUIDs: [CBMUUID]?) {
        uninitialized()
    }
    
    func discoverIncludedServices(_ includedServiceUUIDs: [CBMUUID]?,
                                  for service: CBMService) {
        uninitialized()
    }
    
    func discoverCharacteristics(_ characteristicUUIDs: [CBMUUID]?,
                                 for service: CBMService) {
        uninitialized()
    }
    
    func discoverDescriptors(for characteristic: CBMCharacteristic) {
        uninitialized()
    }
    
    func readValue(for characteristic: CBMCharacteristic) {
        uninitialized()
    }
    
    func readValue(for descriptor: CBMDescriptor) {
        uninitialized()
    }
    
    func maximumWriteValueLength(for type: CBMCharacteristicWriteType) -> Int {
        uninitialized()
    }
    
    func writeValue(_ data: Data,
                    for characteristic: CBMCharacteristic,
                    type: CBMCharacteristicWriteType) {
        uninitialized()
    }
    
    func writeValue(_ data: Data, for descriptor: CBMDescriptor) {
        uninitialized()
    }
    
    func setNotifyValue(_ enabled: Bool,
                        for characteristic: CBMCharacteristic) {
        uninitialized()
    }
    
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func openL2CAPChannel(_ PSM: CBML2CAPPSM) { uninitialized() }
    
    #if !os(macOS)
    @available(iOS 27.0, *)
    func startChannelSoundingSession(_ config: CBMChannelSoundingSessionConfiguration) {
        uninitialized()
    }
    
    @available(iOS 27.0, *)
    func cancelChannelSoundingSession() { uninitialized() }
    #endif
    
    func uninitialized() -> Never {
        fatalError("Uninitialized")
    }
}

fileprivate class CBMServiceUninitialized: CBMService {
    override var debugDescription: String { return "<uninitialized>" }
    override var uuid: CBMUUID { uninitialized() }
    override var characteristics: [CBMCharacteristic]? { uninitialized() }
    override var isPrimary: Bool {
        get { uninitialized() }
        set { uninitialized() }
    }
    
    init() {
        super.init(type: CBMUUID(), primary: true)
    }
    
    func uninitialized() -> Never {
        fatalError("Uninitialized")
    }
}

fileprivate class CBMCharacteristicUninitialized: CBMCharacteristic {
    override var debugDescription: String { return "<uninitialized>" }
    override var uuid: CBMUUID { uninitialized() }
    override var descriptors: [CBMDescriptor]? { uninitialized() }
    override var value: Data? {
        get { uninitialized() }
        set { uninitialized() }
    }
    override var isNotifying: Bool {
        get { uninitialized() }
        set { uninitialized() }
    }
    
    init() {
        super.init(type: CBMUUID(), properties: [])
    }
    
    func uninitialized() -> Never {
        fatalError("Uninitialized")
    }
}
