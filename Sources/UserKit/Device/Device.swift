//
//  Device.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/5/2025.
//

import UIKit
import Foundation
import SystemConfiguration
#if canImport(CoreTelephony)
import CoreTelephony
#endif

struct Device {
    let appVersion = Bundle.main.releaseVersionNumber ?? ""
    
    let buildVersionNumber = Bundle.main.buildVersionNumber ?? ""
    
    let vendorId: String = {
        UIDevice.current.identifierForVendor?.uuidString ?? ""
    }()
    
    let osVersion: String = {
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
        return String(
            format: "%ld.%ld.%ld",
            arguments: [systemVersion.majorVersion, systemVersion.minorVersion, systemVersion.patchVersion]
        )
    }()
    
    let model: String = {
        UIDevice.modelName
    }()
    
    var locale: String {
        Locale.autoupdatingCurrent.identifier
    }
    
    var languageCode: String {
        if #available(iOS 16, *) {
            return Locale.autoupdatingCurrent.language.languageCode?.identifier ?? ""
        } else {
            return Locale.autoupdatingCurrent.languageCode ?? ""
        }
    }
    
    var currencyCode: String {
        Locale.autoupdatingCurrent.currencyCode ?? ""
    }

    var currencySymbol: String {
        Locale.autoupdatingCurrent.currencySymbol ?? ""
    }
    
    var secondsFromGMT: String {
        "\(Int(TimeZone.current.secondsFromGMT()))"
    }
    
    var appInstalledAtString: String {
        appInstallDate?.isoString ?? ""
    }
    
    var regionCode: String {
        if #available(iOS 16, *) {
            return Locale.autoupdatingCurrent.language.region?.identifier ?? ""
        } else {
            return Locale.autoupdatingCurrent.regionCode ?? ""
        }
    }
    
    private let reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, "getuserkit.com")
    
    var reachabilityFlags: SCNetworkReachabilityFlags? {
      guard let reachability = reachability else {
        return nil
      }
      var flags = SCNetworkReachabilityFlags()
      SCNetworkReachabilityGetFlags(reachability, &flags)

      return flags
    }
    
    var radioType: String {
        guard let flags = reachabilityFlags else {
            return "No Internet"
        }

        let isReachable = flags.contains(.reachable)
        let isWWAN = flags.contains(.isWWAN)

        if isReachable {
            if isWWAN {
                return "Cellular"
            } else {
                return "Wifi"
            }
        } else {
            return "No Internet"
        }
    }
    
    private let appInstallDate: Date? = {
        guard let urlToDocumentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last else {
            return nil
        }

        guard let installDate = try? FileManager.default.attributesOfItem(atPath: urlToDocumentsFolder.path)[FileAttributeKey.creationDate] as? Date else {
            return nil
        }
        
        return installDate
    }()
    
    var interfaceStyle: String {
        #if os(visionOS)
        return "Unknown"
        #else
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        switch style {
        case .unspecified:
            return "Unspecified"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        default:
            return "Unknown"
        }
      #endif
    }
    
    let bundleId: String = {
        return Bundle.main.bundleIdentifier ?? ""
    }()
    
    var isLowPowerModeEnabled: String {
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? "true" : "false"
    }
    
    /// Returns true if built for the simulator or using TestFlight.
    let isSandbox: String = {
        #if targetEnvironment(simulator)
        return "true"
        #else

        guard let url = Bundle.main.appStoreReceiptURL else {
            return "false"
        }

        return "\(url.path.contains("sandboxReceipt"))"
        #endif
    }()
}
