// Copyright 2025 Google LLC
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

#ifndef FIRESTORE_INTERNAL_H_
#define FIRESTORE_INTERNAL_H_

// This header is the public interface for the FirebaseFirestoreInternalWrapper
// module. It exposes C++ types to Swift via Swift's C++ interoperability.
//
// Paths are relative to the include/ directory.

// Public value types
#include "../core/include/firebase/firestore/geo_point.h"
#include "../core/include/firebase/firestore/timestamp.h"
#include "../core/include/firebase/firestore/firestore_errors.h"

// API types directly importable by Swift
#include "../core/src/api/source.h"
#include "../core/src/api/snapshot_metadata.h"

// C++ bridge wrappers for Swift interop
#include "FirestoreBridge.h"

#endif  // FIRESTORE_INTERNAL_H_
