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

/// Mock implementation of the ``CBMCentralManager``.
///
/// This implementation will interact only with mock peripherals created using
/// ``CBMPeripheralSpec/simulatePeripheral(identifier:proximity:)``.
open class CBMCentralManagerMock: CBMCentralManager {

    
    /// A list of all mock managers instantiated by user.
    private static var managers: [WeakRef<CBMCentralManagerMock>] = []
    /// A list of peripherals known to the system.
    private static var peripherals: [CBMPeripheralSpec] = [] {
        didSet {
            stopAdvertising()
            initializeAdvertising()
        }
    }
    /// A list of ``CBMPeripheral``s for SwiftUI Previews only.
    ///
    /// Registered items can be accessed using any ``CBMCentralManagerMock``.
    private static var previewPeripherals: Set<CBMPeripheralPreview> = Set()
    /// A map of all current advertisements of all simulated peripherals.
    private static var advertisementTimers = CBMDictionary<CBMAdvertisementConfig, Timer>()
    /// A mutex queue for managing managers.
    private static let mutex: DispatchQueue = DispatchQueue(label: "Mutex")
    /// The value of current authorization status for using Bluetooth.
    ///
    /// As `CBManagerAuthorization` was added in iOS 13, the raw value is kept.
    internal private(set) static var bluetoothAuthorization: Int? {
        didSet {
            notifyManagers()
        }
    }
    
    /// Mock RSSI deviation.
    ///
    /// Returned RSSI values will be in range
    /// `(base RSSI - deviation)...(base RSSI + deviation)`.
    ///
    /// Defaults to 15 dBm.
    internal private(set) static var rssiDeviation: CBMProximity.Deviation = .default
    
    /// The global state of the Bluetooth adapter on the device.
    fileprivate private(set) static var managerState: CBMManagerState = .poweredOff {
        didSet {
            notifyManagers()
        }
    }
    private static func notifyManagers() {
        // For all existing managers...
        let existingManagers = mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers.forEach { manager in
            // ...stop scanning if state changed to any other state
            // than `.poweredOn`. Also, forget all peripherals.
            if manager.state != .poweredOn {
                manager.isScanning = false
                manager.scanFilter = nil
                manager.scanOptions = nil
                manager.peripherals.values.forEach { $0.closeManager() }
                manager.peripherals.removeAll()
            }
            // ...and notify delegate.
            manager.queue.async {
                manager.delegate?.centralManagerDidUpdateState(manager)
            }
        }
        // Compact the list, if any of managers were disposed.
        mutex.sync {
            managers.removeAll { $0.ref == nil }
        }
    }
    
    /// Restarts advertising for all mock peripherals.
    ///
    /// The advertisement delays will be counted from the moment they are started.
    private static func initializeAdvertising() {
        peripherals
            .compactMap { peripheral in peripheral.advertisement?.map { config in (peripheral, config) } }
            .flatMap { $0 }
            .forEach { peripheral, config in
                startAdvertising(config, for: peripheral)
            }
    }
    
    /// Stops all advertising.
    private static func stopAdvertising() {
        advertisementTimers.forEach { $0.value.invalidate() }
        advertisementTimers.removeAll()
    }
    
    /// Starts the given advertisement.
    ///
    /// The advertisement delay will be counted from moment it is started.
    /// - Parameters:
    ///   - config: Advertisement configuration to start.
    ///   - mock: The advertising mock peripheral.
    private static func startAdvertising(_ config: CBMAdvertisementConfig, for mock: CBMPeripheralSpec) {
        
        // A valid advertising config is a single time advertisement (delay > 0),
        // or a periodic one (interval > 0) (or both - delayed periodic advertisement).
        // Not to be mistaken with "Periodic Advertisement" from Advertising Extension.
        guard config.delay > 0 || config.interval > 0 else {
            return
        }
        // Timer works only on queues with a active run loop.
        DispatchQueue.main.async {
            // If the first advertising is to be delayed, create a
            // temporary timer that will call the initial data.
            if config.delay > 0 {
                advertisementTimers[config] = Timer.scheduledTimer(
                    timeInterval: config.delay,
                    target: self,
                    selector: #selector(self.schedule(timer:)),
                    userInfo: (mock, config),
                    repeats: false)
            } else {
                advertisementTimers[config] = Timer.scheduledTimer(
                    timeInterval: config.interval,
                    target: self,
                    selector: #selector(self.notify(timer:)),
                    userInfo: (mock, config),
                    repeats: true)
            }
        }
    }
    
    /// Stops all advertising of the given peripheral.
    /// - Parameter mock: The mock peripheral that changed advertising set.
    private static func stopAdvertising(of mock: CBMPeripheralSpec) {
        mock.advertisement?.forEach { config in
            advertisementTimers
                .removeValue(forKey: config)?
                .invalidate()
        }
    }
    
    /// This timer is fired when the initial delay has passed and the device starts
    /// advertising with a advertisement config.
    ///
    /// The peripheral specification and advertising configuration is set as `userInfo`.
    /// - Parameter timer: The timer that is fired.
    @objc private static func schedule(timer: Timer) {
        guard let (mock, config) = timer.userInfo as? (CBMPeripheralSpec, CBMAdvertisementConfig) else {
            return
        }
        notify(config, for: mock)
        
        if config.interval > 0 {
            advertisementTimers[config] = Timer.scheduledTimer(
                timeInterval: config.interval,
                target: self,
                selector: #selector(self.notify(timer:)),
                userInfo: (mock, config),
                repeats: true)
        }
    }
    
    /// This is a Timer callback, that's called to emulate scanning for Bluetooth LE
    /// devices.
    ///
    /// The peripheral specification and advertising configuration is set as `userInfo`.
    /// - Parameter timer: The timer that is fired.
    @objc private static func notify(timer: Timer) {
        guard let (mock, config) = timer.userInfo as? (CBMPeripheralSpec, CBMAdvertisementConfig) else {
            return
        }
        notify(config, for: mock)
    }
    
