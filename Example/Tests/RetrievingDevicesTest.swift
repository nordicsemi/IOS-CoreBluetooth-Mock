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


import XCTest
@testable import nRF_Blinky
@testable import CoreBluetoothMock

class RetrievingDevicesTest: XCTestCase {
    
    override func setUpWithError() throws {	
        // This method is called AFTER ScannerTableViewController.viewDidLoad()
        // where the BlinkyManager is instantiated. A separate mock manager
        // is not created in this test.
        // Initially mock Bluetooth adapter is powered Off.
        CBMCentralManagerMock.simulatePeripherals([blinky, hrm, thingy])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
    }

    override func tearDownWithError() throws {
        // We can't call CBMCentralManagerMock.tearDownSimulation() here.
        // That would invalidate the BlinkyManager in ScannerTableViewController.
        // The central manager must be reused, so let's just power mock off,
        // which will allow us to set different set of peripherals in another test.
        CBMCentralManagerMock.simulatePowerOff()
    }

    func testRetrieval() throws {
        // Devices might have been scanned and cached by some other test.
        // Make sure they're treated as new devices by changing their addresses.
        blinky.simulateMacChange()
        hrm.simulateMacChange()
        
        let managerPoweredOn = XCTestExpectation(description: "Powered On")
        
        // Define the CBCentralManagerDelegate, which will wait until the manager is ready.
        let delegate = CBMCentralManagerDelegateProxy()
        delegate.didUpdateState = { _ in managerPoweredOn.fulfill() }
        
        // Create an instance of mock CBMCentralManager.
        let manager = CBMCentralManagerMock(delegate: delegate, queue: nil)
        
        // Wait until the manager is initialized.
        wait(for: [managerPoweredOn], timeout: 1.0)
        
        // Initially, none of the devices should be retrievable, as they have not been scanned.
        let list1 = manager.retrievePeripherals(withIdentifiers: [blinky.identifier, hrm.identifier])
        XCTAssertTrue(list1.isEmpty)
        
        // Simulate a situation when a different app on the iPhone scanned the Blinky device
        // causing it to be cached.
        //
        // Note: This should also work when the device is out of range, as undefined time can pass
        //       between retrievals, so it could have been close for a moment, and taken away again.
        blinky.simulateCaching()
        
        // Now the Blinky should be available for retrieval.
        let list2 = manager.retrievePeripherals(withIdentifiers: [blinky.identifier, hrm.identifier])
        XCTAssertEqual(list2.count, 1)
        XCTAssert(list2.contains(where: { $0.identifier == blinky.identifier }))
    }
    
    func testRetrievalAfterScanning() throws {
        // Set up the devices in range.
        thingy.simulateMacChange()
        thingy.simulateProximityChange(.immediate)
        
        let managerPoweredOn = XCTestExpectation(description: "Powered On")
        let thingyFound = XCTestExpectation(description: "Found")
        let thingyRetrieved = XCTestExpectation(description: "Retrieved")
        
        // Define the CBCentralManagerDelegate, which will wait until the manager is ready
        // and will check the successful retrieval.
        let delegate = CBMCentralManagerDelegateProxy()
        delegate.didUpdateState = { _ in managerPoweredOn.fulfill() }
        delegate.didDiscoverPeripheral = { manager, peripheral, _, _ in
            guard peripheral.identifier == thingy.identifier else { return }
            thingyFound.fulfill()
            
            // Now it should be available for retrieval.
            let list = manager.retrievePeripherals(withIdentifiers: [thingy.identifier])
            XCTAssertFalse(list.isEmpty)
            
            if !list.isEmpty {
                thingyRetrieved.fulfill()
            }
        }
        
        // Create an instance of a mock CBMCentralManager.
        let manager = CBMCentralManagerMock(delegate: delegate, queue: nil)
        
        // Wait until the manager is initialized.
        wait(for: [managerPoweredOn], timeout: 1.0)
        
        // Initially, none of the devices should be retrievable, as they have not been scanned.
        let list = manager.retrievePeripherals(withIdentifiers: [thingy.identifier])
        XCTAssertTrue(list.isEmpty)
        
        // Start scanning for any device.
        manager.scanForPeripherals(withServices: nil)
        
        // Wait until the device is found and could be retrieved.
        wait(for: [thingyFound, thingyRetrieved], timeout: 1.0)
    }
    
