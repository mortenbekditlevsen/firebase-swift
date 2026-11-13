// Copyright 2026 Google LLC
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

import DefaultBackend
import PinboardKit
import SwiftCrossUI

@main
struct PinboardApp: App {
    @State var board: Board

    init() {
        FirebaseSetup.configure()
        board = Board()
    }

    var body: some Scene {
        WindowGroup("Pinboard") {
            RootView(board: board)
                .task { await board.run() }
        }
        .defaultSize(width: 900, height: 640)
    }
}

struct RootView: View {
    @Bindable var board: Board

    var body: some View {
        VStack {
            if board.user == nil {
                SignInView(board: board)
            } else {
                BoardView(board: board)
            }
        }
        .alert($board.errorMessage) {
            Button("OK") {}
        }
    }
}