    /// This is a Timer callback, that's called to emulate scanning for Bluetooth LE
    /// devices.
    ///
    /// The scanned peripheral is set as `userInfo`.
    /// - Parameters:
    ///   - config: Advertisement configuration to start.
    ///   - mock: The advertising mock peripheral.
    private static func notify(_ config: CBMAdvertisementConfig, for mock: CBMPeripheralSpec) {
        // If a peripheral is out of range, the packet gets missed.
        guard mock.proximity != .outOfRange else {
            return
        }
        // If the device is connected and does not advertise in that state, skip.
        guard !mock.isConnected || config.isAdvertisingWhenConnected else {
            return
        }
        let services = config.data[CBMAdvertisementDataServiceUUIDsKey] as? [CBMUUID]
        // Notify managers...
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers
            // that are scanning with no UUID filter, empty filter, or with at least one service in common.
            .filter { manager in
                manager.isScanning && (
                    manager.scanFilter == nil || manager.scanFilter!.isEmpty ||
                    services?.contains(where: manager.scanFilter!.contains) ?? false
                )
            }
            // For each scanning manager do the following:
            .forEach { manager in
                // The device has been scanned and cached.
                mock.isKnown = true
                // Get or create local peripheral instance.
                if manager.peripherals[mock.identifier] == nil {
                    manager.peripherals[mock.identifier] = CBMPeripheralMock(basedOn: mock, by: manager)
                }
                let peripheral = manager.peripherals[mock.identifier]!
                
                // If the Allow Duplicates flag was not set and the device was already reported,
                // don't report it for the second time
                let allowDuplicates = manager.scanOptions?[CBMCentralManagerScanOptionAllowDuplicatesKey] as? NSNumber ?? false as NSNumber
                if !peripheral.wasScanned || allowDuplicates.boolValue {
                    // Remember the scanned name from the last advertising packet.
                    peripheral.lastAdvertisedName = config.data[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.lastAdvertisedName
                    // Emulate RSSI based on proximity. Apply some deviation.
                    let rssi = mock.proximity.RSSI
                    let delta = CBMCentralManagerMock.rssiDeviation.value
                    let deviation = Int.random(in: -delta...delta)
                    manager.delegate?.centralManager(manager, didDiscover: peripheral,
                                                     advertisementData: config.data,
                                                     rssi: (rssi + deviation) as NSNumber)
                    // The first scan result is returned without a name.
                    // This flag must then be called after it has been reported.
                    // Setting this flag will cause the advertising name to be
                    // returned from CBPeripheral.name.
                    peripheral.wasScanned = true
                }
            }
        // When an connectable advertising packet was received from a device check if there
        // are any pending connections.
        let isConnectable = config.data[CBMAdvertisementDataIsConnectable] as? NSNumber ?? false as NSNumber
        if isConnectable.boolValue {
            peripheralBecameAvailable(mock)
        }
    }
    /// Whether the app is currently authorized to use Bluetooth.
    ///
    /// If `simulateAuthorization(:)` was not called it is assumed that the
    /// authorization was granted. However, in this case `CBMCentralManager.authorization`
    /// will return the value returned by the native API.
    private static var isAuthorized: Bool {
        return bluetoothAuthorization == nil || bluetoothAuthorization == 3 // CBManagerAuthorization.allowedAlways
    }
    private var scanFilter: [CBMUUID]?
    private var scanOptions: [String : Any]?

    /// The dispatch queue used for all callbacks.
    fileprivate let queue: DispatchQueue
    /// A map of peripherals known to this central manager.
    private var peripherals: [UUID : CBMPeripheralMock] = [:]
    /// A flag set to true few milliseconds after the manager is created.
    /// Some features, like the state or retrieving peripherals are not
    /// available when manager hasn't been initialized yet.
    private var initialized: Bool {
        // This method returns true if the manager is added to
        // the list of managers.
        // Calling tearDownSimulation() will remove all managers
        // from that list, making them uninitialized again.
        CBMCentralManagerMock.mutex.sync {
            CBMCentralManagerMock.managers.contains { $0.ref == self }
        }
    }
    
    // MARK: - Initializers
    
    public init() {
        self.queue = DispatchQueue.main
        super.init(true)
        initialize()
    }
    
    public init(delegate: CBMCentralManagerDelegate?,
                queue: DispatchQueue?) {
        self.queue = queue ?? DispatchQueue.main
        super.init(true)
        self.delegate = delegate
        initialize()
    }
    
    @available(iOS 7.0, *)
    public init(delegate: CBMCentralManagerDelegate?,
                queue: DispatchQueue?,
                options: [String : Any]?) {
        self.queue = queue ?? DispatchQueue.main
        super.init(true)
        self.delegate = delegate
        if let options = options,
           let identifierKey = options[CBMCentralManagerOptionRestoreIdentifierKey] as? String,
           let dict = CBMCentralManagerMock.simulateStateRestoration?(identifierKey) {
            var state: [String : Any] = [:]
            if let peripheralKeys = dict[CBMCentralManagerRestoredStatePeripheralsKey] as? [CBMPeripheralSpec] {
                let peripherals = peripheralKeys.map { mock in
                    CBMPeripheralMock(basedOn: mock, by: self, andRestoreState: true)
                }
                state[CBMCentralManagerRestoredStatePeripheralsKey] = peripherals
                peripherals.forEach { peripheral in
                    self.peripherals[peripheral.identifier] = peripheral
                }
            }
            if let scanServiceKey = dict[CBMCentralManagerRestoredStateScanServicesKey] as? [CBMUUID] {
                state[CBMCentralManagerRestoredStateScanServicesKey] = scanServiceKey
                self.isScanning = true
                self.scanFilter = scanServiceKey
            }
            if let scanOptions = dict[CBMCentralManagerRestoredStateScanOptionsKey] as? [String : Any] {
                state[CBMCentralManagerRestoredStateScanOptionsKey] = scanOptions
                self.isScanning = true
                self.scanOptions = scanOptions
            }
            delegate?.centralManager(self, willRestoreState: state)
        }
        initialize()
    }
    
    private func initialize() {
        if CBMCentralManagerMock.managerState == .poweredOn &&
           CBMCentralManagerMock.peripherals.isEmpty {
            NSLog("Warning: No simulated peripherals. " +
                  "Call simulatePeripherals(:) before creating central manager")
        }
        queue.async { [weak self] in
            if let self = self {
                CBMCentralManagerMock.mutex.sync {
                    CBMCentralManagerMock.managers.append(WeakRef(self))
                }
                self.delegate?.centralManagerDidUpdateState(self)
            }
        }
    }
    
    // MARK: - Central manager simulation methods
    
    /// This method may be used to register a list of ``CBMPeripheralPreview`` should they be used in Swift UI Previews.
    ///
    /// Registered peripherals can be connected, retrieved, and respond to basic requests
    /// - Parameter peripherals: The list of peripherals intended for Swift UI purposes.
    internal static func registerForPreviews(_ peripheral: CBMPeripheralPreview) {
        previewPeripherals.insert(peripheral)
    }
    
    /// Removes all active central manager instances and peripherals from the
    /// simulation, resetting it to the initial state.
    ///
    /// Use this to tear down your mocks between tests, e.g. in `tearDownWithError()`.
    /// All manager delegates will receive a ``CBMManagerState/unknown`` state update.
    public static func tearDownSimulation() {
        stopAdvertising()
        // Set the state of all currently existing central manager instances to
        // .unknown, which will make them invalid.
        managerState = .unknown
        // Remove all central manager instances.
        mutex.sync {
            managers.removeAll()
        }
        // Set the manager state to powered Off.
        managerState = .poweredOff
        // Reset the RSSI deviation to the default
        rssiDeviation = .default
        peripherals.removeAll()
    }
    
    /// Simulates the current authorization state of a Core Bluetooth manager.
    ///
    /// When set to `nil` (default), the native value is returned.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public static func simulateAuthorization(_ authorization: CBMManagerAuthorization) {
        bluetoothAuthorization = authorization.rawValue
    }
    
