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

/**
 * Used for runTransactionBlock:. An FIRTransactionResult instance is a
 * container for the results of the transaction.
 */
public struct TransactionResult: Sendable {
    internal enum AbortedError: Error {
        case aborted
    }
    internal init(result: Result<MutableData, AbortedError>) {
        self.result = result
    }


    var result: Result<MutableData, AbortedError>

    /**
     * Used for runTransactionBlock:. Indicates that the new value should be saved
     * at this location
     *
     * @param value A FIRMutableData instance containing the new value to be set
     * @return An FIRTransactionResult instance that can be used as a return value
     * from the block given to runTransactionBlock:
     */
    public static func success(withValue value: MutableData) -> TransactionResult {
        .init(result: .success(value))
    }

    /**
     * Used for runTransactionBlock:. Indicates that the current transaction should
     * no longer proceed.
     *
     * @return An FIRTransactionResult instance that can be used as a return value
     * from the block given to runTransactionBlock:
     */
    public static func abort() -> TransactionResult {
        .init(result: .failure(.aborted))
    }
}
