/*
* Copyright (c) 2026, Nordic Semiconductor
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

import XCTest
@testable import CoreBluetoothMock

// MARK: - Test device

/// A simulated device used by the central manager behavior tests.
///
/// It exposes two services:
/// - `serviceA` with a readable, a writable and a notifying characteristic,
/// - `serviceB` with a single readable characteristic.
///
/// All requests are recorded, so that tests can check what reached the device.
final class TestDevice: CBMPeripheralSpecDelegate {
    static let serviceA = CBMUUID(string: "1111")
    static let serviceB = CBMUUID(string: "2222")
    static let readChar = CBMUUID(string: "AA01")
    static let writeChar = CBMUUID(string: "AA02")
    static let notifyChar = CBMUUID(string: "AA03")
    static let otherChar = CBMUUID(string: "BB01")
    static let userDescription = CBMUUID(string: "2901")
    static let name = "Test Device"

    let identifier = UUID()
    private(set) var spec: CBMPeripheralSpec!

    // Behavior.
    var connectionResult: Result<Void, Error> = .success(())
    var discoveryResult: Result<Void, Error> = .success(())
    var writeResult: Result<Void, Error> = .success(())
    var descriptorWriteResult: Result<Void, Error> = .success(())
    var values: [CBMUUID : Data] = [
        readChar: Data([0x01, 0x02, 0x03]),
        notifyChar: Data([0x00]),
        otherChar: Data([0xFF])
    ]

    // Recorded requests.
    private(set) var writes: [(uuid: CBMUUID, data: Data)] = []
    private(set) var commands: [(uuid: CBMUUID, data: Data)] = []
    private(set) var notifyRequests: [(uuid: CBMUUID, enabled: Bool)] = []
    private(set) var disconnections = 0
    private(set) var connectionRequests = 0
    private(set) var descriptorWrites: [(uuid: CBMUUID, data: Data)] = []

    // Attributes of the device. They are created for each instance, as their
    // identity is used when matching them with the peripheral's copies.
    let readCharacteristic: CBMCharacteristicMock
    let writeCharacteristic: CBMCharacteristicMock
    let notifyCharacteristic: CBMCharacteristicMock
    let otherCharacteristic: CBMCharacteristicMock

    init(mtu: Int = 23, proximity: CBMProximity = .immediate) {
        readCharacteristic = CBMCharacteristicMock(
            type: TestDevice.readChar, properties: [.read],
            descriptors: CBMDescriptorMock(type: TestDevice.userDescription))
        writeCharacteristic = CBMCharacteristicMock(
            type: TestDevice.writeChar, properties: [.write, .writeWithoutResponse])
        notifyCharacteristic = CBMCharacteristicMock(
            type: TestDevice.notifyChar, properties: [.notify, .read],
            descriptors: CBMClientCharacteristicConfigurationDescriptorMock())
        otherCharacteristic = CBMCharacteristicMock(
            type: TestDevice.otherChar, properties: [.read])

        let serviceA = CBMServiceMock(type: TestDevice.serviceA, primary: true,
                                      characteristics: readCharacteristic,
                                                       writeCharacteristic,
                                                       notifyCharacteristic)
        let serviceB = CBMServiceMock(type: TestDevice.serviceB, primary: true,
                                      characteristics: otherCharacteristic)
        spec = CBMPeripheralSpec
            .simulatePeripheral(identifier: identifier, proximity: proximity)
            .advertising(
                advertisementData: [
                    CBMAdvertisementDataLocalNameKey: TestDevice.name,
                    CBMAdvertisementDataServiceUUIDsKey: [TestDevice.serviceA],
                    CBMAdvertisementDataIsConnectable: true as NSNumber
                ],
                withInterval: 0.05)
            .connectable(name: TestDevice.name,
                         services: [serviceA, serviceB],
                         delegate: self,
                         connectionInterval: 0.01,
                         mtu: mtu)
            .allowForRetrieval()
            .build()
    }

    // MARK: CBMPeripheralSpecDelegate

    func peripheralDidReceiveConnectionRequest(_ peripheral: CBMPeripheralSpec)
        -> Result<Void, Error> {
        connectionRequests += 1
        return connectionResult
    }

    func peripheral(_ peripheral: CBMPeripheralSpec, didDisconnect error: Error?) {
        disconnections += 1
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveServiceDiscoveryRequest serviceUUIDs: [CBMUUID]?)
        -> Result<Void, Error> {
        return discoveryResult
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveCharacteristicsDiscoveryRequest characteristicUUIDs: [CBMUUID]?,
                    for service: CBMServiceMock) -> Result<Void, Error> {
        return discoveryResult
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveReadRequestFor characteristic: CBMCharacteristicMock)
        -> Result<Data, Error> {
        guard let value = values[characteristic.uuid] else {
            return .failure(CBMATTError(.readNotPermitted))
        }
        return .success(value)
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveReadRequestFor descriptor: CBMDescriptorMock)
        -> Result<Data, Error> {
        return .success(Data("description".utf8))
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveWriteRequestFor descriptor: CBMDescriptorMock,
                    data: Data) -> Result<Void, Error> {
        descriptorWrites.append((descriptor.uuid, data))
        return descriptorWriteResult
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
                    data: Data) -> Result<Void, Error> {
        writes.append((characteristic.uuid, data))
        return writeResult
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveWriteCommandFor characteristic: CBMCharacteristicMock,
                    data: Data) {
        commands.append((characteristic.uuid, data))
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveSetNotifyRequest enabled: Bool,
                    for characteristic: CBMCharacteristicMock) -> Result<Void, Error> {
        notifyRequests.append((characteristic.uuid, enabled))
        if characteristic.properties.isDisjoint(with: [.notify, .indicate]) {
            return .failure(CBMError(.invalidHandle))
        }
        return .success(())
    }
}

// MARK: - Base test case

/// A base class for tests of the central role.
///
/// It creates a ``CBMCentralManagerMock`` with a delegate proxy, a test device,
/// and provides helpers to wait for asynchronous callbacks.
///
/// The simulation is not torn down between tests, as the example app owns
/// a central manager that must stay valid. Instead, the adapter is powered off.
class CentralBehaviorTestCase: XCTestCase {
    var device: TestDevice!
    var manager: CBMCentralManagerMock!
    let managerDelegate = CBMCentralManagerDelegateProxy()
    let peripheralDelegate = CBMPeripheralDelegateProxy()

    override func setUpWithError() throws {
        CBMCentralManagerMock.simulateRSSIDeviation(.none)
    }

    override func tearDownWithError() throws {
        CBMCentralManagerMock.simulatePowerOff()
        CBMCentralManagerMock.simulateRSSIDeviation(.default)
        if #available(iOS 13.0, *) {
            CBMCentralManagerMock.simulateAuthorization(.allowedAlways)
        }
        // Callbacks of a manager that is still being released must not reach this test.
        managerDelegate.didUpdateState = nil
        managerDelegate.didDiscoverPeripheral = nil
        managerDelegate.didConnect = nil
        managerDelegate.didFailToConnect = nil
        managerDelegate.didDisconnect = nil
        manager = nil
        device = nil
    }

    // MARK: Fixtures

    /// Creates the test device and the manager, and waits until the manager is ready.
    ///
    /// - Parameters:
    ///   - mtu: The MTU of the test device.
    ///   - proximity: The proximity of the test device.
    ///   - initialState: The initial state of the Bluetooth adapter.
    func setUpManager(mtu: Int = 23,
                      proximity: CBMProximity = .immediate,
                      initialState: CBMManagerState = .poweredOn) {
        device = TestDevice(mtu: mtu, proximity: proximity)
        CBMCentralManagerMock.simulatePeripherals([device.spec])
        CBMCentralManagerMock.simulateInitialState(initialState)

        waitFor("Manager ready") { ready in
            managerDelegate.didUpdateState = { _ in ready.fulfill() }
            manager = CBMCentralManagerMock(delegate: managerDelegate, queue: nil)
        }
        managerDelegate.didUpdateState = nil
    }

    /// Returns the peripheral of the test device, as known to the manager.
    func retrieveDevice() throws -> CBMPeripheral {
        let peripherals = manager.retrievePeripherals(withIdentifiers: [device.identifier])
        return try XCTUnwrap(peripherals.first, "Test device not retrieved")
    }

    /// Connects to the test device and returns the connected peripheral.
    func connectToDevice() throws -> CBMPeripheral {
        let peripheral = try retrieveDevice()
        peripheral.delegate = peripheralDelegate
        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        managerDelegate.didConnect = nil
        XCTAssertEqual(peripheral.state, .connected)
        return peripheral
    }

    /// Connects to the test device and discovers all services,
    /// characteristics and descriptors.
    func connectAndDiscover() throws -> CBMPeripheral {
        let peripheral = try connectToDevice()

        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
        }
        for service in try XCTUnwrap(peripheral.services) {
            waitFor("Characteristics discovered") { discovered in
                peripheralDelegate.didDiscoverCharacteristics = { _, _, _ in discovered.fulfill() }
                peripheral.discoverCharacteristics(nil, for: service)
            }
            for characteristic in service.characteristics ?? [] where characteristic.uuid == TestDevice.readChar {
                waitFor("Descriptors discovered") { discovered in
                    peripheralDelegate.didDiscoverDescriptors = { _, _, _ in discovered.fulfill() }
                    peripheral.discoverDescriptors(for: characteristic)
                }
            }
        }
        peripheralDelegate.didDiscoverServices = nil
        peripheralDelegate.didDiscoverCharacteristics = nil
        peripheralDelegate.didDiscoverDescriptors = nil
        return peripheral
    }

    func characteristic(_ uuid: CBMUUID, of peripheral: CBMPeripheral) throws -> CBMCharacteristic {
        let characteristic = peripheral.services?
            .flatMap { $0.characteristics ?? [] }
            .first { $0.uuid == uuid }
        return try XCTUnwrap(characteristic, "Characteristic \(uuid) not discovered")
    }

    // MARK: Waiting

    /// Waits for an expectation, which is passed to the `body`. The body is expected
    /// to set up a handler that fulfills it, and to trigger the action.
    func waitFor(_ description: String,
                 timeout: TimeInterval = 2.0,
                 inverted: Bool = false,
                 _ body: (XCTestExpectation) -> Void) {
        let expectation = XCTestExpectation(description: description)
        expectation.isInverted = inverted
        body(expectation)
        wait(for: [expectation], timeout: timeout)
    }

    /// Lets the run loop spin for the given time.
    func pause(_ interval: TimeInterval) {
        waitFor("Pause", timeout: interval, inverted: true) { _ in }
    }

    /// Marks a test as a known deviation from the native behavior.
    ///
    /// Remove the call once the issue is fixed. Set the `TEST_RUNNER_RUN_KNOWN_ISSUES`
    /// environment variable to run such tests anyway.
    func skipKnownIssue(_ issue: String) throws {
        if ProcessInfo.processInfo.environment["RUN_KNOWN_ISSUES"] == nil {
            throw XCTSkip("Known issue: \(issue)")
        }
    }
}
