//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 18/04/2023.
//

import FirebaseSharedSwift
import Foundation

enum InternalError: Error {
    case error
}

@available(iOS 13.0, *)
extension DatabaseQuery {
    public func get<T: Decodable>(as type: T.Type,
                           decoder: Database.Decoder =
                           Database.Decoder()) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.getData { error, snapshot in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    do {
                        let data = try snapshot.data(as: T.self, decoder: decoder)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: InternalError.error)
                }
            }

        }
    }

    public func observeSingle<T: Decodable>(as type: T.Type,
                           decoder: Database.Decoder =
                           Database.Decoder()) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.observeSingleEventOfType(.value) { snapshot in
                do {
                    let data = try snapshot.data(as: T.self, decoder: decoder)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

        }
    }

}
