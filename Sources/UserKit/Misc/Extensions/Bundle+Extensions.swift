//
//  Bundle+Extensions.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/5/2025.
//

import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}
