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

import SwiftCrossUI

/// A button whose title shows on macOS 26 and later: a borderless one, in blue.
///
/// SwiftCrossUI 0.10's AppKit backend adds a bordered button's bezel (an
/// `NSButton`) after its label, so the bezel is drawn on top and hides the
/// title until it's pressed. Borderless buttons have no bezel.
struct ActionButton: View {
    var title: String
    var action: @MainActor @Sendable () -> Void
    @Environment(\.isEnabled) var isEnabled

    init(_ title: String, action: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .foregroundColor(isEnabled ? .blue : .gray)
    }
}
