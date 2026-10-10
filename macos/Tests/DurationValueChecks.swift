import Foundation

@main enum DurationValueChecks {
    static func main() {
        let cases: [(String, Double, DurationUnit, String)] = [
            ("60s", 60, .minutes, "1"), ("2m", 120, .minutes, "2"),
            ("1h", 3600, .hours, "1"), ("1h30m", 5400, .minutes, "90"),
            ("15s", 15, .seconds, "15"), ("1.5m", 90, .seconds, "90"),
            ("500ms", 0.5, .seconds, "0.5"), ("1µs", 1e-6, .seconds, "0.000001"),
            ("1ns", 1e-9, .seconds, "0.000000001"), (".5s", 0.5, .seconds, ".5"),
            ("+5m", 300, .minutes, "+5")
        ]
        for (raw, seconds, unit, number) in cases {
            precondition(abs(DurationValue.seconds(raw)! - seconds) < 1e-10, raw)
            precondition(DurationValue.preferredUnit(raw) == unit, raw)
            precondition(DurationValue.number(raw, in: unit) == number, raw)
            let roundtrip = DurationValue.seconds(number + unit.rawValue)!
            precondition(abs(roundtrip - seconds) < 1e-8, raw + " changed during conversion")
        }
        for raw in ["", "abc", "2", "2mx", "1e3s", "-2m", " 2m", "1h 30m", "1..5s", "1e99h"] {
            precondition(DurationValue.seconds(raw) == nil, raw + " should be invalid")
        }
        precondition(DurationValue.validation("0s") != nil)
        precondition(DurationValue.validation("0.1ns") != nil)
        precondition(DurationValue.validation("0.5s", minimum: 1) != nil)
        precondition(DurationValue.validation("1s", minimum: 1) == nil)
        precondition(DurationValue.number("abcm", in: .minutes) == "abc", "Keep invalid input visible for correction")
        print("Duration checks passed: units, fractional and compound durations, validation, roundtrips.")
    }
}
