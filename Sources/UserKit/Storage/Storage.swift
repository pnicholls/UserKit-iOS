//
//  Storage.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

class Storage {

    // MARK: - Properties
    
    private let queue = DispatchQueue(label: "com.userkit.storage")

    private let cache: Cache

    // MARK: - Configuration

    init(cache: Cache = Cache()) {
        self.cache = cache
    }

    /// Clears data that is user specific.
    func reset() {
        cache.cleanUserFiles()
    }

    // MARK: - Cache Reading & Writing
    func get<Key: Storable>(_ keyType: Key.Type) -> Key.Value? {
        return cache.read(keyType)
    }

    func get<Key: Storable>(_ keyType: Key.Type) -> Key.Value?
    where Key.Value: Decodable {
        return cache.read(keyType)
    }

    func save<Key: Storable>(_ value: Key.Value, forType keyType: Key.Type) {
        return cache.write(value, forType: keyType)
    }

    func save<Key: Storable>(_ value: Key.Value, forType keyType: Key.Type)
    where Key.Value: Encodable {
        return cache.write(value, forType: keyType)
    }

    func delete<Key: Storable>(_ keyType: Key.Type) {
        return cache.delete(keyType)
    }

    func save<Key: Storable>(_ keyType: Key.Type) where Key.Value: Encodable {
        return cache.delete(keyType)
    }
}