    /// Simulates the degree of variability in the reported RSSI.
    ///
    /// - Note: For unit testing, it is recommended to set this value to ``CBMProximity/Deviation/none``.
    public static func simulateRSSIDeviation(_ deviation: CBMProximity.Deviation) {
        rssiDeviation = deviation
    }
    
    /// This simulation method is called when a mock central manager was
    /// created with an option to restore the state
    /// (``CBMCentralManagerOptionRestoreIdentifierKey``).
    ///
    /// The returned map, if not `nil`, will be passed to
    /// ``CBMCentralManagerDelegate/centralManager(_:willRestoreState:)-4zyhg`` before creation.
    /// - SeeAlso: ``CBMCentralManagerRestoredStatePeripheralsKey``
    /// - SeeAlso: ``CBMCentralManagerRestoredStateScanServicesKey``
    /// - SeeAlso: ``CBMCentralManagerRestoredStateScanOptionsKey``
    public static var simulateStateRestoration: ((_ identifierKey: String) -> [String : Any]?)?
    
    #if !os(macOS)
    /// Returns a boolean value representing the support for the provided features.
    ///
    /// This method will be called when ``CBMCentralManager/supports(_:)`` method is called.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public static var simulateFeaturesSupport: ((_ features: CBMCentralManager.Feature) -> Bool)?
    #endif
    
    /// Sets the initial state of the Bluetooth central manager.
    ///
    /// This method should only be called ones, before any central manager
    /// is created. By default, the initial state is ``CBMManagerState/poweredOff``.
    /// - Parameter state: The initial state of the central manager.
    public static func simulateInitialState(_ state: CBMManagerState) {
        managerState = state
    }
    
    /// This method sets a list of simulated peripherals.
    ///
    /// Peripherals added using this method will be available for scanning
    /// and connecting, depending on their proximity. Use peripheral's
    /// ``CBMPeripheralSpec/simulateProximityChange(_:)`` to modify proximity.
    ///
    /// This method may only be called before any central manager was created
    /// or when Bluetooth state is ``CBMManagerState/poweredOff``. Existing list of peripherals
    /// will be overridden.
    /// - Parameter peripherals: Peripherals specifications.
    public static func simulatePeripherals(_ peripherals: [CBMPeripheralSpec]) {
        guard managers.isEmpty || managerState == .poweredOff else {
            NSLog("Warning: Peripherals can not be added while the simulation is running. " +
                  "Add peripherals before getting any central manager instance, " +
                  "or when manager is powered off.")
            return
        }
        CBMCentralManagerMock.peripherals = peripherals
    }
    
    /// Simulates turning the Bluetooth adapter on.
    public static func simulatePowerOn() {
        guard managerState != .poweredOn else {
            return
        }
        managerState = .poweredOn
    }
    
    /// Simulate turning the Bluetooth adapter off.
    public static func simulatePowerOff() {
        guard managerState != .poweredOff else {
            return
        }
        managerState = .poweredOff
    }
    
    // MARK: - Peripheral simulation methods
    
    /// Simulates a situation when the device changes its services.
    /// - Parameters:
    ///   - peripheral: The peripheral that changed services.
    ///   - newName: New device name.
    ///   - newServices: New list of device services.
    internal static func peripheral(_ peripheral: CBMPeripheralSpec,
                                    didUpdateName newName: String?,
                                    andServices newServices: [CBMServiceMock]) {
        // Is the peripheral simulated?
        guard peripherals.contains(peripheral) else {
            return
        }
        peripheral.services = newServices

        // If there are no connected devices, we're done.
        guard peripheral.virtualConnections > 0 else {
            return
        }
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers.forEach { manager in
            manager.peripherals[peripheral.identifier]?
                .notifyServicesChanged()
        }
        // Notify that the name has changed.
        if peripheral.name != newName {
            peripheral.name = newName
            existingManagers.forEach { manager in
                // TODO: This needs to be verified.
                //       Should a local peripheral copy be created if no such?
                //       Are all central managers notified about any device
                //       changing name?
                manager.peripherals[peripheral.identifier]?
                    .notifyNameChanged()
            }
        }
    }
    
    /// Simulates a notification sent from the peripheral.
    ///
    /// All central managers that have enabled notifications on it
    /// will receive ``CBMPeripheralDelegate/peripheral(_:didUpdateValueFor:error:)-62302``.
    /// - Parameter characteristic: The characteristic from which
    ///                             notification is to be sent.
    internal static func peripheral(_ peripheral: CBMPeripheralSpec,
                                    didUpdateValueFor characteristic: CBMCharacteristicMock) {
        // Is the peripheral simulated?
        guard peripherals.contains(peripheral) else {
            return
        }
        guard peripheral.virtualConnections > 0 else {
            return
        }
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers.forEach { manager in
            manager.peripherals[peripheral.identifier]?
                .notifyValueChanged(for: characteristic)
        }
    }
    
    /// Simulates a change in advertising packets for the given peripheral.
    ///
    /// The full advertising set is replaced with a new one and all timers are restarted.
    /// - Parameters:
    ///   - peripheral: The peripheral that changed advertising.
    ///   - advertisement: The new advertising set.
    internal static func peripheral(_ peripheral: CBMPeripheralSpec,
                                    didChangeAdvertisement advertisement: [CBMAdvertisementConfig]?) {
        // Stop current advertising of the given device.
        stopAdvertising(of: peripheral)
        // Set new advertising set.
        peripheral.advertisement = advertisement
        peripheral.advertisement?.forEach { config in
            startAdvertising(config, for: peripheral)
        }
    }
    
    /// This method simulates a new virtual connection to the given
    /// peripheral, as if some other application connected to it.
    ///
    /// Central managers will not be notified about the state change unless
    /// they registered for connection events using
    /// ``CBMCentralManager/registerForConnectionEvents(options:)``.
    /// Even without registering (which is available since iOS 13), they
    /// can retrieve the connected peripheral using
    /// ``CBMCentralManager/retrieveConnectedPeripherals(withServices:)``.
    ///
    /// The peripheral does not need to be registered before.
    /// - Parameter peripheral: The peripheral that has connected.
    internal static func peripheralDidConnect(_ peripheral: CBMPeripheralSpec) {
        // Is the peripheral simulated?
        guard peripherals.contains(peripheral) else {
            return
        }
        peripheral.virtualConnections += 1
        
        // TODO: notify a user registered for connection events
    }
    
