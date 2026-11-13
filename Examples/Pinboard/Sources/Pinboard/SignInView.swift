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

import PinboardKit
import SwiftCrossUI

/// Email and password, a new account, or anonymous with a name.
struct SignInView: View {
    let board: Board
    @State var name = ""
    @State var email = ""
    @State var password = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Pinboard")
                .font(.largeTitle)
            Text("Sign in to pin notes and files to a shared board.")
                .foregroundColor(.gray)

            TextField("Name (for new accounts and guests)", text: $name)
            TextField("Email", text: $email)
            SecureField("Password", text: $password)

            HStack {
                ActionButton("Sign in") {
                    Task { await board.signIn(email: email, password: password) }
                }
                ActionButton("Create account") {
                    Task { await board.createAccount(name: name, email: email, password: password) }
                }
                ActionButton("Continue as guest") {
                    Task { await board.signInAnonymously(name: name) }
                }
            }
            .disabled(board.isBusy)
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}
