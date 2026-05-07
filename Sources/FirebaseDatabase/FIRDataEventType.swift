//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 28/10/2021.
//

import Foundation

public enum DataEventType: Int {
    /// A new child node is added to a location.
    case childAdded
    /// A child node is removed from a location.
    case childRemoved
    /// A child node at a location changes.
    case childChanged
    /// A child node moves relative to the other child nodes at a location.
    case childMoved
    /// Any data changes at a location or, recursively, at any child node.
    case value
}
