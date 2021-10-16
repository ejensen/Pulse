// The MIT License (MIT)
//
// Copyright (c) 2020–2021 Alexander Grebenyuk (github.com/kean).

import Logging
import XCTest
import Foundation
import CoreData
@testable import PulseCore

extension LoggerStore {
    func removeStores() {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    func destroyStores() {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.destroyPersistentStore(at: store.url!, ofType: NSSQLiteStoreType, options: [:])
        }
    }
    
    func flush() {
        backgroundContext.performAndWait {
            try! backgroundContext.save()
        }
    }
}

struct TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
