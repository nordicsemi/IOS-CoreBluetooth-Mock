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

/// This test simulates a scenario when a device failed to connect for some reason.
///
/// It is using the app and testing it by sending notifications that trigger different
/// actions.
class FailedConnectionTest: XCTestCase {

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

    func testScanningBlinky() {
        // Set up the devices in range.
        blinky.simulateProximityChange(.immediate)
        hrm.simulateProximityChange(.near)
        thingy.simulateProximityChange(.far)
        // Reset the blinky.
        blinky.simulateReset()

        // Wait until the blinky is found.
        var target: BlinkyPeripheral?
        let found = XCTestExpectation(description: "Device found")
        Sim.onBlinkyDiscovery { blinky in
            XCTAssertEqual(blinky.advertisedName, "nRF Blinky")
            XCTAssert(blinky.isConnectable == true)
            XCTAssert(blinky.isConnected == false)
            XCTAssertGreaterThanOrEqual(blinky.RSSI.intValue, -40 - 15)
            XCTAssertLessThanOrEqual(blinky.RSSI.intValue, -40 + 15)
            target = blinky
            found.fulfill()
        }
        wait(for: [found], timeout: 3)
        XCTAssertNotNil(target, "nRF Blinky not found. Make sure you run the test on a simulator.")
        if target == nil {
            // Going further would cause a crash.
            return
        }
        
        // Let's move Blinky out of range.
        blinky.simulateProximityChange(.outOfRange)
        
        // Select found device.
        Sim.post(.selectPeripheral(target!))

        // As the device is now out of range, connection should fail.
        let connected = XCTestExpectation(description: "Connected")
        connected.isInverted = true
        let connectionObserver = target!.onConnected {
            connected.fulfill() // This should not happen.
        }
        // As the expectation is inverted, the wait should timeout.
        wait(for: [connected], timeout: 3)
        Sim.dispose(connectionObserver)

        let windowScene = UIApplication.shared.connectedScenes.first as! UIWindowScene
        let navigationController = windowScene.windows.first!.rootViewController as! UINavigationController
        navigationController.popViewController(animated: true)
    }
}
