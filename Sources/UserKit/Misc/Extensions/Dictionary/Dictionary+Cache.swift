//
//  Untitled.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

extension Dictionary {
    func keysSortedByValue(_ isOrderedBefore: (Value, Value) -> Bool) -> [Key] {
        return Array(self).sorted { isOrderedBefore($0.1, $1.1) }.map { $0.0 }
    }
}
