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

/// The possible states of a Core Bluetooth manager.
public enum CBMManagerState: Int {
    /// The manager’s state is unknown.
    case unknown
    /// A state that indicates the connection with the system service was momentarily lost.
    case resetting
    /// A state that indicates this device doesn’t support the Bluetooth low energy central or client role.
    case unsupported
    /// A state that indicates the application isn’t authorized to use the Bluetooth low energy role.
    case unauthorized
    /// A state that indicates Bluetooth is currently powered off.
    case poweredOff
    /// A state that indicates Bluetooth is currently powered on and available to use.
    case poweredOn
}

// In Xcode 12.5 the initializers of CBPeer and CBAttribute
// became private, therefore they cannot be user. A local
// counterparts have been created in the library.
// https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/issues/33
//
// public typealias CBMPeer = CBPeer
// public typealias CBMAttribute = CBAttribute

/// A universally unique identifier, as defined by Bluetooth standards.
///
/// Instances of the `CBMUUID` class represent the 128-bit universally unique identifiers (UUIDs)
/// of attributes used in Bluetooth low energy communication, such as a peripheral’s services,
/// characteristics, and descriptors. This class provides a number of factory methods for dealing
/// with long UUIDs when developing your app. For example, instead of passing around the string
/// representation of a 128-bit Bluetooth low energy attribute in your code, you can create a
/// `CBMUUID` object that represents it, and pass that around instead.
///
/// The Bluetooth Special Interest Group (SIG) publishes a list of commonly-used UUIDs,
/// many of which are 16- or 32-bits for convenience. The `CBMUUID` class provides methods
/// that automatically transform these predefined shorter UUIDs into their 128-bit equivalent UUIDs.
/// When you create a CBMUUID object from a predefined 16- or 32-bit UUID, Core Bluetooth
/// pre-fills the rest of the 128-bit UUID with the Bluetooth base UUID, as defined in the
/// Bluetooth 4.0 specification, Volume 3, Part F, Section 3.2.1.
///
/// In addition to providing methods for creating `CBMUUID` objects, this class defines constants
/// that represent the UUIDs of the Bluetooth-defined characteristic descriptors, as defined in the
/// Bluetooth 4.0 specification, Volume 3, Part G, Section 3.3.3.
public typealias CBMUUID = CBUUID
/// An error that Core Bluetooth returns during Bluetooth transactions.
public typealias CBMError = CBError
/// An error that Core Bluetooth returns while using Attribute Protocol (ATT).
public typealias CBMATTError = CBATTError
/// A change to the connection state of a peer.
public typealias CBMConnectionEvent = CBConnectionEvent
/// A set of options to use when registering for connection events.
public typealias CBMConnectionEventMatchingOption = CBConnectionEventMatchingOption
/// Values representing the connection state of a peripheral.
public typealias CBMPeripheralState = CBPeripheralState
/// Values representing the possible write types to a characteristic’s value.
///
/// Characteristic write types have corresponding restrictions on the length of the data
/// that you can write to a characteristic’s value. For the `.withResponse`
/// write type’s restrictions, see the Bluetooth 4.0 specification, Volume 3, Part G, Sections 4.9.3–4.
/// For the `.withoutResponse` write type restrictions,
/// see the Bluetooth 4.0 specification, Volume 3, Part G, Sections 4.9.1–2.
///
/// - Tip: When you write with a response, you can write a characteristic value that’s longer than
///      permitted when you write without a response.
public typealias CBMCharacteristicWriteType = CBCharacteristicWriteType
/// Values that represent the possible properties of a characteristic.
///
/// Since you can combine characteristic properties, a characteristic may have multiple property values set.
public typealias CBMCharacteristicProperties = CBCharacteristicProperties
/// The type of PSM identifiers.
@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
public typealias CBML2CAPPSM = CBL2CAPPSM
/// A live L2CAP connection to a remote device.
@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
public typealias CBML2CAPChannel = CBL2CAPChannel
/// The current authorization state of a Core Bluetooth manager.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public typealias CBMManagerAuthorization = CBManagerAuthorization
/// The channel sounding role a CBPeripheral should assume for a given session.
@available(iOS 27.0, *)
public typealias CBMChannelSoundingSessionConfiguration = CBChannelSoundingSessionConfiguration
/// The measured distance in meters of a CBPeripheral.
@available(iOS 27.0, *)
public typealias CBMChannelSoundingProcedureResults = CBChannelSoundingProcedureResults

