//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

protocol FEvent {
    var path: FPath? { get }
    func fireEventOnQueue()
    var isCancelEvent: Bool { get }
    var description: String { get }
}
