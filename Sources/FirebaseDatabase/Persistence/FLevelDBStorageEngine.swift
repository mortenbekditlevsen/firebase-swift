// Copyright 2017 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

// WARNING: If you change this, you need to write a migration script
let kFPersistenceVersion = "1"

let  kFServerDBPath = "server_data"
let  kFWritesDBPath = "writes"

let  kFUserWriteId = "id"
let  kFUserWritePath = "path"
let  kFUserWriteOverwrite = "o"
let  kFUserWriteMerge = "m"

let  kFTrackedQueryId = "id"
let  kFTrackedQueryPath = "path"
let  kFTrackedQueryParams = "p"
let  kFTrackedQueryLastUse = "lu"
let  kFTrackedQueryIsComplete = "c"
let  kFTrackedQueryIsActive = "a"

let  kFServerCachePrefix = "/server_cache/"
// '~' is the last non-control character in the ASCII table until 127
// We wan't the entire range of thing stored in the DB
let kFServerCacheRangeEnd = "/server_cache~"
let kFTrackedQueriesPrefix = "/tracked_queries/"
let kFTrackedQueryKeysPrefix = "/tracked_query_keys/"

// Failed to load JSON because a valid JSON turns out to be NaN while
// deserializing
let kFNanFailureCode = 3840

enum FLevelDBStorageEngineError: Error {
    case decodingError
}

private func writeRecordKey(writeId: Int) -> String { "\(writeId)" }

private func serverCacheKey(_ path: FPath) -> String {
    kFServerCachePrefix + path.toStringWithTrailingSlash()
}

private func trackedQueryKey(trackedQueryId: Int) -> String {
    "\(kFTrackedQueriesPrefix)\(trackedQueryId)"
}

private func trackedQueryKeysKeyPrefix(trackedQueryId: Int) -> String {
    "\(kFTrackedQueryKeysPrefix)\(trackedQueryId)/"
}

private func trackedQueryKeysKey(trackedQueryId: Int, key: String) -> String {
    "\(kFTrackedQueryKeysPrefix)\(trackedQueryId)/\(key)"
}

class FLevelDBStorageEngine: FStorageEngine {
    private(set) var writesDB: APLevelDB!
    private(set) var serverCacheDB: APLevelDB!
    private var basePath: URL
    
