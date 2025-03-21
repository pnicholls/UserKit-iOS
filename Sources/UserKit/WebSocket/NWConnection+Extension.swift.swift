//
//  NWConnection+Extension.swift.swift
//  UserKit
//
//  Created by Peter Nicholls on 21/3/2025.
//

import Network

fileprivate var _intentionalDisconnection: Bool = false

internal extension NWConnection {

    var intentionalDisconnection: Bool {
        get {
            return _intentionalDisconnection
        }
        set {
            _intentionalDisconnection = newValue
        }
    }
}
