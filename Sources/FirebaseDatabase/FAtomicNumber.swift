//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 29/10/2021.
//

import Atomics

final class FAtomicNumber: Sendable {
    let counter = ManagedAtomic<Int>(1)
    func getAndIncrement() -> Int {
        counter.wrappingIncrement(ordering: .relaxed)
        return counter.load(ordering: .relaxed)
    }
}