    /// Method called when a peripheral becomes available (in range).
    ///
    /// If there is a pending connection request, it will connect.
    /// - Parameter peripheral: The peripheral that came in range.
    internal static func peripheralBecameAvailable(_ peripheral: CBMPeripheralSpec) {
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers.forEach { manager in
            if let target = manager.peripherals[peripheral.identifier],
               target.state == .connecting {
                target.connect() { result in
                    switch result {
                    case .success:
                        manager.delegate?.centralManager(manager, didConnect: target)
                    case .failure(let error):
                        manager.delegate?.centralManager(manager, didFailToConnect: target,
                                                         error: error)
                    }
                }
            }
        }
    }
    
    /// Simulates the peripheral to disconnect from the device.
    ///
    /// All connected mock central managers will receive
    /// ``CBMCentralManagerDelegate/centralManager(_:didDisconnectPeripheral:error:)-1lv48`` callback.
    /// - Parameters:
    ///   - peripheral: The peripheral to disconnect.
    ///   - error: The disconnection reason. Use ``CBMError`` or ``CBMATTError`` errors.
    internal static func peripheral(_ peripheral: CBMPeripheralSpec,
                                    didDisconnectWithError error: Error = CBError(.peripheralDisconnected)) {
        // Is the peripheral simulated?
        guard peripherals.contains(peripheral) else {
            return
        }
        // Notify all central managers.
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            managers.compactMap { $0.ref }
        }
        existingManagers.forEach { manager in
            if let target = manager.peripherals[peripheral.identifier],
               target.state == .connected {
                target.disconnected(withError: error) { error in
                    manager.delegate?.centralManager(manager,
                                                     didDisconnectPeripheral: target,
                                                     timestamp: CFAbsoluteTimeGetCurrent(),
                                                     isReconnecting: target.isReconnecting,
                                                     error: error)
                }
            }
        }
        // TODO: notify a user registered for connection events
    }
    
    // MARK: - CBCentralManager mock methods
    
    open override var state: CBMManagerState {
        guard initialized else {
            return .unknown
        }
        guard CBMCentralManagerMock.isAuthorized else {
            return .unauthorized
        }
        return CBMCentralManagerMock.managerState
    }
    
    
    @available(iOS, introduced: 13.0, deprecated: 13.1)
    @available(macOS, introduced: 10.15)
    @available(tvOS, introduced: 13.0, deprecated: 13.1)
    @available(watchOS, introduced: 6.0, deprecated: 6.1)
    open override var authorization: CBMManagerAuthorization {
        if let rawValue = CBMCentralManagerMock.bluetoothAuthorization,
           let authorization = CBMManagerAuthorization(rawValue: rawValue) {
            return authorization
        } else {
            // If `simulateAuthorization(:)` was not called, .allowedAlways is assumed.
            return .allowedAlways
        }
    }
    
    @available(iOS 13.1, macOS 10.15, tvOS 13.1, watchOS 6.1, *)
    open override class var authorization: CBMManagerAuthorization {
        if let rawValue = CBMCentralManagerMock.bluetoothAuthorization,
           let authorization = CBMManagerAuthorization(rawValue: rawValue) {
            return authorization
        } else {
            // If `simulateAuthorization(:)` was not called, .allowedAlways is assumed.
            return .allowedAlways
        }
    }
    
    open override func scanForPeripherals(withServices serviceUUIDs: [CBMUUID]?,
                                          options: [String : Any]? = nil) {
        // Central manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        isScanning = true
        scanFilter = serviceUUIDs
        scanOptions = options
    }
    
    open override func stopScan() {
        // Central manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        isScanning = false
        scanFilter = nil
        scanOptions = nil
        peripherals.values.forEach { $0.wasScanned = false }
    }
    
    open override func connect(_ peripheral: CBMPeripheral, options: [String : Any]? = nil) {
        // Handle the Preview peripheral.
        if let peripheral = peripheral as? CBMPeripheralPreview {
            peripheral.state = .connected
            delegate?.centralManager(self, didConnect: peripheral)
            return
        }
        // Central manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // Read connection options. Currently only auto-reconnect is supported.
        var enableAutoReconnect = false
        if var o = options {
            if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                let option = o.removeValue(forKey: CBMConnectPeripheralOptionEnableAutoReconnect) as? NSNumber
                enableAutoReconnect = option?.boolValue ?? false
            }
            if !o.isEmpty {
                NSLog("Warning: Connection options are not supported in mock central manager")
            }
        }
        // Ignore peripherals that are not mocks.
        guard let mock = peripheral as? CBMPeripheralMock else {
            return
        }
        // The peripheral must come from this central manager. Ignore other.
        // To connect a peripheral obtained using another central manager
        // use `retrievePeripherals(withIdentifiers:)` or
        // `retrieveConnectedPeripherals(withServices:)`.
        guard peripherals.values.contains(mock) else {
            return
        }
        // Connection is pending.
        mock.state = .connecting
        mock.isReconnecting = enableAutoReconnect
        // If the device is already connected, there is no need to waiting for
        // advertising packet.
        if mock.isAlreadyConnected {
            mock.connect() { _ in
                 self.delegate?.centralManager(self, didConnect: mock)
            }
        }
    }
    
    open override func cancelPeripheralConnection(_ peripheral: CBMPeripheral) {
        // Handle the Preview peripheral.
        if let peripheral = peripheral as? CBMPeripheralPreview {
            peripheral.state = .disconnected
            delegate?.centralManager(self,
                                     didDisconnectPeripheral: peripheral,
                                     timestamp: CFAbsoluteTimeGetCurrent(),
                                     isReconnecting: false,
                                     error: nil)
            return
        }
        // Central manager must be in powered on state.
        guard ensurePoweredOn() else { return }
        // Ignore peripherals that are not mocks.
        guard let mock = peripheral as? CBMPeripheralMock else {
            return
        }
        // It is not possible to cancel connection of a peripheral obtained
        // from another central manager.
        guard peripherals.values.contains(mock) else {
            return
        }
        mock.disconnect() {
            self.delegate?.centralManager(self,
                                          didDisconnectPeripheral: mock,
                                          timestamp: CFAbsoluteTimeGetCurrent(),
                                          isReconnecting: false,
                                          error: nil)
        }
    }
    
    open override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBMPeripheral] {
        // Check if any Preview peripheral matches the identifier.
        let previewPeripherals = Self.previewPeripherals
            .filter{ identifiers.contains($0.identifier) }
        if !previewPeripherals.isEmpty {
            return Array(previewPeripherals)
        }
        // Starting from iOS 13, this method returns peripherals only in ON state.
        guard ensurePoweredOn() else { return [] }
        // Also, look for them among other managers, and copy them to the local
        // manager.
        let missingIdentifiers = identifiers.filter { peripherals[$0] == nil }
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            CBMCentralManagerMock.managers.compactMap { $0.ref }
        }
        let peripheralsKnownByOtherManagers = missingIdentifiers
            .flatMap { identifier in
                existingManagers.compactMap { $0.peripherals[identifier] }
            }
            .map { CBMPeripheralMock(copy: $0, by: self) }
        peripheralsKnownByOtherManagers.forEach {
            peripherals[$0.identifier] = $0
        }
        // Peripherals that have not been scanned by any manager, but have been
        // cached by the system and can be retrieved.
        let stillMissingIdentifiers = identifiers.filter { peripherals[$0] == nil }
        let peripheralsCached = CBMCentralManagerMock.peripherals
            // Get only cached peripherals.
            .filter { $0.isKnown }
            // Search for those that are still missing.
            .filter { stillMissingIdentifiers.contains($0.identifier) }
            // Create a local copy.
            .map { CBMPeripheralMock(basedOn: $0, by: self) }
        peripheralsCached.forEach {
            peripherals[$0.identifier] = $0
        }
        // Now, with updated peripherals, get those known to this central manager.
        let localPeripherals = peripherals[identifiers]
        // Return them in the same order as requested, some may be missing.
        return localPeripherals
            .sorted {
                let firstIndex = identifiers.firstIndex(of: $0.identifier)!
                let secondIndex = identifiers.firstIndex(of: $1.identifier)!
                return firstIndex < secondIndex
            }
    }
    
    open override func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBMUUID]) -> [CBMPeripheral] {
        // Check if there exist any Preview peripheral with at least one common service.
        let previewPeripherals = Self.previewPeripherals
            .filter { peripheral in
                peripheral.services?.contains(where: { serviceUUIDs.contains($0.uuid) }) ?? false
            }
        if !previewPeripherals.isEmpty {
            return Array(previewPeripherals)
        }
        // Starting from iOS 13, this method returns peripherals only in ON state.
        guard ensurePoweredOn() else { return [] }
        // Get the connected peripherals with at least one of the given services
        // that are already known to this central manager.
        let peripheralsConnectedByThisManager = peripherals[serviceUUIDs]
            .filter { $0.state == .connected }
        // Other central managers may know some connected peripherals that
        // are not known to the local one.
        let existingManagers = CBMCentralManagerMock.mutex.sync {
            CBMCentralManagerMock.managers.compactMap { $0.ref }
        }
        let peripheralsConnectedByOtherManagers = existingManagers
            // Look for connected peripherals known to other managers.
            .flatMap {
                $0.peripherals[serviceUUIDs]
                    .filter { $0.state == .connected }
            }
            // Search for ones that are not known to the local manager.
            .filter { peripherals[$0.identifier] == nil }
            // Create a local copy.
            .map { CBMPeripheralMock(copy: $0, by: self) }
        // Add those copies to the local manager.
        peripheralsConnectedByOtherManagers.forEach {
            peripherals[$0.identifier] = $0
        }
        let peripheralsConnectedByOtherApps = CBMCentralManagerMock.peripherals
            .filter { $0.isConnected }
            // Search for ones that are not known to the local manager.
            .filter { peripherals[$0.identifier] == nil }
            // And only those that match any of given service UUIDs.
            .filter {
                $0.services?.contains { service in
                    serviceUUIDs.contains(service.uuid)
                } ?? false
            }
            // Create a local copy.
            .map { CBMPeripheralMock(basedOn: $0, by: self) }
        return peripheralsConnectedByThisManager
             + peripheralsConnectedByOtherManagers
             + peripheralsConnectedByOtherApps
    }
    
    #if !os(macOS)
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    open override func registerForConnectionEvents(options: [CBMConnectionEventMatchingOption : Any]? = nil) {
        fatalError("Mock connection events are not implemented")
    }
    #endif
    
    fileprivate func ensurePoweredOn() -> Bool {
        guard state == .poweredOn else {
            NSLog("[CoreBluetoothMock] API MISUSE: \(self) can only accept this command while in the powered on state")
            return false
        }
        return true
    }
    
}