    func testRetrievalConnected() throws {
        let hrmServiceUUID = CBMUUID(string: "180D")
        
        // Set up the devices in range.
        hrm.simulateMacChange()
        hrm.simulateProximityChange(.near)
        blinky.simulateProximityChange(.immediate)
        thingy.simulateProximityChange(.far)
        
        let managerPoweredOn = XCTestExpectation(description: "Powered On")
        let hrmFound = XCTestExpectation(description: "Found")
        let otherFound = XCTestExpectation(description: "Other found")
        otherFound.isInverted = true
        let hrmRetrieved = XCTestExpectation(description: "Retrieved after service discovery")
        let hrmNotRetrieved = XCTestExpectation(description: "Not retrieved as not connected")
        let hrmStillNotRetrieved = XCTestExpectation(description: "Not retrieved as services not discovered")
        
        // Create an instance of a mock CBMCentralManager.
        let manager = CBMCentralManagerMock()
        
        // Define the CBMPeripheralDelegate, which will wait until the serivces are
        // discovered and will try to retrieve the device.
        let peripheralDelegate = CBMPeripheralDelegateProxy()
        // Captured weakly: `manager` -> peripheral -> peripheralDelegate -> this closure
        // would otherwise be a retain cycle, leaking the manager into later tests.
        peripheralDelegate.didDiscoverServices = { [weak manager] peripheral, error in
            XCTAssertNil(error)
            
            // HRM device should now be connected and retrievable.
            let list = manager?.retrieveConnectedPeripherals(withServices: [hrmServiceUUID]) ?? []
            XCTAssertFalse(list.isEmpty)
            
            if !list.isEmpty {
                hrmRetrieved.fulfill()
            }
        }
        
        // Define the CBCentralManagerDelegate, which will wait until the manager is ready
        // and will check the successful retrieval.
        let delegate = CBMCentralManagerDelegateProxy()
        delegate.didUpdateState = { _ in managerPoweredOn.fulfill() }
        delegate.didDiscoverPeripheral = { manager, peripheral, _, _ in
            guard peripheral.identifier == hrm.identifier else {
                otherFound.fulfill()
                return
            }
            hrmFound.fulfill()
            
            // HRM device should still not be connected and retrievable.
            let list = manager.retrieveConnectedPeripherals(withServices: [hrmServiceUUID])
            XCTAssertTrue(list.isEmpty)
            
            if list.isEmpty {
                hrmNotRetrieved.fulfill()
            }
            
            // Connect to the device when found.
            peripheral.delegate = peripheralDelegate
            manager.connect(peripheral)
        }
        delegate.didConnect = { manager, peripheral in
            // HRM device should still not be connected and retrievable.
            let list = manager.retrieveConnectedPeripherals(withServices: [hrmServiceUUID])
            XCTAssertTrue(list.isEmpty)
            
            if list.isEmpty {
                hrmStillNotRetrieved.fulfill()
            }
            
            // Discover services.
            peripheral.discoverServices([hrmServiceUUID])
        }
        manager.delegate = delegate
        
        // Wait until the manager is initialized.
        wait(for: [managerPoweredOn], timeout: 1.0)
        
        // Initially, none of the devices should be retrievable, as they have not been scanned.
        let list = manager.retrieveConnectedPeripherals(withServices: [hrmServiceUUID])
        XCTAssertTrue(list.isEmpty)
        
        // Scan only for HRM device. Other devices may also be in range.
        manager.scanForPeripherals(withServices: [hrmServiceUUID])
        
        wait(for: [
                hrmFound, otherFound,
                hrmNotRetrieved, hrmStillNotRetrieved, hrmRetrieved
             ],
             timeout: 4.0)
    }

}
