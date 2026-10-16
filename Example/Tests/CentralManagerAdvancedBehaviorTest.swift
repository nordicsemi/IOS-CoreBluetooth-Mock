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

/// Tests of scenarios with multiple central managers, state restoration,
/// descriptors and retrieving peripherals.
///
/// Expectations in these tests follow the behavior of the native `CBCentralManager`.
class CentralManagerAdvancedBehaviorTest: CentralBehaviorTestCase {

    /// A second manager, with its own delegates.
    private var secondManager: CBMCentralManagerMock!
    private let secondManagerDelegate = CBMCentralManagerDelegateProxy()
    private let secondPeripheralDelegate = CBMPeripheralDelegateProxy()

    override func tearDownWithError() throws {
        CBMCentralManagerMock.simulateStateRestoration = nil
        secondManagerDelegate.didUpdateState = nil
        secondManagerDelegate.didConnect = nil
        secondManagerDelegate.didDisconnect = nil
        secondManager = nil
        try super.tearDownWithError()
    }

    private func createSecondManager() {
        waitFor("Second manager ready") { ready in
            secondManagerDelegate.didUpdateState = { _ in ready.fulfill() }
            secondManager = CBMCentralManagerMock(delegate: secondManagerDelegate, queue: nil)
        }
    }

    private func connectSecondManager() throws -> CBMPeripheral {
        let peripheral = try XCTUnwrap(
            secondManager.retrievePeripherals(withIdentifiers: [device.identifier]).first)
        peripheral.delegate = secondPeripheralDelegate
        waitFor("Connected") { connected in
            secondManagerDelegate.didConnect = { _, _ in connected.fulfill() }
            secondManager.connect(peripheral)
        }
        return peripheral
    }

    private func discoverAll(_ peripheral: CBMPeripheral, with delegate: CBMPeripheralDelegateProxy) throws {
        waitFor("Services discovered") { discovered in
            delegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices([TestDevice.serviceA])
        }
        let service = try XCTUnwrap(peripheral.services?.first)
        waitFor("Characteristics discovered") { discovered in
            delegate.didDiscoverCharacteristics = { _, _, _ in discovered.fulfill() }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    // MARK: - Multiple managers

    func testBothManagersDiscoverTheDevice() {
        setUpManager()
        createSecondManager()

        let first = expectation(description: "First manager discovered the device")
        let second = expectation(description: "Second manager discovered the device")
        managerDelegate.didDiscoverPeripheral = { _, _, _, _ in first.fulfill() }
        secondManagerDelegate.didDiscoverPeripheral = { _, _, _, _ in second.fulfill() }
        manager.scanForPeripherals(withServices: nil)
        secondManager.scanForPeripherals(withServices: nil)
        wait(for: [first, second], timeout: 2.0)
    }

    func testManagersHaveSeparatePeripheralObjects() throws {
        setUpManager()
        createSecondManager()
        let first = try retrieveDevice()
        let second = try XCTUnwrap(secondManager.retrievePeripherals(withIdentifiers: [device.identifier]).first)

        XCTAssertFalse(first === second)
        XCTAssertEqual(first.identifier, second.identifier)
    }

    func testConnectedPeripheralIsRetrievedByAnotherManager() throws {
        setUpManager()
        createSecondManager()
        let peripheral = try connectAndDiscover()

        let retrieved = secondManager.retrieveConnectedPeripherals(withServices: [TestDevice.serviceA])
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.identifier, peripheral.identifier)
        // The retrieved peripheral still has to be connected by this manager.
        XCTAssertEqual(retrieved.first?.state, .disconnected)
    }

    func testDeviceSeesOneConnectionForTwoManagers() throws {
        setUpManager()
        createSecondManager()
        let first = try connectToDevice()
        let second = try connectSecondManager()
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(device.connectionRequests, 1, "The device is connected only once")

        // The device is notified when the last manager disconnects.
        waitFor("First disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(first)
        }
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(device.disconnections, 0)

        waitFor("Second disconnected") { disconnected in
            secondManagerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            secondManager.cancelPeripheralConnection(second)
        }
        XCTAssertEqual(device.disconnections, 1)
    }

    func testDeviceDisconnectionIsReportedToBothManagers() throws {
        setUpManager()
        createSecondManager()
        let first = try connectToDevice()
        let second = try connectSecondManager()

        let firstReported = expectation(description: "First manager notified")
        let secondReported = expectation(description: "Second manager notified")
        managerDelegate.didDisconnect = { _, _, _, _, _ in firstReported.fulfill() }
        secondManagerDelegate.didDisconnect = { _, _, _, _, _ in secondReported.fulfill() }
        device.spec.simulateDisconnection()
        wait(for: [firstReported, secondReported], timeout: 2.0)

        XCTAssertEqual(first.state, .disconnected)
        XCTAssertEqual(second.state, .disconnected)
    }

    func testNotificationsAreDeliveredToEveryManagerThatEnabledThem() throws {
        setUpManager()
        createSecondManager()
        let first = try connectToDevice()
        let second = try connectSecondManager()
        try discoverAll(first, with: peripheralDelegate)
        try discoverAll(second, with: secondPeripheralDelegate)
        let firstCharacteristic = try characteristic(TestDevice.notifyChar, of: first)
        let secondCharacteristic = try characteristic(TestDevice.notifyChar, of: second)

        waitFor("First enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            first.setNotifyValue(true, for: firstCharacteristic)
        }
        // The second manager has not enabled notifications.
        let firstReceived = expectation(description: "First received")
        peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in firstReceived.fulfill() }
        let secondReceived = expectation(description: "Second not notified")
        secondReceived.isInverted = true
        secondPeripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in secondReceived.fulfill() }
        device.spec.simulateValueUpdate(Data([0x01]), for: device.notifyCharacteristic)
        wait(for: [firstReceived, secondReceived], timeout: 0.5)