// MARK: - CBPeripheralMock implementation

/// Mock implementation of the ``CBMPeripheral``.
///
/// This implementation will be used when creating peripherals by ``CBMCentralManagerMock``.
///
/// Unless required, this class should not be accessed directly, but rather by the common protocol ``CBMPeripheral``.
@objc open class CBMPeripheralMock: CBMPeer, CBMPeripheral {
    /// The parent central manager.
    private let manager: CBMCentralManagerMock
    /// The dispatch queue to call delegate methods on.
    private var queue: DispatchQueue {
        return manager.queue
    }
    private let mutex: DispatchQueue = DispatchQueue(label: "Mutex")
    /// The mock peripheral with user-defined implementation.
    private let mock: CBMPeripheralSpec
    /// Size of the outgoing buffer. Only this many packets
    /// can be written without response in a loop, without
    /// waiting for ``CBMPeripheral/canSendWriteWithoutResponse``.
    private let bufferSize = 20
    /// The current buffer size.
    private var availableWriteWithoutResponseBuffer: Int
    private var _canSendWriteWithoutResponse: Bool = false
    /// A flag indicating whether the last connection attempt was
    /// using ``CBMConnectPeripheralOptionEnableAutoReconnect`` option.
    ///
    /// This flag is only cleared when the device is disconnected using
    /// ``CBMCentralManager/cancelPeripheralConnection(_:)``.
    fileprivate var isReconnecting: Bool = false
    
    /// A flag set to `true` when the device was scanned for the first time during
    /// a single scan. This is to ensure that the result is not delivered twice unless
    /// ``CBMCentralManagerScanOptionAllowDuplicatesKey`` flag is set.
    fileprivate var wasScanned: Bool = false
    fileprivate var lastAdvertisedName: String? = nil
    fileprivate var isAlreadyConnected: Bool {
        return mock.isConnected
    }
    
    open var delegate: CBMPeripheralDelegate?
    
    open override var identifier: UUID {
        return mock.identifier
    }
    open var name: String? {
        return mock.wasConnected ? mock.name : lastAdvertisedName
    }
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open var canSendWriteWithoutResponse: Bool {
        return _canSendWriteWithoutResponse
    }
    open private(set) var ancsAuthorized: Bool = false
    @objc dynamic open fileprivate(set) var state: CBMPeripheralState = .disconnected
    open private(set) var services: [CBMService]? = nil
    
    // MARK: Initializers
    
