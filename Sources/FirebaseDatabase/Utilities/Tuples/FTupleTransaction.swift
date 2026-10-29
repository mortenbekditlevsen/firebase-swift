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

@DatabaseActor
class FTupleTransaction {
    internal init(path: FPath, update: @escaping (inout MutableData) -> TransactionResult, onComplete: (@Sendable (Error?, Bool, DataSnapshot?) -> Void)?, status: FTransactionStatus, order: Int, applyLocally: Bool, retryCount: Int, unwatcher: @escaping () -> Void, abortStatus: String? = nil, abortReason: String? = nil, currentWriteId: Int, currentInputSnapshot: FNode, currentOutputSnapshotRaw: FNode, currentOutputSnapshotResolved: FNode) {
        self.path = path
        self.update = update
        self.onComplete = onComplete
        self.status = status
        self.order = order
        self.applyLocally = applyLocally
        self.retryCount = retryCount
        self.unwatcher = unwatcher
        self.abortStatus = abortStatus
        self.abortReason = abortReason
        self.currentWriteId = currentWriteId
        self.currentInputSnapshot = currentInputSnapshot
        self.currentOutputSnapshotRaw = currentOutputSnapshotRaw
        self.currentOutputSnapshotResolved = currentOutputSnapshotResolved
    }

    let path: FPath
    let update: (inout MutableData) -> TransactionResult // fbt_transactionresult_mutabledata
    let onComplete: (@Sendable (Error?, Bool, DataSnapshot?) -> Void)? // fbt_void_nserror_bool_datasnapshot
    var status: FTransactionStatus

    /**
     * Used when combining transaction at different locations to figure out which
     * one goes first.
     */
    let order: Int

    /**
     * Whether to raise local events for this transaction
     */
    let applyLocally: Bool

    /**
     * Count how many times we've retried the transaction
     */
    var retryCount: Int


    /**
     * Function to call to clean up our listener
     */
    let unwatcher: () -> Void

    /**
     * Stores why a transaction was aborted
     */
    private(set) var abortStatus: String?
    private(set) var abortReason: String?

    func setAbortStatus(abortStatus: String?, reason: String?) {
        self.abortStatus = abortStatus
        self.abortReason = reason
    }

    var abortError: Error? {
        abortStatus.flatMap { FUtilities.error(for: $0, reason: abortReason) }
    }


    var currentWriteId: Int

    /**
     * Stores the input snapshot, before the update
     */
    var currentInputSnapshot: FNode

    /**
     * Stores the unresolved (for server values) output snapshot, after the update
     */
    var currentOutputSnapshotRaw: FNode

    /**
     * Stores the resolved (for server values) output snapshot, after the update
     */
    var currentOutputSnapshotResolved: FNode
}
