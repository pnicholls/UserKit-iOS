//
//  SearchPathDirectory.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

enum SearchPathDirectory {
    /// Saves to the caches directory, which can be cleared by
    /// the system at any time.
    case cache

    /// Specific to the user.
    case userSpecificDocuments

    /// Specific to the app as a whole.
    case appSpecificDocuments
}

protocol Storable {
    static var key: String { get }
    static var directory: SearchPathDirectory { get }
    associatedtype Value
}

enum AppUserCredentials: Storable {
    static var key: String {
        "store.userCredentials"
    }
    static var directory: SearchPathDirectory = .userSpecificDocuments
    typealias Value = Credentials
}

