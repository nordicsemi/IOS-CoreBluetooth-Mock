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

/// Tests of the peripheral object: discovery, reading, writing and notifications.
///
/// Expectations in these tests follow the behavior of the native `CBPeripheral`.
class PeripheralBehaviorTest: CentralBehaviorTestCase {

    // MARK: - Discovery

    func testServicesAreNilBeforeDiscovery() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        XCTAssertNil(peripheral.services)
    }

    func testDiscoverAllServices() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { discoveredPeripheral, error in
                XCTAssertTrue(discoveredPeripheral === peripheral)
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverServices(nil)
        }
        let uuids = peripheral.services?.map { $0.uuid }
        XCTAssertEqual(uuids, [TestDevice.serviceA, TestDevice.serviceB])
        XCTAssertEqual(peripheral.services?.first?.isPrimary, true)
        // Characteristics are not discovered automatically.
        XCTAssertNil(peripheral.services?.first?.characteristics)
    }

    func testServicesAreNotAvailableUntilDiscoveryCompletes() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
            XCTAssertNil(peripheral.services)
        }
        XCTAssertNotNil(peripheral.services)
    }

    func testDiscoverFilteredServices() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices([TestDevice.serviceB])
        }
        XCTAssertEqual(peripheral.services?.map { $0.uuid }, [TestDevice.serviceB])
    }

    func testDiscoveringServicesTwiceDoesNotDuplicateThem() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        for _ in 0..<2 {
            waitFor("Services discovered") { discovered in
                peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
                peripheral.discoverServices(nil)
            }
        }
        XCTAssertEqual(peripheral.services?.count, 2)
    }

    func testServiceDiscoveryError() throws {
        setUpManager()
        device.discoveryResult = .failure(CBMATTError(.insufficientAuthentication))
        let peripheral = try connectToDevice()

        waitFor("Discovery failed") { failed in
            peripheralDelegate.didDiscoverServices = { _, error in
                XCTAssertEqual((error as? CBMATTError)?.code, .insufficientAuthentication)
                failed.fulfill()
            }
            peripheral.discoverServices(nil)
        }
        XCTAssertTrue(peripheral.services?.isEmpty ?? true)
    }

    func testDiscoveryIsIgnoredWhenNotConnected() throws {
        setUpManager()
        let peripheral = try retrieveDevice()
        peripheral.delegate = peripheralDelegate

        waitFor("Nothing reported", timeout: 0.3, inverted: true) { reported in
            peripheralDelegate.didDiscoverServices = { _, _ in reported.fulfill() }
            peripheral.discoverServices(nil)
        }
        XCTAssertNil(peripheral.services)
    }

    func testDiscoverCharacteristics() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
        }
        let service = try XCTUnwrap(peripheral.services?.first)

        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { _, discoveredService, error in
                XCTAssertTrue(discoveredService === service)
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
        let characteristics = try XCTUnwrap(service.characteristics)
        XCTAssertEqual(characteristics.map { $0.uuid },
                       [TestDevice.readChar, TestDevice.writeChar, TestDevice.notifyChar])
        XCTAssertEqual(characteristics[0].properties, [.read])
        XCTAssertEqual(characteristics[1].properties, [.write, .writeWithoutResponse])
        XCTAssertEqual(characteristics[2].properties, [.notify, .read])
        // Values and descriptors are not known until read or discovered.
        XCTAssertTrue(characteristics.allSatisfy { $0.value == nil })
        XCTAssertTrue(characteristics.allSatisfy { $0.descriptors == nil })
        XCTAssertTrue(characteristics.allSatisfy { !$0.isNotifying })
    }

    func testCharacteristicsAreNotAvailableUntilDiscoveryCompletes() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
        }
        let service = try XCTUnwrap(peripheral.services?.first)

        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { _, _, _ in discovered.fulfill() }
            peripheral.discoverCharacteristics(nil, for: service)
            XCTAssertNil(service.characteristics)
        }
        XCTAssertEqual(service.characteristics?.count, 3)
    }

    func testCharacteristicsAreNotSetWhenDiscoveryFails() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
        }
        let service = try XCTUnwrap(peripheral.services?.first)
        device.discoveryResult = .failure(CBMATTError(.insufficientAuthentication))

        waitFor("Discovery failed") { failed in
            peripheralDelegate.didDiscoverCharacteristics = { _, _, error in
                XCTAssertNotNil(error)
                failed.fulfill()
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
        XCTAssertNil(service.characteristics)
    }

    func testDescriptorsAreNotAvailableUntilDiscoveryCompletes() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        XCTAssertNil(characteristic.descriptors)

        waitFor("Descriptors discovered") { discovered in
            peripheralDelegate.didDiscoverDescriptors = { _, _, _ in discovered.fulfill() }
            peripheral.discoverDescriptors(for: characteristic)
            XCTAssertNil(characteristic.descriptors)
        }
        XCTAssertEqual(characteristic.descriptors?.count, 1)
    }

    func testDiscoverFilteredCharacteristics() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices(nil)
        }
        let service = try XCTUnwrap(peripheral.services?.first)

        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { _, _, _ in discovered.fulfill() }
            peripheral.discoverCharacteristics([TestDevice.writeChar], for: service)
        }
        XCTAssertEqual(service.characteristics?.map { $0.uuid }, [TestDevice.writeChar])
    }

    func testDiscoverDescriptors() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let readChar = try characteristic(TestDevice.readChar, of: peripheral)
        let notifyChar = try characteristic(TestDevice.notifyChar, of: peripheral)

        XCTAssertEqual(readChar.descriptors?.map { $0.uuid }, [TestDevice.userDescription])
        // Descriptors were not discovered for this characteristic.
        XCTAssertNil(notifyChar.descriptors)
    }

    func testCharacteristicsOfDifferentServicesDoNotMix() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let serviceB = try XCTUnwrap(peripheral.services?.last)
        XCTAssertEqual(serviceB.characteristics?.map { $0.uuid }, [TestDevice.otherChar])
    }

    // MARK: - Reading

    func testReadCharacteristic() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)

        waitFor("Value read") { read in
            peripheralDelegate.didUpdateCharacteristicValue = { _, readCharacteristic, error in
                XCTAssertTrue(readCharacteristic === characteristic)
                XCTAssertNil(error)
                read.fulfill()
            }
            peripheral.readValue(for: characteristic)
        }
        XCTAssertEqual(characteristic.value, Data([0x01, 0x02, 0x03]))
    }

    func testReadReturnsLatestValue() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)

        for value in [Data([0x01]), Data([0x02, 0x03])] {
            device.values[TestDevice.readChar] = value
            waitFor("Value read") { read in
                peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in read.fulfill() }
                peripheral.readValue(for: characteristic)
            }
            XCTAssertEqual(characteristic.value, value)
        }
    }

    func testReadError() throws {
        setUpManager()
        device.values[TestDevice.readChar] = nil
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)

        waitFor("Read failed") { failed in
            peripheralDelegate.didUpdateCharacteristicValue = { _, _, error in
                XCTAssertEqual((error as? CBMATTError)?.code, .readNotPermitted)
                failed.fulfill()
            }
            peripheral.readValue(for: characteristic)
        }
        XCTAssertNil(characteristic.value)
    }

    func testReadIsIgnoredWhenNotConnected() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
        }

        waitFor("Nothing reported", timeout: 0.3, inverted: true) { reported in
            peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in reported.fulfill() }
            peripheral.readValue(for: characteristic)
        }
    }

    func testReadDescriptor() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)
        let descriptor = try XCTUnwrap(characteristic.descriptors?.first)

        waitFor("Descriptor read") { read in
            peripheralDelegate.didUpdateDescriptorValue = { _, readDescriptor, error in
                XCTAssertTrue(readDescriptor === descriptor)
                XCTAssertNil(error)
                read.fulfill()
            }
            peripheral.readValue(for: descriptor)
        }
        XCTAssertEqual((descriptor.value as? Data), Data("description".utf8))
    }

    func testReadRSSI() throws {
        setUpManager(proximity: .near)
        let peripheral = try connectToDevice()

        waitFor("RSSI read") { read in
            peripheralDelegate.didReadRSSI = { _, rssi, error in
                XCTAssertNil(error)
                XCTAssertEqual(rssi.intValue, -70)
                read.fulfill()
            }
            peripheral.readRSSI()
        }
    }

    // MARK: - Writing

    func testWriteWithResponse() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)

        waitFor("Value written") { written in
            peripheralDelegate.didWriteCharacteristicValue = { _, writtenCharacteristic, error in
                XCTAssertTrue(writtenCharacteristic === characteristic)
                XCTAssertNil(error)
                written.fulfill()
            }
            peripheral.writeValue(Data([0xAA, 0xBB]), for: characteristic, type: .withResponse)
        }
        XCTAssertEqual(device.writes.count, 1)
        XCTAssertEqual(device.writes.first?.uuid, TestDevice.writeChar)
        XCTAssertEqual(device.writes.first?.data, Data([0xAA, 0xBB]))
    }

    func testWriteWithResponseError() throws {
        setUpManager()
        device.writeResult = .failure(CBMATTError(.invalidAttributeValueLength))
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)

        waitFor("Write failed") { failed in
            peripheralDelegate.didWriteCharacteristicValue = { _, _, error in
                XCTAssertEqual((error as? CBMATTError)?.code, .invalidAttributeValueLength)
                failed.fulfill()
            }
            peripheral.writeValue(Data([0x01]), for: characteristic, type: .withResponse)
        }
    }

    func testWritesAreDeliveredInOrder() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)

        var responses = 0
        waitFor("All values written") { written in
            peripheralDelegate.didWriteCharacteristicValue = { _, _, _ in
                responses += 1
                if responses == 3 { written.fulfill() }
            }
            for i in 1...3 {
                peripheral.writeValue(Data([UInt8(i)]), for: characteristic, type: .withResponse)
            }
        }
        XCTAssertEqual(device.writes.map { $0.data }, [Data([1]), Data([2]), Data([3])])
    }

    func testWriteWithoutResponse() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)

        waitFor("No write response", timeout: 0.3, inverted: true) { written in
            peripheralDelegate.didWriteCharacteristicValue = { _, _, _ in written.fulfill() }
            peripheral.writeValue(Data([0x12, 0x34]), for: characteristic, type: .withoutResponse)
        }
        XCTAssertEqual(device.commands.count, 1)
        XCTAssertEqual(device.commands.first?.data, Data([0x12, 0x34]))
        XCTAssertTrue(device.writes.isEmpty)
    }

    func testReadyToSendWriteWithoutResponse() throws {
        guard #available(iOS 11.0, *) else { throw XCTSkip("Requires iOS 11") }
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)

        waitFor("Ready to send") { ready in
            peripheralDelegate.isReadyToSendWriteWithoutResponse = { _ in ready.fulfill() }
            peripheral.writeValue(Data([0x01]), for: characteristic, type: .withoutResponse)
            XCTAssertFalse(peripheral.canSendWriteWithoutResponse)
        }
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)
    }

    func testCanNotSendWriteWithoutResponseWhenDisconnected() throws {
        guard #available(iOS 11.0, *) else { throw XCTSkip("Requires iOS 11") }
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
        }
        XCTAssertFalse(peripheral.canSendWriteWithoutResponse)
    }

    func testWritesWithoutResponseAreLimitedByTheBuffer() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.writeChar, of: peripheral)

        // Without waiting for `peripheralIsReady(toSendWriteWithoutResponse:)`
        // only a limited number of commands may be sent.
        for i in 0..<50 {
            peripheral.writeValue(Data([UInt8(i)]), for: characteristic, type: .withoutResponse)
        }
        pause(0.3)
        XCTAssertLessThanOrEqual(device.commands.count, 20)
    }

    func testMaximumWriteValueLength() throws {
        guard #available(iOS 9.0, *) else { throw XCTSkip("Requires iOS 9") }
        setUpManager(mtu: 247)
        let peripheral = try connectToDevice()
        XCTAssertEqual(peripheral.maximumWriteValueLength(for: .withResponse), 512)
        XCTAssertEqual(peripheral.maximumWriteValueLength(for: .withoutResponse), 244)
    }

    func testMaximumWriteValueLengthWithDefaultMTU() throws {
        guard #available(iOS 9.0, *) else { throw XCTSkip("Requires iOS 9") }
        setUpManager()
        let peripheral = try connectToDevice()
        XCTAssertEqual(peripheral.maximumWriteValueLength(for: .withoutResponse), 20)
    }

    func testWriteDescriptorError() throws {
        setUpManager()
        device.descriptorWriteResult = .failure(CBMATTError(.writeNotPermitted))
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)
        let descriptor = try XCTUnwrap(characteristic.descriptors?.first)

        waitFor("Write failed") { failed in
            peripheralDelegate.didWriteDescriptorValue = { _, _, error in
                XCTAssertEqual((error as? CBMATTError)?.code, .writeNotPermitted)
                failed.fulfill()
            }
            peripheral.writeValue(Data([0x01]), for: descriptor)
        }
    }

    // MARK: - Notifications

    func testEnableNotifications() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        XCTAssertFalse(characteristic.isNotifying)

        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, updatedCharacteristic, error in
                XCTAssertTrue(updatedCharacteristic === characteristic)
                XCTAssertNil(error)
                XCTAssertTrue(updatedCharacteristic.isNotifying)
                enabled.fulfill()
            }
            peripheral.setNotifyValue(true, for: characteristic)
            // The state changes after the device confirms it.
            XCTAssertFalse(characteristic.isNotifying)
        }
        XCTAssertEqual(device.notifyRequests.map { $0.enabled }, [true])
    }

    func testNotificationsAreDelivered() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            peripheral.setNotifyValue(true, for: characteristic)
        }

        var received: [Data] = []
        waitFor("Notifications received") { done in
            peripheralDelegate.didUpdateCharacteristicValue = { _, updatedCharacteristic, error in
                XCTAssertTrue(updatedCharacteristic === characteristic)
                XCTAssertNil(error)
                received.append(updatedCharacteristic.value ?? Data())
                if received.count == 3 { done.fulfill() }
            }
            for i in 1...3 {
                device.spec.simulateValueUpdate(Data([UInt8(i)]), for: device.notifyCharacteristic)
            }
        }
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(characteristic.value, received.last)
    }

    func testNotificationsAreNotDeliveredWhenDisabled() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)

        waitFor("Notification not received", timeout: 0.3, inverted: true) { received in
            peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in received.fulfill() }
            device.spec.simulateValueUpdate(Data([0x01]), for: device.notifyCharacteristic)
        }
        XCTAssertNil(characteristic.value)
    }

    func testDisableNotifications() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            peripheral.setNotifyValue(true, for: characteristic)
        }

        waitFor("Notifications disabled") { disabled in
            peripheralDelegate.didUpdateNotificationState = { _, updatedCharacteristic, _ in
                XCTAssertFalse(updatedCharacteristic.isNotifying)
                disabled.fulfill()
            }
            peripheral.setNotifyValue(false, for: characteristic)
        }
        XCTAssertEqual(device.notifyRequests.map { $0.enabled }, [true, false])

        waitFor("Notification not received", timeout: 0.3, inverted: true) { received in
            peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in received.fulfill() }
            device.spec.simulateValueUpdate(Data([0x01]), for: device.notifyCharacteristic)
        }
    }

    func testEnablingNotificationsTwiceIsReportedWithoutReachingTheDevice() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            peripheral.setNotifyValue(true, for: characteristic)
        }

        waitFor("Notification state reported") { reported in
            peripheralDelegate.didUpdateNotificationState = { _, _, error in
                XCTAssertNil(error)
                reported.fulfill()
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }
        XCTAssertEqual(device.notifyRequests.count, 1)
    }

    func testEnablingNotificationsOnCharacteristicWithoutNotifyProperty() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        let characteristic = try characteristic(TestDevice.readChar, of: peripheral)

        waitFor("Notification state reported") { reported in
            peripheralDelegate.didUpdateNotificationState = { _, _, error in
                XCTAssertNotNil(error)
                reported.fulfill()
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }
        XCTAssertFalse(characteristic.isNotifying)
    }

    func testNotificationsAreNotRestoredAfterReconnection() throws {
        setUpManager()
        var peripheral = try connectAndDiscover()
        var characteristic = try characteristic(TestDevice.notifyChar, of: peripheral)
        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, _, _ in enabled.fulfill() }
            peripheral.setNotifyValue(true, for: characteristic)
        }
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            device.spec.simulateDisconnection()
        }

        peripheral = try connectAndDiscover()
        characteristic = try self.characteristic(TestDevice.notifyChar, of: peripheral)
        XCTAssertFalse(characteristic.isNotifying)
        waitFor("Notification not received", timeout: 0.3, inverted: true) { received in
            peripheralDelegate.didUpdateCharacteristicValue = { _, _, _ in received.fulfill() }
            device.spec.simulateValueUpdate(Data([0x01]), for: device.notifyCharacteristic)
        }
    }

    // MARK: - Delegate

    func testPeripheralDelegateIsWeak() throws {
        setUpManager()
        let peripheral = try retrieveDevice()

        autoreleasepool {
            peripheral.delegate = CBMPeripheralDelegateProxy()
        }
        XCTAssertNil(peripheral.delegate)
    }
}