        waitFor("Second enabled") { enabled in
            secondPeripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            second.setNotifyValue(true, for: secondCharacteristic)
        }
        let bothReceived = expectation(description: "Both received")
        bothReceived.expectedFulfillmentCount = 2
        peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in bothReceived.fulfill() }
        secondPeripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in bothReceived.fulfill() }
        device.spec.simulateValueUpdate(Data([0x02]), for: device.notifyCharacteristic)
        wait(for: [bothReceived], timeout: 1.0)
    }

    func testPowerOffInvalidatesEveryManager() throws {
        setUpManager()
        createSecondManager()
        let first = try connectToDevice()

        CBMCentralManagerMock.simulatePowerOff()
        pause(0.1)

        XCTAssertEqual(manager.state, .poweredOff)
        XCTAssertEqual(secondManager.state, .poweredOff)
        XCTAssertEqual(first.state, .disconnected)
    }

    // MARK: - State restoration

    func testRestoringPendingConnection() throws {
        setUpManager()
        CBMCentralManagerMock.simulateStateRestoration = { [unowned self] _ in
            [CBMCentralManagerRestoredStatePeripheralsKey: [self.device.spec!]]
        }

        var restored: [CBMPeripheral] = []
        let willRestore = expectation(description: "Will restore state")
        let secondDelegate = CBMCentralManagerDelegateProxy()
        secondDelegate.willRestoreState = { _, state in
            restored = state[CBMCentralManagerRestoredStatePeripheralsKey] as? [CBMPeripheral] ?? []
            willRestore.fulfill()
        }
        let connected = expectation(description: "Connected")
        secondDelegate.didConnect = { _, _ in connected.fulfill() }
        secondManager = CBMCentralManagerMock(delegate: secondDelegate, queue: nil,
                                              options: [CBMCentralManagerOptionRestoreIdentifierKey: "test"])
        wait(for: [willRestore], timeout: 1.0)

        XCTAssertEqual(restored.map { $0.identifier }, [device.identifier])
        // The device was not connected when the app was terminated, so the
        // connection is pending until the device is seen again.
        XCTAssertEqual(restored.first?.state, .connecting)
        wait(for: [connected], timeout: 2.0)
        XCTAssertEqual(restored.first?.state, .connected)
    }

    func testRestoringScan() {
        setUpManager()
        CBMCentralManagerMock.simulateStateRestoration = { _ in
            [CBMCentralManagerRestoredStateScanServicesKey: [TestDevice.serviceA]]
        }
        var scanServices: [CBMUUID]?
        let secondDelegate = CBMCentralManagerDelegateProxy()
        secondDelegate.willRestoreState = { _, state in
            scanServices = state[CBMCentralManagerRestoredStateScanServicesKey] as? [CBMUUID]
        }
        secondManager = CBMCentralManagerMock(delegate: secondDelegate, queue: nil,
                                              options: [CBMCentralManagerOptionRestoreIdentifierKey: "test"])

        XCTAssertEqual(scanServices, [TestDevice.serviceA])
        XCTAssertTrue(secondManager.isScanning)
    }

    func testNothingIsRestoredWithoutIdentifier() {
        setUpManager()
        CBMCentralManagerMock.simulateStateRestoration = { _ in
            XCTFail("State restoration should not be requested")
            return nil
        }
        let secondDelegate = CBMCentralManagerDelegateProxy()
        secondDelegate.willRestoreState = { _, _ in XCTFail("Nothing to restore") }
        secondManager = CBMCentralManagerMock(delegate: secondDelegate, queue: nil, options: nil)
        XCTAssertFalse(secondManager.isScanning)
    }

    // MARK: - Descriptors

    func testWriteDescriptor() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)
        let descriptor = try XCTUnwrap(characteristic.descriptors?.first)

        waitFor("Descriptor written") { written in
            peripheralDelegate.didWriteDescriptorValue = { _, writtenDescriptor, error in
                XCTAssertTrue(writtenDescriptor === descriptor)
                XCTAssertNil(error)
                written.fulfill()
            }
            peripheral.writeValue(Data("name".utf8), for: descriptor)
        }
        XCTAssertEqual(device.descriptorWrites.count, 1)
        XCTAssertEqual(device.descriptorWrites.first?.data, Data("name".utf8))
    }

    // MARK: - Retrieving

    func testRetrievedPeripheralsAreInTheRequestedOrder() throws {
        let other = TestDevice()
        setUpManager()
        CBMCentralManagerMock.simulatePowerOff()
        CBMCentralManagerMock.simulatePeripherals([device.spec, other.spec])
        CBMCentralManagerMock.simulatePowerOn()
        pause(0.1)

        let identifiers = [other.identifier, UUID(), device.identifier]
        let retrieved = manager.retrievePeripherals(withIdentifiers: identifiers)
        XCTAssertEqual(retrieved.map { $0.identifier }, [other.identifier, device.identifier])
    }

    func testRetrievingTheSamePeripheralTwiceReturnsTheSameObject() throws {
        setUpManager()
        let first = try retrieveDevice()
        let second = try retrieveDevice()
        XCTAssertTrue(first === second)
    }

    func testDiscoveredPeripheralIsTheSameAsRetrieved() throws {
        setUpManager()
        var discovered: CBMPeripheral?
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, peripheral, _, _ in
                discovered = peripheral
                found.fulfill()
            }
            manager.scanForPeripherals(withServices: nil)
        }
        XCTAssertTrue(try retrieveDevice() === discovered)
    }
}
