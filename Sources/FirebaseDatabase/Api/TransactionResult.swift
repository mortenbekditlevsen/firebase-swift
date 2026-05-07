//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 21/04/2022.
//

import Foundation

/**
 * Used for runTransactionBlock:. An FIRTransactionResult instance is a
 * container for the results of the transaction.
 */
struct TransactionResult {
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
    static func successWithValue(_ value: MutableData) -> TransactionResult {
        .init(result: .success(value))
    }

    /**
     * Used for runTransactionBlock:. Indicates that the current transaction should
     * no longer proceed.
     *
     * @return An FIRTransactionResult instance that can be used as a return value
     * from the block given to runTransactionBlock:
     */
    static func abort() -> TransactionResult {
        .init(result: .failure(.aborted))
    }
}
