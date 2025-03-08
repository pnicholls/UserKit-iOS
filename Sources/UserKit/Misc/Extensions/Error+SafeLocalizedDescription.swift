//
//  Error+SafeLocalizedDescription.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

extension Error {
    /// Checks that it's not an empty NSError before returning the `localizedDescription`.`
    var safeLocalizedDescription: String {
        // Xcode lies, conditional cast is needed otherwise this crashes.
        let nsError = self as NSError
        if nsError.code == 0,
            nsError.domain.isEmpty
        {
            return "Unknown error."
        } else {
            return localizedDescription
        }
    }
}
