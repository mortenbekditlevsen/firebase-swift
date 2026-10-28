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

public struct FQuerySpec: Hashable, Sendable {
    public let path: FPath
    public let params: FQueryParams
    init(path: FPath, params: FQueryParams) {
        self.params = params
        self.path = path
    }

    static func defaultQueryAtPath(_ path: FPath) -> FQuerySpec {
        FQuerySpec(path: path, params: .defaultInstance)
    }

    var index: FIndex {
        params.index
    }
    var isDefault: Bool {
        params.isDefault
    }
    var loadsAllData: Bool {
        params.loadsAllData
    }

    var description: String {
        "FQuerySpec (path: \(path), params: \(params)"
    }
}