    /// Creates a new peripheral mock based on the given peripheral specification.
    ///
    /// If the `restore` parameter is set to `false`, the peripheral will be in the
    /// disconnected state even if the emulated device was connected. Central manager
    /// needs to connect to the device to change the state.
    ///
    /// The `restore` parameter allows to restore the state of the peripheral, if the
    /// application was terminated and the central manager was created with
    /// `CBMCentralManagerOptionRestoreIdentifierKey` option.
    /// If the same central manager (with the same identifier) had that device connected
    /// or connecting when the app was terminated, the peripheral will be restored to the
    /// same state.
    ///
    /// - Parameters:
    ///   - mock: The peripheral specification.
    ///   - manager: The mock central manager.
    ///   - restore: `true` to restore the state of the peripheral, default is `false`.
    fileprivate init(basedOn mock: CBMPeripheralSpec,
                     by manager: CBMCentralManagerMock,
                     andRestoreState restore: Bool = false) {
        self.mock = mock
        self.manager = manager
        self.availableWriteWithoutResponseBuffer = bufferSize
        self.isReconnecting = restore
        
        // If the Central Manager restores its state, the previously
        // connected peripherals may still be connected or connecting.
        //
        // If CBMPeripheralSpec was created using .connected(...), the
        // virtual connections count has been set to 1.
        // Then, it is up to the proximity to decide if the device is
        // connected or connecting.
        if restore {
            // A non-connectable device could not have been connected.
            // Ignore it when restoring the state.
            guard mock.services != nil else {
                NSLog("Warning: The peripheral with identifier \(mock.identifier) is not connectable and can not be restored to connected state.")
                return
            }
            self.state = mock.isConnected && mock.proximity != .outOfRange ? .connected : .connecting
            self._canSendWriteWithoutResponse = state == .connected
        }
    }
    
    /// Creates a copy of the given peripheral mock.
    ///
    /// This new peripheral will be in disconnected state, even if the original
    /// was connected.
    fileprivate init(copy: CBMPeripheralMock,
                     by manager: CBMCentralManagerMock) {
        self.mock = copy.mock
        self.manager = manager
        self.availableWriteWithoutResponseBuffer = bufferSize
    }
    
    // MARK: Connection
    
