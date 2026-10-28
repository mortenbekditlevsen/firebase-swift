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