    public static var firebaseDir: URL {
#if os(iOS) || os(watchOS)
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDir = urls[0] // Yes, it's a hard error if we have no documents directory
            return documentsDir.appendingPathComponent("firebase")
#elseif os(tvOS)
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            let cachesDir = urls[0] // Yes, it's a hard error if we have no documents directory
            return cachesDir.appendingPathComponent("firebase")
#elseif os(macOS)

        if #available(macOS 13.0, *) {

            return URL(filePath: NSHomeDirectory())
                .appendingPathComponent("firebase")
        } else {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("firebase")
        }
#else
            // On other platforms like linux .documentsDirectory is a global /Users/xxx/Documents folder
            // This is likely ok since the database names include the firebase database url too.
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDir = urls[0] // Yes, it's a hard error if we have no documents directory
            return documentsDir.appendingPathComponent("firebase")
#endif
    }

    init(path: String) {
        self.basePath = FLevelDBStorageEngine.firebaseDir.appendingPathComponent(path)
        /* For reference:
         serverDataDB = [aPersistence createDbByName:@"server_data"];
         FPangolinDB *completenessDb = [aPersistence
         createDbByName:@"server_complete"];
         */
        FLevelDBStorageEngine.ensureDir(&self.basePath, markAsDoNotBackup: true)
        runMigration()
        openDatabases()
    }

    private func runMigration() {
        // Currently we're at version 1, so all we need to do is write that to a
        // file
        let versionFile =
        basePath.appendingPathComponent("version")

        let oldVersion = try? String(contentsOf: versionFile, encoding: .utf8)
        if let oldVersion = oldVersion {
            if oldVersion == kFPersistenceVersion {
                // Everythings fine no need for migration
            } else if oldVersion.isEmpty {
                FFWarn("I-RDB076036",
                       "Version file empty. Assuming database version 1.")
            } else {
                // If we add more versions in the future, we need to run migration here
                fatalError("Unrecognized database version: \(oldVersion)")
            }
        } else {
            do {
                try kFPersistenceVersion.write(to: versionFile, atomically: false, encoding: .utf8)
            } catch {
                FFWarn("I-RDB076001", "Failed to write version for database: \(error)")
            }
        }
    }

    func runLegacyMigration(_ info: FRepoInfo) {
        fatalError("Not yet supported")
        /*
         - (void)runLegacyMigration:(FRepoInfo *)info {
             NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(
                 NSDocumentDirectory, NSUserDomainMask, YES);
             NSString *documentsDir = [dirPaths objectAtIndex:0];
             NSString *firebaseDir =
                 [documentsDir stringByAppendingPathComponent:@"firebase"];
             NSString *repoHashString =
                 [NSString stringWithFormat:@"%@_%@", info.host, info.namespace];
             NSString *legacyBaseDir =
                 [NSString stringWithFormat:@"%@/1/%@/v1", firebaseDir, repoHashString];
             if ([[NSFileManager defaultManager] fileExistsAtPath:legacyBaseDir]) {
                 FFWarn(@"I-RDB076002", @"Legacy database found, migrating...");
                 // We only need to migrate writes
                 NSError *error = nil;
                 APLevelDB *writes = [APLevelDB
                     levelDBWithPath:[legacyBaseDir stringByAppendingPathComponent:
                                                        @"outstanding_puts"]
                               error:&error];
                 if (writes != nil) {
                     __block NSUInteger numberOfWritesRestored = 0;
                     // Maybe we could use write batches, but what the heck, I'm sure
                     // it'll go fine :P
                     [writes enumerateKeysAndValuesAsData:^(NSString *key, NSData *data,
                                                            BOOL *stop) {
         #pragma clang diagnostic push
         #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                       // Update the deprecated API when minimum iOS version is 11+.
                       id pendingPut = [NSKeyedUnarchiver unarchiveObjectWithData:data];
         #pragma clang diagnostic pop
                       if ([pendingPut isKindOfClass:[FPendingPut class]]) {
                           FPendingPut *put = pendingPut;
                           id<FNode> newNode =
                               [FSnapshotUtilities nodeFrom:put.data
                                                   priority:put.priority];
                           [self saveUserOverwrite:newNode
                                            atPath:put.path
                                           writeId:[key integerValue]];
                           numberOfWritesRestored++;
                       } else if ([pendingPut
                                      isKindOfClass:[FPendingPutPriority class]]) {
                           // This is for backwards compatibility. Older clients will
                           // save FPendingPutPriority. New ones will need to read it and
                           // translate.
                           FPendingPutPriority *putPriority = pendingPut;
                           FPath *priorityPath =
                               [putPriority.path childFromString:@".priority"];
                           id<FNode> newNode =
                               [FSnapshotUtilities nodeFrom:putPriority.priority
                                                   priority:nil];
                           [self saveUserOverwrite:newNode
                                            atPath:priorityPath
                                           writeId:[key integerValue]];
                           numberOfWritesRestored++;
                       } else if ([pendingPut isKindOfClass:[FPendingUpdate class]]) {
                           FPendingUpdate *update = pendingPut;
                           FCompoundWrite *merge = [FCompoundWrite
                               compoundWriteWithValueDictionary:update.data];
                           [self saveUserMerge:merge
                                        atPath:update.path
                                       writeId:[key integerValue]];
                           numberOfWritesRestored++;
                       } else {
                           FFWarn(@"I-RDB076003",
                                  @"Failed to migrate legacy write, meh!");
                       }
                     }];
                     FFWarn(@"I-RDB076004", @"Migrated %lu writes",
                            (unsigned long)numberOfWritesRestored);
                     [writes close];
                     FFWarn(@"I-RDB076005", @"Deleting legacy database...");
                     BOOL success =
                         [[NSFileManager defaultManager] removeItemAtPath:legacyBaseDir
                                                                    error:&error];
                     if (!success) {
                         FFWarn(@"I-RDB076006", @"Failed to delete legacy database: %@",
                                error);
                     } else {
                         FFWarn(@"I-RDB076007", @"Finished migrating legacy database.");
                     }
                 } else {
                     FFWarn(@"I-RDB076008", @"Failed to migrate old database: %@",
                            error);
                 }
             }
         }

         */
    }

    private func openDatabases() {
        self.serverCacheDB = createDb(dbName: kFServerDBPath)
        self.writesDB = createDb(dbName: kFWritesDBPath)
    }

    private func purgeDatabase(dbPath: String) {
        let path = basePath.appendingPathComponent(dbPath)
        do {
            FFWarn("I-RDB076009", "Deleting database at path \(path)")
            try FileManager.default.removeItem(at: path)
        } catch {
            fatalError("Failed to delete database files: \(error)")
        }
    }

    func purgeEverything() {
        close()
        for path in [kFServerDBPath, kFWritesDBPath] {
            purgeDatabase(dbPath: path)
        }
        openDatabases()
    }

    func close() {
        serverCacheDB.close()
        serverCacheDB = nil
        writesDB.close()
        writesDB = nil
    }

    func createDb(dbName: String) -> APLevelDB {
        let path = basePath.appendingPathComponent(dbName)
        do {
            return try APLevelDB(path: path.path)
        } catch {
            FFWarn("I-RDB076036",
                   "Failed to read database persistence file '\(dbName)': \(error)")
            // Delete the database and try again.
            purgeDatabase(dbPath: dbName)

            do {
                return try APLevelDB(path: path.path)
            } catch {
                fatalError("Error initializing persistence: \(error)")
            }
        }
    }

    func saveUserOverwrite(_ node: FNode, atPath path: FPath, writeId: Int) {
        // The node in export form, as `val(forExport: true)` has it.
        saveUserWrite([
            kFUserWriteId: writeId,
            kFUserWritePath: path.toStringWithTrailingSlash(),
            kFUserWriteOverwrite: node,
        ], writeId: writeId)
    }

    func saveUserMerge(_ merge: FCompoundWrite, atPath path: FPath, writeId: Int) {
        saveUserWrite([
            kFUserWriteId: writeId,
            kFUserWritePath: path.toStringWithTrailingSlash(),
            kFUserWriteMerge: merge.nodesForExport(),
        ], writeId: writeId)
    }

    private func saveUserWrite(_ write: [String: Any], writeId: Int) {
        do {
            let bytes = try FJSONWriter.bytes(write)
            _ = writesDB.setData(Data(bytes.readableBytesView), forKey: writeRecordKey(writeId: writeId))
        } catch {
            assertionFailure("Failed to serialize user write: \(write), (Error: \(error)")
        }
    }

    func removeUserWrite(_ writeId: Int) {
        _ = writesDB.removeKey(writeRecordKey(writeId: writeId))
    }

    func removeAllUserWrites() {
        var count = 0
        let start = Date()
        let batch = writesDB.beginWriteBatch()
        writesDB.enumerateKeys { key, stop in
            batch.removeKey(key)
            count += 1
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076010", "Failed to remove all users writes on disk!")
        } else {
            FFDebug("I-RDB076011", "Removed \(count) writes in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    var userWrites: [FWriteRecord] {
        let date = Date()
        var writes: [FWriteRecord] = []
        writesDB.enumerateKeysAndValues { (key: String, data: Data, stop: inout Bool) in
            do {
                writes.append(try Self.writeRecord(data))
            } catch {
                // Don't crash on a write that can't be read, as upstream did
                // (except for doubles out of range): it can't be sent either.
                FFWarn("I-RDB076012",
                       "Failed to deserialize write \(String(decoding: data, as: UTF8.self)) (Error: \(error))")
                FFWarn("I-RDB076013", "Removing failed write with key \(key)")
                _ = self.writesDB.removeKey(key)
            }
        }
        // Make sure writes are sorted
        writes.sort { $0.writeId < $1.writeId }
        FFDebug("I-RDB076014", "Loaded \(writes.count) writes in \(date.timeIntervalSinceNow * -1000)ms")
        return writes
    }

    /// A stored write: {"id": id, "path": path, "o": overwrite} or {…, "m": merge}.
    private static func writeRecord(_ data: Data) throws -> FWriteRecord {
        try FJSONScanner.withScanner(data) { scanner in
            var writeId: Int?
            var path: FPath?
            var overwrite: FNode?
            var merge: [String: FNode]?
            try scanner.beginObject()
            var first = true
            while let key = try scanner.nextKey(&first) {
                switch key {
                case kFUserWriteId:
                    if case .int64(let id) = try scanner.readNumber() { writeId = Int(exactly: id) }
                case kFUserWritePath:
                    path = FPath(with: try scanner.readString())
                case kFUserWriteOverwrite:
                    overwrite = try scanner.readNode()
                case kFUserWriteMerge:
                    merge = try scanner.readMerge()
                default:
                    try scanner.skipValue()
                }
            }
            try scanner.expectEnd()
            guard let writeId, let path else { throw FLevelDBStorageEngineError.decodingError }
            if let merge {
                return FWriteRecord(path: path, merge: .compoundWrite(nodeDictionary: merge), writeId: writeId)
            } else if let overwrite {
                return FWriteRecord(path: path, overwrite: overwrite, writeId: writeId, visible: true)
            }
            throw FLevelDBStorageEngineError.decodingError
        }
    }

    func serverCache(atPath path: FPath) -> FNode {
        let start = Date()
        let node = storedNode(at: path)
        FFDebug("I-RDB076015", "Loaded node with \(node.numChildren()) children at \(path) in \(start.timeIntervalSinceNow * -1000)ms")
        return node
    }

    /// The node at `path` in the server cache, from its leaves' keys and
    /// values, read in place (one pass, nothing copied but the keys' names).
    private func storedNode(at path: FPath) -> FNode {
        let prefix = serverCacheKey(path)
        let prefixLength = prefix.utf8.count
        var builder = FLeafTreeBuilder()
        serverCacheDB.forEach(withPrefix: prefix) { key, value in
            builder.add(path: key.extracting(droppingFirst: prefixLength), leaf: Self.leaf(value, key: key))
            return true
        }
        return builder.finish()
    }

    /// A stored leaf value: JSON (a string, number or boolean).
    private static func leaf(_ value: Span<UInt8>, key: Span<UInt8>) -> FNode {
        var scanner = FJSONScanner(value)
        do {
            let node = try scanner.readNode()
            // Values written by earlier versions may end in a C terminator.
            scanner.skipWhitespace()
            if scanner.offset == value.count - 1, value[value.count - 1] == 0 {
                return node
            }
            try scanner.expectEnd()
            return node
        } catch {
            let keyString = unsafe key.withUnsafeBufferPointer { unsafe String(decoding: $0, as: UTF8.self) }
            FFWarn("I-RDB076034", "Failed to load primitive at \(keyString) (Error: \(error))")
            return .empty
        }
    }

    static func ensureDir(_ path: inout URL, markAsDoNotBackup: Bool) {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        } catch {
            fatalError("Failed to create persistence directory. Error: \(error) Path: \(path.path)")
        }
        #if canImport(Darwin)
            // Readable after the first unlock, so the database keeps working in
            // the background. No effect on simulators.
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: path.path)
            } catch {
                FFWarn("I-RDB076036",
                       "Failed to set file protection attribute on persistence directory: \(error)")
            }
        #endif
        guard markAsDoNotBackup else { return }
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try path.setResourceValues(values)
        } catch {
            // Not worth crashing over: the data is only a cache.
            FFWarn(
                "I-RDB076035",
                "Failed to mark firebase database folder as do not backup: \(error)")
        }
    }

    func serverCache(forKeys keys: Set<String>, atPath path: FPath) -> FNode {
        let start = Date()
        var node: FNode = .empty
        for key in keys {
            node = node.updateImmediateChild(key, withNewChild: storedNode(at: path.child(fromString: key)))
        }
        FFDebug("I-RDB076016",
                "Loaded node with \(node.numChildren()) children for \(keys.count) keys at \(path) in \(start.timeIntervalSinceNow * -1000)ms")
        return node
    }

    private func removeAllLeafNodes(on path: FPath, batch: APLevelDBWriteBatch) {
        var path: FPath? = path
        while let aPath = path {
            batch.removeKey(serverCacheKey(aPath))
            path = aPath.parent()
        }
        // Make sure to delete any nodes at the root
        batch.removeKey(serverCacheKey(.empty))
    }

    private func removeAllWrites(withPrefix prefix: String, batch: APLevelDBWriteBatch, database: APLevelDB) {
        database.forEach(withPrefix: prefix) { key, _ in
            batch.removeKey(bytes: key)
            return true
        }
    }

    func updateServerCache(_ node: FNode, atPath path: FPath, merge: Bool) {
        let start = Date()
        let batch = serverCacheDB.beginWriteBatch()
        // Remove any leaf nodes that might be higher up
        removeAllLeafNodes(on: path, batch: batch)
        var counter = 0
        if merge {
            // remove any children that exist
            node.enumerateChildren { childKey, childNode, stop in
                let childPath = path.child(fromString: childKey)
                self.removeAllWrites(withPrefix: serverCacheKey(childPath), batch: batch, database: self.serverCacheDB)
                self.saveNodeInternal(childNode, atPath: childPath, batch: batch, counter: &counter)
            }
        } else {
            // remove everything
            removeAllWrites(withPrefix: serverCacheKey(path), batch: batch, database: serverCacheDB)
            saveNodeInternal(node, atPath: path, batch: batch, counter: &counter)
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076017", "Failed to update server cache on disk!")
        } else {
            FFDebug("I-RDB076018", "Saved \(counter) leaf nodes for overwrite in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    func updateServerCache(merge: FCompoundWrite, atPath path: FPath) {
        let start = Date()
        var count = 0
        let batch = serverCacheDB.beginWriteBatch()
        // Remove any leaf nodes that might be higher up
        removeAllLeafNodes(on: path, batch: batch)
        merge.enumerateWrites { relativePath, node, stop in
            let childPath = path.child(relativePath)
            self.removeAllWrites(withPrefix: serverCacheKey(childPath), batch: batch, database: self.serverCacheDB)
            self.saveNodeInternal(node, atPath: childPath, batch: batch, counter: &count)
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076019", "Failed to update server cache on disk!")
        } else {
            FFDebug("I-RDB076020", "Saved \(count) leaf nodes for merge in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    private func saveNodeInternal(_ node: FNode, atPath path: FPath, batch: APLevelDBWriteBatch, counter: inout Int) {
        var writer = FJSONWriter(capacity: 64)
        saveNode(node, forKey: serverCacheKey(path), batch: batch, writer: &writer, counter: &counter)
    }

    /// Stores a node's leaves, each at its path's key, as
    /// `val(forExport: true)` has them: priorities at ".priority", and a leaf
    /// with a priority at ".value".
    private func saveNode(_ node: FNode, forKey key: String, batch: APLevelDBWriteBatch,
                          writer: inout FJSONWriter, counter: inout Int) {
        let priority = node.getPriority()
        switch node.type {
        case .empty:
            return
        case .leaf(let value):
            if priority.isEmpty {
                saveLeaf(value, forKey: key, batch: batch, writer: &writer, counter: &counter)
                return
            }
            saveLeaf(value, forKey: key + kPayloadValue + "/", batch: batch, writer: &writer, counter: &counter)
        case .children(let children):
            for (childKey, child) in children {
                saveNode(child, forKey: key + childKey.key + "/", batch: batch, writer: &writer, counter: &counter)
            }
        }
        if case .leaf(let value) = priority.type {
            saveLeaf(value, forKey: key + kPayloadPriority + "/", batch: batch, writer: &writer, counter: &counter)
        }
    }

    private func saveLeaf(_ value: LeafValue, forKey key: String, batch: APLevelDBWriteBatch,
                          writer: inout FJSONWriter, counter: inout Int) {
        writer.reset()
        do {
            try writer.write(FNode.leaf(value))
        } catch {
            fatalError("Failed to serialize primitive: \(error)")
        }
        writer.buffer.withUnsafeReadableBytes { batch.setBytes($0, forKey: key) }
        counter += 1
    }

    var serverCacheEstimatedSizeInBytes: Int {
        // Use the exact size, because for pruning the approximate size can lead to
        // weird situations where we prune everything because no compaction is ever
        // run
        serverCacheDB.exactSize(from: kFServerCachePrefix,
                                to: kFServerCacheRangeEnd)
    }

    func pruneCache(_ pruneForest: FPruneForest, atPath path: FPath) {
        // TODO: be more intelligent, don't scan entire database...
        var pruned = 0
        var kept = 0
        let start = Date()

        let prefix = serverCacheKey(path)
        let batch = serverCacheDB.beginWriteBatch()
        serverCacheDB.enumerateKeys(withPrefix: prefix) { (dbKey: String, stop) in
            let index = dbKey.index(dbKey.startIndex, offsetBy: prefix.count)
            let pathStr = String(dbKey[index...])
            let relativePath = FPath(with: pathStr)
            if pruneForest.shouldPruneUnkeptDescendants(atPath: relativePath) {
                pruned += 1
                batch.removeKey(dbKey)
            } else {
                kept += 1
            }
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076021", "Failed to prune cache on disk!")
        } else {
            FFDebug("I-RDB076022", "Pruned \(pruned) paths, kept \(kept) paths in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    // MARK: Tracked queries

    func loadTrackedQueries() -> [FTrackedQuery] {
        let date = Date()
        var trackedQueries: [FTrackedQuery] = []
        serverCacheDB.enumerateKeys(withPrefix: kFTrackedQueriesPrefix, asData: { key, data, stop in
            do {
                guard let queryJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                guard let queryId = queryJSON[kFTrackedQueryId] as? Int else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                guard let pathString = queryJSON[kFTrackedQueryPath] as? String else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                let path = FPath(with: pathString)
                guard let queryObject = queryJSON[kFTrackedQueryParams] as? [String: Any] else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                let params = FQueryParams.fromQueryObject(queryObject)
                let query = FQuerySpec(path: path, params: params)
                guard let isComplete = queryJSON[kFTrackedQueryIsComplete] as? Bool else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                guard let isActive = queryJSON[kFTrackedQueryIsActive] as? Bool else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                guard let lastUse = queryJSON[kFTrackedQueryLastUse] as? TimeInterval else {
                    throw FLevelDBStorageEngineError.decodingError
                }
                let trackedQuery = FTrackedQuery(id: queryId,
                                                 query: query,
                                                 lastUse: lastUse,
                                                 isActive: isActive,
                                                 isComplete: isComplete)
                trackedQueries.append(trackedQuery)

            } catch {
                if (error as NSError).code == kFNanFailureCode {
                    FFWarn(
                        "I-RDB076023",
                        "Failed to deserialize tracked query (\(String(data: data, encoding: .utf8) ?? "-")), likely because of out of range doubles (Error: \(error))")
                    FFWarn("I-RDB076024",
                           "Removing failed tracked query with key \(key)")
                    _ = self.serverCacheDB.removeKey(key)
                } else {
                    fatalError("Failed to deserialize tracked query: \(error)")
                }

            }
        })
        FFDebug("I-RDB076025", "Loaded \(trackedQueries.count) tracked queries in \(date.timeIntervalSinceNow * -1000)ms")
        return trackedQueries
    }

    func removeTrackedQuery(_ queryId: Int) {
        let start = Date()
        let batch = serverCacheDB.beginWriteBatch()
        batch.removeKey(trackedQueryKey(trackedQueryId: queryId))
        var keyCount = 0
        serverCacheDB.enumerateKeys(withPrefix: trackedQueryKeysKeyPrefix(trackedQueryId: queryId), usingBlock: { key, stop in
            batch.removeKey(key)
            keyCount += 1
        })
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076026", "Failed to remove tracked query on disk!")
        } else {
            FFDebug("I-RDB076027", "Removed query with id \(queryId) (and removed \(keyCount) keys) in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    func saveTrackedQuery(_ query: FTrackedQuery) {
        let start = Date()
        let trackedQuery: [String: Any] = [
            kFTrackedQueryId : query.queryId,
            kFTrackedQueryPath : query.query.path.toStringWithTrailingSlash(),
            kFTrackedQueryParams : query.query.params.wireProtocolParams,
            kFTrackedQueryLastUse : query.lastUse,
            kFTrackedQueryIsComplete : query.isComplete,
            kFTrackedQueryIsActive : query.isActive
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: trackedQuery)
            _ = serverCacheDB.setData(data, forKey: trackedQueryKey(trackedQueryId: query.queryId))
        } catch {
            assertionFailure("Failed to serialize tracked query (Error: \(error)")
        }
        FFDebug("I-RDB076028", "Saved tracked query \(query.queryId) in \(start.timeIntervalSinceNow * -1000)ms")
    }

    func setTrackedQueryKeys(_ keys: Set<String>, forQueryId queryId: Int) {
        let start = Date()
        var removed = 0
        var added = 0
        let batch = serverCacheDB.beginWriteBatch()
        var seenKeys: Set<String> = []
        // First, delete any keys that might be stored and are not part of the
        // current keys
        serverCacheDB.enumerateKeys(withPrefix: trackedQueryKeysKeyPrefix(trackedQueryId: queryId), asStrings: { dbKey, actualKey, stop in
            if keys.contains(actualKey) {
                // Already in DB
                seenKeys.insert(actualKey)
            } else {
                // Not part of set, delete key
                batch.removeKey(dbKey)
                removed += 1
            }
        })
        // Next add any keys that are missing in the database
        for childKey in keys {
            if !seenKeys.contains(childKey) {
                batch.setString(childKey, forKey: trackedQueryKeysKey(trackedQueryId: queryId, key: childKey))
                added += 1
            }
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076029", "Failed to set tracked queries on disk!")
        } else {
            FFDebug("I-RDB076030", "Set \(keys.count) tracked keys (\(added) added, \(removed) removed) for query \(queryId) in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    func updateTrackedQueryKeys(addedKeys added: Set<String>, removedKeys removed: Set<String>, forQueryId queryId: Int) {
        let start = Date()
        let batch = serverCacheDB.beginWriteBatch()
        for key in removed {
            batch.removeKey(trackedQueryKeysKey(trackedQueryId: queryId, key: key))
        }
        for key in added {
            batch.setString(key, forKey: trackedQueryKeysKey(trackedQueryId: queryId, key: key))
        }
        let success = batch.commit()
        if !success {
            FFWarn("I-RDB076031", "Failed to update tracked queries on disk!")
        } else {
            FFDebug("I-RDB076032", "Added \(added.count) tracked keys, removed \(removed.count) for query \(queryId) in \(start.timeIntervalSinceNow * -1000)ms")
        }
    }

    func trackedQueryKeysForQuery(_ queryId: Int) -> Set<String> {
        let start = Date()
        var set: Set<String> = []

        serverCacheDB.enumerateKeys(withPrefix: trackedQueryKeysKeyPrefix(trackedQueryId: queryId), asStrings: { dbKey, actualKey, stop in
            set.insert(actualKey)
        })

        FFDebug("I-RDB076033", "Loaded \(set.count) tracked keys for query \(queryId) in \(start.timeIntervalSinceNow * -1000)ms")
        return set
    }

}
