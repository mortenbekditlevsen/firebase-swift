//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation


class FCancelEvent: FEvent {
    var eventRegistration: FEventRegistration
    var error: Error
    var path: FPath? {
        _path
    }
    let _path: FPath

    init(eventRegistration: FEventRegistration, error: Error, path: FPath) {
        self.eventRegistration = eventRegistration
        self.error = error
        self._path = path
    }

    func fireEventOnQueue(_ queue: DispatchQueue) {
        eventRegistration.fireEvent(self, queue: queue)
    }
    var isCancelEvent: Bool { true }
    var description: String {
        "\(_path): cancel"
    }
}
