//
//  Timestamp.swift
//  firebase-swift
//
//  Created by Morten Bek Ditlevsen on 03/06/2026.
//

import Foundation

/// A `Timestamp` represents a point in time independent of any time zone or calendar, represented
/// as seconds and fractions of seconds at nanosecond resolution in UTC Epoch time. It is encoded
/// using the Proleptic Gregorian Calendar which extends the Gregorian calendar backwards to year
/// one. It is encoded assuming all minutes are 60 seconds long, i.e. leap seconds are "smeared" so
/// that no leap second table is needed for interpretation. Range is from 0001-01-01T00:00:00Z to
/// 9999-12-31T23:59:59.999999999Z. By restricting to that range, we ensure that we can convert to
/// and from RFC 3339 date strings.
///
/// See the [reference timestamp definition](https://github.com/google/protobuf/blob/main/src/google/protobuf/timestamp.proto).
public struct Timestamp: Sendable, Hashable {
    /// Represents seconds of UTC time since Unix epoch 1970-01-01T00:00:00Z.
    /// Must be from 0001-01-01T00:00:00Z to 9999-12-31T23:59:59Z inclusive.
    public let seconds: Int64

    /// Non-negative fractions of a second at nanosecond resolution. Negative second values with
    /// fractions must still have non-negative nanos values that count forward in time.
    /// Must be from 0 to 999,999,999 inclusive.
    public let nanoseconds: Int32

    /// Creates a new timestamp.
    ///
    /// - Parameters:
    ///   - seconds: The number of seconds since epoch.
    ///   - nanoseconds: The number of nanoseconds after the seconds.
    public init(seconds: Int64, nanoseconds: Int32) {
        precondition(
            nanoseconds >= 0 && nanoseconds < 1_000_000_000,
            "Timestamp nanoseconds out of range: \(nanoseconds)"
        )
        precondition(
            seconds >= -62_135_596_800 && seconds < 253_402_300_800,
            "Timestamp seconds out of range: \(seconds)"
        )
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }

    /// Creates a new timestamp from the given date.
    ///
    /// - Parameter date: The date to convert to a timestamp.
    public init(date: Date) {
        var secondsDouble = 0.0
        var fraction = modf(date.timeIntervalSince1970, &secondsDouble)
        // GCP Timestamps always have non-negative nanos.
        if fraction < 0 {
            fraction += 1.0
            secondsDouble -= 1.0
        }
        let seconds = Int64(secondsDouble)
        let nanoseconds = Int32(fraction * 1_000_000_000)
        self.init(seconds: seconds, nanoseconds: nanoseconds)
    }

    /// Creates a new timestamp with the current date / time.
    public init() {
        self.init(date: Date())
    }

    /// Returns a new `Date` corresponding to this timestamp. This may lose precision.
    public func dateValue() -> Date {
        Date(timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000)
    }
}

// MARK: - Internal

extension Timestamp {
    var iso8601String: String {
        let secondsDate = Date(timeIntervalSince1970: Double(seconds))
        let style = Date.ISO8601FormatStyle()
            .year()
            .month()
            .day()
            .time(includingFractionalSeconds: false)
            .timeSeparator(.colon)
            .dateSeparator(.dash)
        let secondsString = style.format(secondsDate)
        // Strip the trailing "Z" — we'll add it back after appending nanoseconds.
        let trimmed = secondsString.replacingOccurrences(of: "Z", with: "")
        precondition(trimmed.count == 19, "Invalid ISO string: \(trimmed)")
        let nanosString = String(format: "%09d", nanoseconds)
        return "\(trimmed).\(nanosString)Z"
    }
}

// MARK: - Comparable

extension Timestamp: Comparable {
    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        if lhs.seconds != rhs.seconds {
            return lhs.seconds < rhs.seconds
        }
        return lhs.nanoseconds < rhs.nanoseconds
    }
}

extension Timestamp: CustomStringConvertible {
    public var description: String {
        "Timestamp(seconds: \(seconds), nanoseconds: \(nanoseconds))"
    }
}
