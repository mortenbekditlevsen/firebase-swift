// Copyright 2017 Google LLC
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

import Foundation

typealias fbt_startListeningBlock = (FQuerySpec, Int?, FSyncTreeHash, @escaping @Sendable (String) -> [FEvent]) -> [FEvent]

typealias fbt_stopListeningBlock = (FQuerySpec, Int?) -> Void

class FListenProvider {
    internal init(startListening: @escaping @Sendable fbt_startListeningBlock, stopListening: @escaping @Sendable fbt_stopListeningBlock) {
        self.startListening = startListening
        self.stopListening = stopListening
    }

    var startListening: fbt_startListeningBlock
    var stopListening: fbt_stopListeningBlock
}
