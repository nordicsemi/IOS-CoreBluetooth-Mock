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

import Foundation
import Combine

// MARK: - Blinky

public class Blinky {
    
    // MARK: Private Properties
    
    private let name: String
    private var ledEnabled: Bool
    private var buttonPressed: Bool
    private var recurringTimer: Bool
    
    private var ledData: Data {
        return ledEnabled ? Data([0x01]) : Data([0x00])
    }
    private var buttonData: Data {
        return buttonPressed ? Data([0x01]) : Data([0x00])
    }
    
    // MARK: init
    
    public init(name: String = "Nordic_Blinky") {
        self.ledEnabled = false
        self.buttonPressed = false
        self.recurringTimer = false
        self.name = name
    }
    
    public private(set) lazy var spec = CBMPeripheralSpec
        .simulatePeripheral(proximity: .immediate)
        .advertising(
            advertisementData: [
                CBMAdvertisementDataIsConnectable : true as NSNumber,
                CBMAdvertisementDataLocalNameKey : name,
                CBMAdvertisementDataServiceUUIDsKey : [CBMUUID.blinkyService]
            ],
            withInterval: 2.0,
            delay: 5.0,
            alsoWhenConnected: false
        )
        .connectable(
            name: name,
            services: [.blinkyService],
            delegate: self,
            connectionInterval: 0.02,
        )
        .build()
}

// MARK: - CBMPeripheralSpecDelegate

extension Blinky: CBMPeripheralSpecDelegate {
    
    public func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveReadRequestFor characteristic: CBMCharacteristicMock) -> Result<Data, Error> {
        switch characteristic.uuid {
        case .buttonCharacteristic:
            return .success(buttonData)
        case .ledCharacteristic:
            return .success(ledData)
        default:
            return .failure(CBMATTError(.readNotPermitted))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                           didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
                           data: Data) -> Result<Void, Error> {
        switch characteristic.uuid {
        case .ledCharacteristic:
            ledEnabled = data[0] != 0x00
            return .success(())
        default:
            return .failure(CBMATTError(.writeNotPermitted))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveSetNotifyRequest enabled: Bool, for characteristic: CBMCharacteristicMock) -> Result<Void, Error> {
        switch characteristic.uuid {
        case .buttonCharacteristic:
            updateSimulation(peripheral, characteristic: characteristic, enabled: enabled)
            return .success(())
        default:
            return .failure(CBMATTError(.requestNotSupported))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec, didDisconnect error: (any Error)?) {
        reset()
    }
    
    public func reset() {
        ledEnabled = false
        buttonPressed = false
        recurringTimer = false
    }
}

// MARK: Private

private extension Blinky {
    
    func updateSimulation(_ peripheral: CBMPeripheralSpec, characteristic: CBMCharacteristicMock, enabled: Bool) {
        recurringTimer = enabled
        guard enabled else { return }
        enqueueSimulatedButtonPress(peripheral, characteristic: characteristic)
    }
    
    func enqueueSimulatedButtonPress(_ peripheral: CBMPeripheralSpec, characteristic: CBMCharacteristicMock) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, recurringTimer else { return }
            buttonPressed = !buttonPressed
            peripheral.simulateValueUpdate(buttonData, for: characteristic)
            enqueueSimulatedButtonPress(peripheral, characteristic: characteristic)
        }
    }
}

// MARK: - CoreBluetoothMock

private extension CBMUUID {
    static let blinkyService: CBMUUID! = CBMUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")
    
    static let buttonCharacteristic: CBMUUID! = CBMUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")
    static let ledCharacteristic: CBMUUID! = CBMUUID(string: "00001525-1212-EFDE-1523-785FEABCD123")
}

private extension CBMServiceMock {
    
    static let blinkyService = CBMServiceMock(
        type: .blinkyService,
        primary: true,
        characteristics: .buttonCharacteristic, .ledCharacteristic
    )
}

private extension CBMCharacteristicMock {
    
    static let buttonCharacteristic = CBMCharacteristicMock(
        type: .buttonCharacteristic,
        properties: [.notify, .read],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )

    static let ledCharacteristic = CBMCharacteristicMock(
        type: .ledCharacteristic,
        properties: [.write, .read]
    )
}
