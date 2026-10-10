import Foundation
import SwiftUI

enum DurationUnit: String, CaseIterable, Identifiable {
    case seconds = "s", minutes = "m", hours = "h"
    var id: String { rawValue }
    var title: String { switch self { case .seconds: "秒"; case .minutes: "分钟"; case .hours: "小时" } }
    var multiplier: Double { switch self { case .seconds: 1; case .minutes: 60; case .hours: 3600 } }
}

// Keep Go duration strings at the boundary; the UI edits a number and a unit.
enum DurationValue {
    static func seconds(_ raw: String) -> Double? {
        let raw = raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
        let pattern = "(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(ns|us|µs|μs|ms|s|m|h)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, range: range)
        guard !matches.isEmpty, matches.reduce(0, { $0 + $1.range.length }) == range.length else { return nil }
        var total = 0.0
        for match in matches {
            guard let wholeRange = Range(match.range, in: raw), let unitRange = Range(match.range(at: 1), in: raw) else { return nil }
            let unit = String(raw[unitRange])
            guard let number = Double(raw[wholeRange].dropLast(unit.count)) else { return nil }
            let multiplier = ["ns": 1e-9, "us": 1e-6, "µs": 1e-6, "μs": 1e-6, "ms": 0.001, "s": 1, "m": 60, "h": 3600][unit]!
            total += number * multiplier
        }
        return total.isFinite && total <= 9_223_372_036.854775 ? total : nil
    }
    static func preferredUnit(_ raw: String) -> DurationUnit {
        guard let seconds = seconds(raw), seconds > 0 else { return .seconds }
        if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 { return .hours }
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 { return .minutes }
        return .seconds
    }
    static func number(_ value: Double) -> String {
        var text = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
    static func number(_ raw: String, in unit: DurationUnit) -> String {
        if raw.hasSuffix(unit.rawValue) {
            let text = String(raw.dropLast())
            if seconds(raw) == nil || Double(text) != nil || text.isEmpty { return text }
        }
        return seconds(raw).map { number($0 / unit.multiplier) } ?? raw
    }
    static func validation(_ raw: String, minimum: Double = 0) -> String? {
        guard let seconds = seconds(raw) else { return "请输入有效数字" }
        if seconds <= 0 { return "时间须大于 0" }
        if seconds < 1e-9 { return "时间过短" }
        if seconds < minimum { return "至少 \(number(minimum)) 秒" }
        return nil
    }
}

struct DurationInput: View {
    let title: String
    let help: String
    let minimum: Double
    @Binding var value: String
    @ViewState private var unit: DurationUnit

    init(_ title: String, value: Binding<String>, help: String = "", minimum: Double = 0) {
        self.title = title; self.help = help; self.minimum = minimum; _value = value
        _unit = State(initialValue: DurationValue.preferredUnit(value.wrappedValue))
    }
    private var number: Binding<String> {
        Binding(get: { DurationValue.number(value, in: unit) }, set: {
            value = $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".") + unit.rawValue
        })
    }
    private var selectedUnit: Binding<DurationUnit> {
        Binding(get: { unit }, set: { newUnit in
            let number = DurationValue.number(value, in: unit)
            unit = newUnit
            value = number + newUnit.rawValue
        })
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    TextField("数值", text: number).multilineTextAlignment(.trailing).monospacedDigit()
                        .textFieldStyle(.roundedBorder).frame(width: 82).accessibilityLabel(title + "数值")
                    Picker(title + "单位", selection: selectedUnit) {
                        ForEach(DurationUnit.allCases) { unit in Text(unit.title).tag(unit) }
                    }.labelsHidden().frame(width: 84)
                }
                if let message = DurationValue.validation(value, minimum: minimum) {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).help(help)
            .onChange(of: value) { newValue in
                // External refresh or Undo can restore a different unit.
                if !newValue.hasSuffix(unit.rawValue), DurationValue.seconds(newValue) != nil {
                    unit = DurationValue.preferredUnit(newValue)
                }
            }
    }
}
