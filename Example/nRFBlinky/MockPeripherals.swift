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
import CoreBluetoothMock

// MARK: - Mock nRF Blinky

/// A wrapper around the Blinky peripheral spec, that allows simulating button clicks
/// or providing high-level behavior.
///
/// This is how you may simulate Button click using a mock Blinky:
///
/// ```swift
/// blinkyImpl.simulateButtonToggle()
/// ```
private let blinkyImpl = Blinky(
//    identifier: UUID(),
//    name: "Nordic_Blinky",
//    proximity: .immediate,
//    delegate: PeriodicBlinkyDelegate(
//        releasedDuration: 2,
//        pressedDuration: 0.5,
//    )
)

/// The *Blinky* spec peripheral is used for mock Central Manager.
///
/// This is how you may simulate Button click using a mock Blinky:
///
/// ```swift
/// blinky.simulateValueUpdate(Data([0x01]), for: .buttonCharacteristic)
/// ```
let blinky = blinkyImpl.spec

// MARK: - Mock Nordic HRM

extension CBMServiceMock {
    
    static let hrmService = CBMServiceMock(
        type: CBMUUID(string: "180D"), primary: true,
        characteristics:
            CBMCharacteristicMock(
                type: CBMUUID(string: "2A37"), // Heart Rate Measurement
                properties: [.notify],
                descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
            ),
            CBMCharacteristicMock(
                type: CBMUUID(string: "2A38"), // Body Sensor Location
                properties: [.read]
            )
    )
    
}

private struct DummyCBMPeripheralSpecDelegate: CBMPeripheralSpecDelegate {
    // Let's use default implementation.
    // The HRM will not show up in the scan result, as it
    // doesn't advertise with Nordic LED Button service.
    // If you uncomment the line below, and try to connect,
    // connection will fail on "Device not supported" error.
}

let hrm = CBMPeripheralSpec
    .simulatePeripheral(proximity: .outOfRange)
    .advertising(
        advertisementData: [
            CBMAdvertisementDataLocalNameKey : "NordicHRM",
            CBMAdvertisementDataServiceUUIDsKey : [
                CBMUUID(string: "180D"), // Heart Rate
                CBMUUID(string: "180A"), // Device Information
                // BlinkyPeripheral.nordicBlinkyServiceUUID // <- this line
            ],
            CBMAdvertisementDataIsConnectable : true as NSNumber
        ],
        withInterval: 0.100)
    .connectable(
        name: "NordicHRM",
        services: [.hrmService],
        delegate: DummyCBMPeripheralSpecDelegate(),
        connectionInterval: 0.250,
        mtu: 251)
    .build()

// MARK: - Physical Web Beacon

let thingy = CBMPeripheralSpec
    .simulatePeripheral(proximity: .outOfRange)
    .advertising(
        advertisementData: [
            CBMAdvertisementDataServiceUUIDsKey : [
                CBMUUID(string: "FEAA")  // Eddystone
            ],
            CBMAdvertisementDataServiceDataKey : [
                // Physical Web beacon: 10ee03676f2e676c2f7049576466972
                // type: URL
                // TX Power: -18 dBm
                // URL: https://goo.gl/pIWdir -> Thingy:52
                CBMUUID(string: "FEAA") : Data(base64Encoded: "EO4DZ28uZ2wvcElXZGaXIA==")
            ]
        ],
        withInterval: 0.250,
        alsoWhenConnected: true)
    .advertising(
        advertisementData: [
            CBMAdvertisementDataServiceUUIDsKey : [
                CBMUUID(string: "EF680100-9B35-4933-9B10-52FFA9740042")],
            CBMAdvertisementDataIsConnectable : true as NSNumber,
            CBMAdvertisementDataManufacturerDataKey : Data([0x59, 0x00, 0x5E, 0x91, 0xD9, 0xC3]),
            CBMAdvertisementDataLocalNameKey : "Thingy:52",
        ],
        withInterval: 0.100,
        delay: 2.0)
    .build()

// MARK: - A device with 2 batteries

extension CBMUUID {
    static let batteryService             = CBMUUID(string: "180F")
    static let batteryLevelCharacteristic = CBMUUID(string: "2A19")
    static let characteristicUserDesr     = CBMUUID(string: "2901")
}

// The mocked Power Pack device has 2 batteries: primary and secondary.
// Battery Service specification allows only one Battery Level
// characteristic in each service, therefore below we define
// two Battery Services, one for each battery.
//
// The service instance cannot be reused, as each has its own unique
// identifier, that is used to distinguish them.

extension CBMCharacteristicMock {
    
    static let primaryBatteryLevelCharacteristic = CBMCharacteristicMock(
        type: .batteryLevelCharacteristic,
        properties: [.notify, .read],
        descriptors: CBMDescriptorMock(type: .characteristicUserDesr)
    )
    
    static let secondaryBatteryLevelCharacteristic = CBMCharacteristicMock(
        type: .batteryLevelCharacteristic,
        properties: [.notify, .read],
        descriptors: CBMDescriptorMock(type: .characteristicUserDesr)
    )
    
}

extension CBMServiceMock {

    static let primaryBatteryService = CBMServiceMock(
        type: .batteryService, primary: true,
        characteristics: .primaryBatteryLevelCharacteristic
    )
    
    static let secondaryBatteryService = CBMServiceMock(
        type: .batteryService, primary: true,
        characteristics: .secondaryBatteryLevelCharacteristic
    )
    
}

private class PowerPackCBMPeripheralSpecDelegate: CBMPeripheralSpecDelegate {
    private var primaryBatteryLevel: UInt8 = 75
    private var secondaryBatteryLevel: UInt8 = 100
    
    private var primaryBatteryLevelData: Data {
        return Data([primaryBatteryLevel])
    }
    
    private var secondaryBatteryLevelData: Data {
        return Data([secondaryBatteryLevel])
    }
    
    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveReadRequestFor characteristic: CBMCharacteristicMock)
            -> Result<Data, Error> {
        if characteristic == CBMCharacteristicMock.primaryBatteryLevelCharacteristic {
            return .success(primaryBatteryLevelData)
        }
        if characteristic == CBMCharacteristicMock.secondaryBatteryLevelCharacteristic {
            return .success(secondaryBatteryLevelData)
        }
        return .failure(CBMATTError(.invalidHandle))
    }
    
    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveReadRequestFor descriptor: CBMDescriptorMock)
            -> Result<Data, Error> {
        if descriptor.characteristic == CBMCharacteristicMock.primaryBatteryLevelCharacteristic {
            return .success("Primary".data(using: .utf8)!)
        }
        if descriptor.characteristic == CBMCharacteristicMock.secondaryBatteryLevelCharacteristic {
            return .success("Secondary".data(using: .utf8)!)
        }
        return .failure(CBMATTError(.invalidHandle))
    }
}

let powerPack = CBMPeripheralSpec
    .simulatePeripheral(proximity: .outOfRange)
    .advertising(
        advertisementData: [
            CBMAdvertisementDataLocalNameKey    : "Power Pack",
            CBMAdvertisementDataServiceUUIDsKey : [CBMUUID.batteryService],
            CBMAdvertisementDataIsConnectable   : true as NSNumber
        ],
        withInterval: 0.250)
    .connectable(
        name: "Power Pack",
        services: [
            .primaryBatteryService,
            .secondaryBatteryService,
        ],
        delegate: PowerPackCBMPeripheralSpecDelegate(),
        connectionInterval: 0.045,
        mtu: 186)
    .build()
