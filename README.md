# Core Bluetooth Mock

[![Platform](https://img.shields.io/cocoapods/p/CoreBluetoothMock.svg?style=flat)](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-green?style=flat)](https://swift.org/package-manager)
![Version number](https://img.shields.io/cocoapods/v/CoreBluetoothMock) 
[![Release](https://img.shields.io/github/release/nordicsemi/IOS-CoreBluetooth-Mock.svg)](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/releases)
[![GitHub stars](https://img.shields.io/github/stars/nordicsemi/IOS-CoreBluetooth-Mock)](https://github.com/nordicsemi/CoreBluetoothMock/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/nordicsemi/IOS-CoreBluetooth-Mock)](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/members)
[![GitHub contributors](https://img.shields.io/github/contributors/nordicsemi/IOS-CoreBluetooth-Mock)](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/graphs/contributors)

The *Core Bluetooth Mock* library was designed to emulate *Core Bluetooth* objects, providing easy way to test 
Bluetooth-enabled apps. As the native Bluetooth API is not supported on a simulator, using this library you can run, test 
and take screenshots of such apps without the need of a physical phone or tablet. You may also start working on the
iOS app when your peripheral is still under development.

### Core Bluetooth?

The [Core Bluetooth](https://developer.apple.com/documentation/corebluetooth) framework provides the classes needed 
for your apps to communicate with Bluetooth-equipped low energy (LE) wireless technology. It requires an iPhone or iPad to 
work making Bluetooth-enabled apps difficult to test. As the documentation states:

> Don’t subclass any of the classes of the Core Bluetooth framework. Overriding these classes isn’t supported and results in 
   undefined behavior.

### Core Bluetooth Mock!

The *Core Bluetooth Mock* library defines a number of **CBM...** classes and constants, that wrap or imitate the corresponding
**CB...** counterparts from *Core Bluetooth* framework. For example, `CBMCentralManager` has the same API and 
behavior as `CBCentralManager`, etc. On physical iDevices all calls to `CBMCentralManager` and `CBMPeripheral` are
forwarded to their native equivalents, but on a simulator a user defined mock implementation is used. 

## Requirements

The *Core Bluetooth Mock* library is available only in *Swift*, and compatible with 
* iOS 12.0+[^1], 
* macOS 10.14+, 
* tvOS 12.0+[^1],
* watchOS 4.0+

(with some features available only on newer platforms).

> [!Note]
> For projects running Objective-C we recommend https://github.com/Rightpoint/RZBluetooth library.

[^1]: Xcode 15 dropped support for iOS 9.0 and tvOS 9.0 in simulator. Now the minimum supported version is 12.0 for both platforms.

## Installation

The library support [CocoaPods](https://github.com/CocoaPods/CocoaPods), [Carthage](https://github.com/Carthage/Carthage) and 
[Swift Package Manager](https://swift.org/package-manager).

<details>
   <summary>CocoaPods</summary>

- Create/Update your **Podfile** with the following contents

    ```ruby
    target 'YourAppTargetName' do
        pod 'CoreBluetoothMock'
    end
    ```

- Install dependencies

    ```bash
    pod install
    ```

- Open the newly created `.xcworkspace`
</details>
<details>
   <summary>Carthage</summary>
   
- Create a new **Cartfile** in your project's root with the following contents

    ```
    github "https://github.com/nordicsemi/IOS-CoreBluetooth-Mock" ~> x.y // Replace x.y with your required version
    ```
    
- Build with carthage

    ```bash
    carthage update --platform iOS // also supported are tvOS, watchOS and macOS
    ```

- Copy the **CoreBluetoothMock.framework** from *Carthage/Build* to your project and follow [instructions from Carthage](https://github.com/Carthage/Carthage).
</details>
<details>
   <summary>Swift Package Manager</summary>

- In Xcode: *File -> Swift Packages -> Add package dependency*, 
type *https://github.com/nordicsemi/IOS-CoreBluetooth-Mock.git* and set required version, branch or commit.

- If you have *Swift.package* file, include the following dependency:
  ```swift
  dependencies: [
      // [...]
      .package(name: "CoreBluetoothMock", 
               url: "https://github.com/nordicsemi/IOS-CoreBluetooth-Mock.git", 
               .upToNextMajor(from: "x.y")) // Replace x.y with your required version
  ]
  ```
  and add it to your target:
  ```swift
  targets: [
      // [...]
      .target(
          name: "<Your target name>",
          dependencies: ["CoreBluetoothMock"]),
  ]
  ```
</details>

## Documentation

The documentation of the library is available [here](https://nordicsemi.github.io/IOS-CoreBluetooth-Mock/documentation/corebluetoothmock).

## Migration from *CoreBluetooth*

We have a couple of examples that show migrations from the platform's `CoreBluetooth` import to `CoreBluetoothMock`:

- [nRF Connect Device Manager](https://apps.apple.com/es/app/nrf-connect-device-manager/id1519423539) has migrated to aid in UI-level testing as well as being able to run the app in the Simulator. You can find the appropriate [Pull Request here](https://github.com/nordicsemi/IOS-nRF-Connect-Device-Manager/pull/590).
- CoreBluetooth-Mock-Example is available [here](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock-Example). There is also a step-by-step guide available via this [Pull Request](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock-Example/pull/1).

> [!Note]
> The migration example application currently does not use mocks in tests. 
For that, check out the **Example** folder in this repository with *nRF Blinky* app, which is
using mock peripherals in Unit Tests and UI Tests. See below.

# Sample application: nRF Blinky

nRF Blinky is an example app targeted towards newcomer BLE developers, and also demonstrating the use 
of *Core Bluetooth Mock* library. This application controls an LED on an
[nRF5DK](https://www.nordicsemi.com/Software-and-Tools/Development-Kits)
and receive notifications whenever the button on the kit is pressed and released.

The mock implementation is used in Unit tests and UI tests. 
See [AppDelegate.swift](Example/nRFBlinky/AppDelegate.swift) where the mock environment is set up and
and [UITests.swift](Example/Tests) and [UITests.swift](Example/UI%20Tests/UITests.swift) classes.

The mock peripherals are defined in [MockPeripherals.swift](Example/nRFBlinky/MockPeripherals.swift).

### Nordic LED and Button Service

A simplified proprietary service by Nordic Semiconductor, containing two characteristics one to control LED3 and Button1:
- Service UUID: **`00001523-1212-EFDE-1523-785FEABCD123`**
  - First characteristic controls the LED state (On/Off).
    - UUID: **`00001525-1212-EFDE-1523-785FEABCD123`**
    - Value: **`1`** => LED On
    - Value: **`0`** => LED Off
  - Second characteristic notifies central of the button state on change (Pressed/Released).
    - UUID: **`00001524-1212-EFDE-1523-785FEABCD123`**
    - Value: **`1`** => Button Pressed
    - Value: **`0`** => Button Released
  
  For full specification, check out 
  [documentation](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/ble_sdk_app_blinky.html?cp=8_1_4_2_2_3).

### Requirements

- An iOS device with BLE capabilities, or a simulator (to run the mock).
- A [Development Kit](https://www.nordicsemi.com/Software-and-Tools/Development-Kits) (unless testing mock).
- The Blinky example firmware to flash on the Development Kit. For your convenience, we have bundled two firmwares in this project under the Firmwares directory.
- To get the latest firmwares and check the source code, you may go directly to our [Developers website](http://developer.nordicsemi.com/nRF5_SDK/) and download the SDK version you need, then you can find the source code and hex files to the blinky demo in the directory `/examples/ble_peripheral/ble_app_blinky/`
- The LBS (LED Button Service) is also supported in nRF Connect SDK: [here](https://developer.nordicsemi.com/nRF_Connect_SDK/doc/latest/nrf/samples/bluetooth/peripheral_lbs/README.html).
-  More information about the nRFBlinky example firmware can be found in the [documentation](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/ble_sdk_app_blinky.html?cp=8_1_4_2_2_3).

### Installation and usage

- Prepare your Development kit.
  - Plug in the Development Kit to your computer via USB.
  - Power On the Development Kit.
  - The Development Kit will now appear as a Mass storage device.
  - Drag (or copy/paste) the appropriate HEX file onto that new device.
  - The Development Kit LEDs will flash and it will disconnect and reconnect.
  - The Development Kit is now ready and flashed with the nRFBlinky example firmware.

- Start Xcode and run build the project against your target iOS Device (**Note:** BLE is not available in the iOS simulator, so the iOS device is a requirement to test with real hardware).
  - Launch the **nRF Blinky** app on your iOS device.
  - The app will start scanning for nearby peripherals.
  - Select the **Nordic_Blinky** peripheral that appears on screen (**Note:** if the peripheral does not show up, ensure that it's powered on and functional).
  - Your iOS device will now connect to the peripheral and state is displayed on the screen.
  - Changing the value of the Toggle switch will turn LED 3 on or off.
  - Pressing Button 1 on the Development Kit will show the button state as Pressed on the app.
  - Releasing Button 1 will show the state as Released on the App.

## Special Thanks

On behalf of Nordic and all the maintainers of this repo, we'd like to [thank all contributors](https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/graphs/contributors) for their contributions.

<a href="https://github.com/nordicsemi/IOS-CoreBluetooth-Mock/graphs/contributors">
  <img src="https://contributors-img.web.app/image?repo=nordicsemi/IOS-CoreBluetooth-Mock" />
</a>