/// A Boolean value that specifies whether the scan should run without duplicate filtering.
///
/// The value for this key is an NSNumber object. If true, the central disables filtering and
/// generates a discovery event each time it receives an advertising packet from the peripheral.
/// If `false` (the default), the central coalesces multiple discoveries of the same peripheral
/// into a single discovery event.
///
/// - Important: Disabling this filtering can have an adverse effect on battery life;
///              use it only if necessary.
public let CBMCentralManagerScanOptionAllowDuplicatesKey = CBCentralManagerScanOptionAllowDuplicatesKey
/// An array of service UUIDs that you want to scan for.
///
/// The array is an instance of `NSArray`, and uses ``CBMUUID`` objects to represent the UUIDs
/// to scan for.
///
/// Specifying this scan option causes the central manager to also scan for peripherals soliciting
/// any of the services contained in the array.
public let CBMCentralManagerScanOptionSolicitedServiceUUIDsKey = CBCentralManagerScanOptionSolicitedServiceUUIDsKey
/// A Boolean value that specifies whether the system warns the user if the app instantiates
/// the central manager when Bluetooth service isn’t available.
///
/// The value for this key is an `NSNumber` object. If the key isn’t specified, the default value is `true`.
public let CBMCentralManagerOptionShowPowerAlertKey = CBCentralManagerOptionShowPowerAlertKey
/// A string containing a unique identifier (UID) for the central manager to instantiate.
///
/// The value for this key is an `NSString`. The system uses this UID to identify a specific
/// central manager. As a result, the UID must remain the same for subsequent executions
/// of the app to restore the central manager.
public let CBMCentralManagerOptionRestoreIdentifierKey = CBCentralManagerOptionRestoreIdentifierKey
/// An array of peripherals for use when restoring the state of a central manager.
///
/// The value associated with this key is an `NSArray` of ``CBMPeripheralSpec`` objects.
/// The array contains all of the peripherals connected to the central manager
/// (or had a pending connection) at the time the system terminated the app.
///
/// When possible, the system restores all information about a peripheral, including any
///  discovered services, characteristics, characteristic descriptors, and characteristic notification states.
public let CBMCentralManagerRestoredStatePeripheralsKey  = CBCentralManagerRestoredStatePeripheralsKey
/// An array of service IDs for use when restoring state.
///
/// The value associated with this key is an `NSArray` of service UUIDs
/// (represented by ``CBMUUID`` objects) containing all the services the central manager
/// was scanning for at the time the system terminated the app.
public let CBMCentralManagerRestoredStateScanServicesKey = CBCentralManagerRestoredStateScanServicesKey
/// A dictionary of peripheral scan options for use when restoring state.
///
/// The value associated with this key is an `NSDictionary`.
/// The dictionary contains all of the peripheral scan options in use by the central manager
/// when the system terminated the app.
public let CBMCentralManagerRestoredStateScanOptionsKey  = CBCentralManagerRestoredStateScanOptionsKey

/// The local name of a peripheral.
///
/// The value associated with this key is an `NSString`.
public let CBMAdvertisementDataLocalNameKey             = CBAdvertisementDataLocalNameKey
/// An array of service UUIDs.
public let CBMAdvertisementDataServiceUUIDsKey          = CBAdvertisementDataServiceUUIDsKey
/// A Boolean value that indicates whether the advertising event type is connectable.
///
/// The value for this key is an `NSNumber` object. You can use this value to determine
/// whether your app can currently connect to a peripheral.
public let CBMAdvertisementDataIsConnectable            = CBAdvertisementDataIsConnectable
/// The transmit power of a peripheral.
///
/// The value associated with this key is an instance of `NSNumber`.
///
/// This key and value are available if the peripheral provides its transmitting power level
/// in its advertising packet. You can calculate the path loss by comparing the RSSI
/// value with the transmitting power level.
public let CBMAdvertisementDataTxPowerLevelKey          = CBAdvertisementDataTxPowerLevelKey
/// A dictionary that contains service-specific advertisement data.
///
/// The keys (``CBMUUID`` objects) represent ``CBMService`` UUIDs, and the values
/// (`NSData` objects) represent service-specific data.
public let CBMAdvertisementDataServiceDataKey           = CBAdvertisementDataServiceDataKey
/// The manufacturer data of a peripheral.
///
/// The value associated with this key is an `NSData` object.
public let CBMAdvertisementDataManufacturerDataKey      = CBAdvertisementDataManufacturerDataKey
/// An array of UUIDs found in the overflow area of the advertisement data.
///
/// The value associated with this key is an array of one or more ``CBMUUID`` objects,
/// representing ``CBMService`` UUIDs.
///
/// Because data stored in this area results from not fitting in the main advertisement,
/// UUIDs listed here are “best effort” and may not always be accurate. For details
/// about the overflow area of advertisement data, see the `startAdvertising(_:)`
/// method in `CBPeripheralManager`.
public let CBMAdvertisementDataOverflowServiceUUIDsKey  = CBAdvertisementDataOverflowServiceUUIDsKey
/// An array of solicited service UUIDs.
///
/// The value associated with this key is an array of one or more ``CBMUUID`` objects,
/// representing ``CBMService`` UUIDs.
public let CBMAdvertisementDataSolicitedServiceUUIDsKey = CBAdvertisementDataSolicitedServiceUUIDsKey