    fileprivate func connect(completion: @escaping (Result<Void, Error>) -> ()) {
        // Ensure the device is disconnected.
        guard state == .connecting else {
            return
        }
        // Ensure the device is connectable and in range.
        guard let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              mock.proximity != .outOfRange else {
            // There's no timeout on iOS. The device will connect when brought back
            // into range. To cancel pending connection, call disconnect().
            return
        }
        // If the device is already connected (using a different central manager),
        // report success immediately. The device already has the connection with central
        // and will not be notified about another virtual client connection.
        if isAlreadyConnected {
            queue.async { [weak self] in
                if let self = self, self.state == .connecting {
                    self.state = .connected
                    self._canSendWriteWithoutResponse = true
                    self.mock.wasConnected = true
                    self.mock.virtualConnections += 1
                    completion(.success(()))
                }
            }
            return
        }
        // If the device wasn't connected emulate connection request.
        let result = delegate.peripheralDidReceiveConnectionRequest(mock)
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let self = self, self.state == .connecting {
                if case .success = result {
                    self.state = .connected
                    self._canSendWriteWithoutResponse = true
                    self.mock.wasConnected = true
                    self.mock.virtualConnections += 1
                } else {
                    self.state = .disconnected
                }
                completion(result)
            }
        }
    }
    
    fileprivate func disconnect(completion: @escaping () -> ()) {
        // Cancel auto-reconnection.
        isReconnecting = false
        // Cancel pending connection.
        guard state != .connecting else {
            state = .disconnected
            queue.async {
                completion()
            }
            return
        }
        // Ensure the device is connectable and connected.
        guard let interval = mock.connectionInterval,
              state == .connected else {
            return
        }
        if #available(iOS 9.0, *), case .connected = state {
            state = .disconnecting
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            // `tearDownSimulation()` could have been called before this is called.
            // See https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/issues/25
            if let self = self, self.state == .disconnecting,
               CBMCentralManagerMock.managerState == .poweredOn {
                self.state = .disconnected
                self.services = nil
                self._canSendWriteWithoutResponse = false
                self.mock.virtualConnections -= 1
                // Notify the mock delegate when the last connection
                // was terminated.
                if mock.virtualConnections == 0 {
                    self.mock.connectionDelegate?.peripheral(self.mock,
                                                             didDisconnect: nil)
                }
                completion()
            }
        }
    }
    
    fileprivate func disconnected(withError error: Error,
                                  completion: @escaping (Error?) -> ()) {
        // Ensure the device is connected.
        guard var interval = mock.connectionInterval,
              state == .connected else {
            return
        }
        // If a device disconnected with a timeout, the central waits
        // for the duration of supervision timeout before accepting
        // disconnection.
        if let error = error as? CBMError, error.code == .connectionTimeout,
           let timeout = mock.supervisionTimeout {
            interval = timeout
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let self = self, CBMCentralManagerMock.managerState == .poweredOn {
                if isReconnecting {
                    self.state = .connecting
                } else {
                    self.state = .disconnected
                    self.services = nil
                }
                self._canSendWriteWithoutResponse = false
                completion(error)
            }
        }
    }
    
    // MARK: Service modification
    
    fileprivate func notifyNameChanged() {
        guard state == .connected,
              let interval = mock.connectionInterval else {
            return
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let self = self, self.state == .connected {
                self.delegate?.peripheralDidUpdateName(self)
            }
        }
    }
    
    fileprivate func notifyServicesChanged() {
        guard state == .connected,
              let oldServices = services,
              let interval = mock.connectionInterval else {
            return
        }
        
        // Keep only services that hadn't changed.
        // TODO: What if the order of services (thus their handle numbers) has changed?
        services = oldServices
            .filter { service in
                mock.services!.contains {
                    $0.identifier == service.identifier
                }
            }
        let invalidatedServices = oldServices.filter { !services!.contains($0) }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let self = self, self.state == .connected {
                self.delegate?.peripheral(self, didModifyServices: invalidatedServices)
            }
        }
    }
    
    fileprivate func notifyValueChanged(for originalCharacteristic: CBMCharacteristicMock) {
        guard state == .connected,
              let interval = mock.connectionInterval,
              let service = services?.first(where: {
                $0.characteristics?.contains(where: {
                    $0.identifier == originalCharacteristic.identifier
                }) ?? false
              }),
              let characteristic = service.characteristics?.first(where: {
                  $0.identifier == originalCharacteristic.identifier
              }),
              characteristic.isNotifying else {
            return
        }

        let value = originalCharacteristic.value
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            if let self = self, self.state == .connected {
                characteristic.value = value
                self.delegate?.peripheral(self,
                                          didUpdateValueFor: characteristic,
                                          error: nil)
            }
        }
    }
    
    fileprivate func closeManager() {
        state = .disconnected
        services = nil
        _canSendWriteWithoutResponse = false
        mock.virtualConnections = 0
    }
    
    // MARK: Service discovery
    
    open func discoverServices(_ serviceUUIDs: [CBMUUID]?) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let mockServices = mock.services else {
            return
        }
        
        switch delegate.peripheral(mock,
                                   didReceiveServiceDiscoveryRequest: serviceUUIDs) {
        case .success:
            services = services ?? []
            let initialSize = services!.count
            services = services! + mockServices
                // Filter all device services that match given list (if set).
                .filter { serviceUUIDs == nil || serviceUUIDs!.isEmpty || serviceUUIDs!.contains($0.uuid) }
                // Filter those of them, that are not already in discovered services.
                .filter { s in !services!
                    .contains { ds in s.identifier == ds.identifier }
                }
                // Copy the service info, without included services or characteristics.
                .map { CBMService(shallowCopy: $0, for: self) }
            let newServicesCount = services!.count - initialSize
            // Service discovery may takes the more time, the more services
            // are discovered.
            let delay = interval * Double(newServicesCount)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self, didDiscoverServices: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self, didDiscoverServices: error)
                }
            }
        }
    }
    
    open func discoverIncludedServices(_ includedServiceUUIDs: [CBMUUID]?,
                                         for service: CBMService) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services, services.contains(service),
              let mockServices = mock.services,
              let mockService = mockServices.find(mockOf: service),
              let mockIncludedServices = mockService.includedServices else {
            return
        }
        
        mockService.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveIncludedServiceDiscoveryRequest: includedServiceUUIDs,
                                   for: mockService) {
        case .success:
            service._includedServices = service._includedServices ?? []
            let initialSize = service._includedServices!.count
            service._includedServices = service._includedServices! +
                mockIncludedServices
                    // Filter all included service that match given list (if set).
                    .filter { includedServiceUUIDs == nil || includedServiceUUIDs!.isEmpty || includedServiceUUIDs!.contains($0.uuid) }
                    // Filter those of them, that are not already in discovered services.
                    .filter { s in !service._includedServices!
                        .contains { ds in s.identifier == ds.identifier }
                    }
                    // Copy the service info, without included characteristics.
                    .map { CBMService(shallowCopy: $0, for: self) }
            let newServicesCount = service._includedServices!.count - initialSize
            // Service discovery may takes the more time, the more services
            // are discovered.
            let delay = interval * Double(newServicesCount)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverIncludedServicesFor: service,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverIncludedServicesFor: service,
                                              error: error)
                }
            }
        }
        
    }
    
    open func discoverCharacteristics(_ characteristicUUIDs: [CBMUUID]?,
                                        for service: CBMService) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services, services.contains(service),
              let mockServices = mock.services,
              let mockService = mockServices.find(mockOf: service),
              let mockCharacteristics = mockService.characteristics else {
            return
        }
        
        mockService.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveCharacteristicsDiscoveryRequest: characteristicUUIDs,
                                   for: mockService) {
        case .success:
            service._characteristics = service._characteristics ?? []
            let initialSize = service._characteristics!.count
            service._characteristics = service._characteristics! +
                mockCharacteristics
                    // Filter all service characteristics that match given list (if set).
                    .filter { characteristicUUIDs == nil || characteristicUUIDs!.isEmpty || characteristicUUIDs!.contains($0.uuid) }
                    // Filter those of them, that are not already in discovered characteristics.
                    .filter { c in !service._characteristics!
                        .contains { dc in c.identifier == dc.identifier }
                    }
                    // Copy the characteristic info, without included descriptors or value.
                    .map { CBMCharacteristic(shallowCopy: $0, in: service) }
            let newCharacteristicsCount = service._characteristics!.count - initialSize
            // Characteristics discovery may takes the more time, the more characteristics
            // are discovered.
            let delay = interval * Double(newCharacteristicsCount)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverCharacteristicsFor: service,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverCharacteristicsFor: service,
                                              error: error)
                }
            }
        }
    }
    
    open func discoverDescriptors(for characteristic: CBMCharacteristic) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services,
              let parentService = characteristic.optionalService, services.contains(parentService),
              let mockServices = mock.services,
              let mockCharacteristic = mockServices.find(mockOf: characteristic),
              let mockDescriptors = mockCharacteristic.descriptors else {
            return
        }
        
        mockCharacteristic.optionalService?.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveDescriptorsDiscoveryRequestFor: mockCharacteristic) {
        case .success:
            characteristic._descriptors = characteristic._descriptors ?? []
            let initialSize = characteristic._descriptors!.count
            characteristic._descriptors = characteristic._descriptors! +
                mockDescriptors
                    // Filter those of them, that are not already in discovered descriptors.
                    .filter { d in !characteristic._descriptors!
                        .contains { dd in d.identifier == dd.identifier }
                    }
                    // Copy the descriptors info, without the value.
                    .map { CBMDescriptor(shallowCopy: $0, in: characteristic) }
            let newDescriptorsCount = characteristic._descriptors!.count - initialSize
            // Descriptors discovery may takes the more time, the more descriptors
            // are discovered.
            let delay = interval * Double(newDescriptorsCount)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverDescriptorsFor: characteristic,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didDiscoverDescriptorsFor: characteristic,
                                              error: error)
                }
            }
        }
    }
    
    // MARK: Read requests
    
    open func readValue(for characteristic: CBMCharacteristic) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services,
              let service = characteristic.optionalService, services.contains(service),
              let mockServices = mock.services,
              let mockCharacteristic = mockServices.find(mockOf: characteristic) else {
            return
        }
        
        mockCharacteristic.optionalService?.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveReadRequestFor: mockCharacteristic) {
        case .success(let data):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    characteristic.value = data
                    self.delegate?.peripheral(self,
                                              didUpdateValueFor: characteristic,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didUpdateValueFor: characteristic,
                                              error: error)
                }
            }
        }
    }
    
    open func readValue(for descriptor: CBMDescriptor) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services,
              let service = descriptor.optionalCharacteristic?.service, services.contains(service),
              let mockServices = mock.services,
              let mockDescriptor = mockServices.find(mockOf: descriptor) else {
            return
        }
        
        mockDescriptor.characteristic?.optionalService?.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveReadRequestFor: mockDescriptor) {
        case .success(let data):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    descriptor.value = data
                    self.delegate?.peripheral(self,
                                              didUpdateValueFor: descriptor,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didUpdateValueFor: descriptor,
                                              error: error)
                }
            }
        }
    }
    
    // MARK: Write requests
    
    open func writeValue(_ data: Data,
                           for characteristic: CBMCharacteristic,
                           type: CBMCharacteristicWriteType) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let mtu = mock.mtu,
              let services = services,
              let service = characteristic.optionalService, services.contains(service),
              let mockServices = mock.services,
              let mockCharacteristic = mockServices.find(mockOf: characteristic) else {
            return
        }
        
        mockCharacteristic.optionalService?.peripheral = self
        if type == .withResponse {
            switch delegate.peripheral(mock,
                                       didReceiveWriteRequestFor: mockCharacteristic,
                                       data: data) {
            case .success:
                let packetsCount = max(1, (data.count + mtu - 2) / (mtu - 3))
                let delay = interval * Double(packetsCount)
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if let self = self, self.state == .connected {
                        self.delegate?.peripheral(self,
                                                  didWriteValueFor: characteristic,
                                                  error: nil)
                    }
                }
            case .failure(let error):
                queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                    if let self = self, self.state == .connected {
                        self.delegate?.peripheral(self,
                                                  didWriteValueFor: characteristic,
                                                  error: error)
                    }
                }
            }
        } else {
            // Decrease buffer.
            mutex.sync {
                guard self.availableWriteWithoutResponseBuffer > 0 else {
                    return
                }
                self.availableWriteWithoutResponseBuffer -= 1
                self._canSendWriteWithoutResponse = false
            }
            
            delegate.peripheral(mock,
                                didReceiveWriteCommandFor: mockCharacteristic,
                                data: data.subdata(in: 0..<min(mtu - 3, data.count)))

            queue.async { [weak self] in
                if let self = self, self.state == .connected {
                    // Increase buffer.
                    self.mutex.sync {
                        self.availableWriteWithoutResponseBuffer += 1
                        self._canSendWriteWithoutResponse = true
                    }
                    if #available(iOS 11.0, tvOS 11.0, watchOS 4.0, *) {
                        self.delegate?.peripheralIsReady(toSendWriteWithoutResponse: self)
                    }
                }
            }
        }
    }
    
    open func writeValue(_ data: Data, for descriptor: CBMDescriptor) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services,
              let service = descriptor.optionalCharacteristic?.service, services.contains(service),
              let mockServices = mock.services,
              let mockDescriptor = mockServices.find(mockOf: descriptor) else {
            return
        }
        
        mockDescriptor.characteristic?.optionalService?.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveWriteRequestFor: mockDescriptor,
                                   data: data) {
        case .success:
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didWriteValueFor: descriptor,
                                              error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didWriteValueFor: descriptor,
                                              error: error)
                }
            }
        }
    }
    
    @available(iOS 9.0, *)
    open func maximumWriteValueLength(for type: CBMCharacteristicWriteType) -> Int {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return 0 }
        guard state == .connected, let mtu = mock.mtu else {
            return 0
        }
        return type == .withResponse ? 512 : mtu - 3
    }
    
    // MARK: Enabling notifications and indications
    
    open func setNotifyValue(_ enabled: Bool,
                               for characteristic: CBMCharacteristic) {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        guard state == .connected,
              let delegate = mock.connectionDelegate,
              let interval = mock.connectionInterval,
              let services = services,
              let service = characteristic.optionalService, services.contains(service),
              let mockServices = mock.services,
              let mockCharacteristic = mockServices.find(mockOf: characteristic) else {
            return
        }
        guard enabled != characteristic.isNotifying else {
            // If the state is up-to-date, just notify the delegate immediately.
            // Tested on iOS 17 and 26.
            self.delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic, error: nil)
            return
        }
        
        mockCharacteristic.optionalService?.peripheral = self
        switch delegate.peripheral(mock,
                                   didReceiveSetNotifyRequest: enabled,
                                   for: mockCharacteristic) {
        case .success:
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    characteristic.isNotifying = enabled
                    self.delegate?.peripheral(self,
                                              didUpdateNotificationStateFor: characteristic,
                                              error: nil)
                    mockCharacteristic.isNotifying = enabled
                    delegate.peripheral(self.mock,
                                        didUpdateNotificationStateFor: mockCharacteristic,
                                        error: nil)
                }
            }
        case .failure(let error):
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let self = self, self.state == .connected {
                    self.delegate?.peripheral(self,
                                              didUpdateNotificationStateFor: characteristic,
                                              error: error)
                    delegate.peripheral(self.mock,
                                        didUpdateNotificationStateFor: mockCharacteristic,
                                        error: error)
                }
            }
        }        
    }
    
    // MARK: Other
    
    open func readRSSI() {
        // Central manager must be in powered on state.
        guard manager.ensurePoweredOn() else { return }
        queue.async { [weak self] in
            if let self = self, self.state == .connected {
                let rssi = self.mock.proximity.RSSI
                let delta = CBMCentralManagerMock.rssiDeviation.value
                let deviation = Int.random(in: -delta...delta)
                self.delegate?.peripheral(self, didReadRSSI: (rssi + deviation) as NSNumber,
                                          error: nil)
            }
        }
    }
    
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func openL2CAPChannel(_ PSM: CBML2CAPPSM) {
        fatalError("L2CAP mock is not implemented")
    }
    
    #if !os(macOS)
    @available(iOS 27.0, *)
    open func startChannelSoundingSession(_ config: CBMChannelSoundingSessionConfiguration) {
        fatalError("Channel Sounding mock is not implemented")
    }
    
    @available(iOS 27.0, *)
    open func cancelChannelSoundingSession() {
        fatalError("Channel Sounding mock is not implemented")
    }
    #endif
    
    open override var hash: Int {
        return mock.identifier.hashValue
    }
    
    open override var debugDescription: String {
        var stateString: String
        switch state {
        case .disconnected:  stateString = "disconnected"
        case .connecting:    stateString = "connecting"
        case .connected:     stateString = "connected"
        case .disconnecting: stateString = "disconnecting"
        @unknown default:    stateString = "unknown"
        }
        return "<CBMPeripheral: identifier: \(mock.identifier), mtu: \(mock.mtu ?? 23), state: \(stateString)>"
    }
}

// MARK: - Helpers

private class WeakRef<T: AnyObject> {
    fileprivate private(set) weak var ref: T?
    
    fileprivate init(_ value: T) {
        self.ref = value
    }
}

private extension Dictionary where Key == UUID, Value == CBMPeripheralMock {
    
    subscript(identifiers: [UUID]) -> [CBMPeripheralMock] {
        return identifiers.compactMap { self[$0] }
    }
    
    subscript(serviceUUIDs: [CBMUUID]) -> [CBMPeripheralMock] {
        return filter { (_, peripheral) in
            peripheral.services?
                .contains(where: { service in
                    serviceUUIDs.contains(service.uuid)
                })
            ?? false
        }.map { $0.value }
    }
    
}
