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

/// The time source of the connection: real time, or a manual clock in tests.
struct DatabaseClock: Sendable {
    /// Sleeps for the duration; throws when cancelled.
    let sleep: @Sendable (Duration) async throws -> Void
    /// Monotonic time since an arbitrary origin.
    let now: @Sendable () -> Duration

    init<C: Clock<Duration>>(_ clock: C) {
        let origin = clock.now
        sleep = { try await clock.sleep(for: $0) }
        now = { origin.duration(to: clock.now) }
    }

    static let continuous = DatabaseClock(ContinuousClock())
}

/// The delays between connection attempts (upstream's FIRRetryHelper): none
/// after a success, then from `minDelay` growing by `multiplier` up to
/// `maxDelay`, each shortened by a random part of up to `jitter`.
struct Backoff {
    var minDelay: Duration = .seconds(kPersistentConnReconnectMinDelay)
    var maxDelay: Duration = .seconds(kPersistentConnReconnectMaxDelay)
    var multiplier = kPersistentConnReconnectMultiplier
    var jitter = 0.7
    var random: @Sendable () -> Double = { Double.random(in: 0 ..< 1) }

    private var current: Duration = .zero
    private var lastWasSuccess = true

    /// The delay before the next attempt.
    mutating func nextDelay() -> Duration {
        defer { lastWasSuccess = false }
        guard !lastWasSuccess else { return .zero }
        current = current == .zero ? minDelay : min(current * multiplier, maxDelay)
        return current * (1 - jitter) + current * (jitter * random())
    }

    /// The next attempt follows at once, and later delays start over.
    mutating func reset() {
        lastWasSuccess = true
        current = .zero
    }
}
