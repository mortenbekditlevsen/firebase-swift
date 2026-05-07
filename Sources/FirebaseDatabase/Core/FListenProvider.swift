//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 27/03/2022.
//

import Foundation

typealias fbt_startListeningBlock = (FQuerySpec, Int?, FSyncTreeHash, @escaping (String) -> [FEvent]) -> [FEvent]

typealias fbt_stopListeningBlock = (FQuerySpec, Int?) -> Void

class FListenProvider {
    internal init(startListening: @escaping fbt_startListeningBlock, stopListening: @escaping fbt_stopListeningBlock) {
        self.startListening = startListening
        self.stopListening = stopListening
    }

    var startListening: fbt_startListeningBlock
    var stopListening: fbt_stopListeningBlock
}