/// An option that indicates a delay before the system makes a connection.
///
/// The corresponding value is an `NSNumber` that indicates the duration of the delay in seconds.
public let CBMConnectPeripheralOptionStartDelayKey = CBConnectPeripheralOptionStartDelayKey
#if !os(macOS)
/// An option to require Apple Notification Center Service (ANCS) when connecting a device.
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public let CBMConnectPeripheralOptionRequiresANCS = CBConnectPeripheralOptionRequiresANCS
#endif
/// A Boolean value that specifies whether the system should display an alert when
/// connecting a peripheral in the background.
///
/// The value for this key is an `NSNumber` object. This key is useful for apps that
/// haven’t specified the bluetooth-central background mode and can’t display their own alert.
/// If more than one app requests a notification for a given peripheral, the one that was
/// most recently in the foreground receives the alert. If the key isn’t specified, the default
/// value is `false`.
public let CBMConnectPeripheralOptionNotifyOnConnectionKey = CBConnectPeripheralOptionNotifyOnConnectionKey
/// A Boolean value that specifies whether the system should display an alert when
/// disconnecting a peripheral in the background.
///
/// The value for this key is an `NSNumber` object. This key is useful for apps that
/// haven’t specified the bluetooth-central background mode and can’t display their own alert.
/// If more than one app requests a notification for a given peripheral, the one that was
/// most recently in the foreground receives the alert. If the key isn’t specified, the default
/// value is `false`.
public let CBMConnectPeripheralOptionNotifyOnDisconnectionKey = CBConnectPeripheralOptionNotifyOnDisconnectionKey
/// A Boolean value that specifies whether the system should display an alert for any
/// notification sent by a peripheral.
///
/// If `true`, the system displays an alert for all notifications received from a given
/// peripheral while the app is suspended.
///
/// The value for this key is an `NSNumber` object. This key is useful for apps that
/// haven’t specified the bluetooth-central background mode and can’t display their own alert.
/// If more than one app requests a notification for a given peripheral, the one that was
/// most recently in the foreground receives the alert. If the key isn’t specified, the default
/// value is `false`.
public let CBMConnectPeripheralOptionNotifyOnNotificationKey = CBConnectPeripheralOptionNotifyOnNotificationKey
#if !os(macOS)
/// A Boolean value that specifies whether the system should to connect non-GATT profiles
/// on classic Bluetooth devices, if there is a low energy GATT connection to the same device.
///
/// If `true`, the system  instructs the system to bring up classic transport profiles when a
/// low energy transport peripheral connects.
///
/// The value for this key is an `NSNumber` object. If the key isn’t specified, the default
/// value is `false`.
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public let CBMConnectPeripheralOptionEnableTransportBridgingKey = CBConnectPeripheralOptionEnableTransportBridgingKey
#endif
/// An Boolean indicating that the AutoReconnect is enabled for the peripheral is connected.
///
/// After peripheral device is connected, this will allow the system to initiate connect to the peer
/// device automatically when link is dropped.
///
/// Caller will get notified about the disconnection with potential delay via
/// ``CBMCentralManagerDelegate/centralManager(_:didDisconnectPeripheral:timestamp:isReconnecting:error:)-305ej``.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public let CBMConnectPeripheralOptionEnableAutoReconnect = CBConnectPeripheralOptionEnableAutoReconnect
