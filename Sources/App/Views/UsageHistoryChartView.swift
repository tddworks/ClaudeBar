import Charts
import SwiftUI
import Domain

/// *DAILY USAGE — LAST 30 DAYS* — a login's usage history as a chart: one
/// bar a day, by cost, by tokens (input and output), or by cache (writes and
/// reads), each with its thirty-day total. Hovering a bar shows its day.
struct UsageHistoryChartView: View {
    let days: [DailyUsageStat]
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var measure: Measure
    @State private var selectedDate: Date?
    @State private var isVisible: Bool

    /// - Parameter shown: starts visible instead of fading in — for a still image.
    init(days: [DailyUsageStat], delay: Double, measure: Measure = .cost, shown: Bool = false) {
        self.days = days
        self.delay = delay
        _measure = State(initialValue: measure)
        _isVisible = State(initialValue: shown)
    }

    enum Measure: String, CaseIterable, Identifiable {
        case cost = "Cost"
        case tokens = "Tokens"
        case cache = "Cache"

        var id: String { rawValue }
    }

    /// One stacked part of one day's bar.
    private struct Segment: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 4) {
                ForEach(Measure.allCases) { choice in
                    chip(choice)
                }
                Spacer(minLength: 0)
                legend
            }

            chart
                .frame(height: 110)
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient).themeShadow(theme)
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
            }
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(delay)) { isVisible = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(colors[0])
                Text("DAILY USAGE — LAST 30 DAYS")
                    .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(headline)
                    .font(theme.displayFont(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Text(caption)
                    .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func chip(_ choice: Measure) -> some View {
        let isOn = measure == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { measure = choice }
        } label: {
            Text(choice.rawValue)
                .font(.system(size: 9, weight: isOn ? .bold : .medium, design: theme.fontDesign))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isOn ? theme.progressTrack : Color.clear))
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The colours' names, when a bar has more than one part.
    @ViewBuilder
    private var legend: some View {
        if kinds.count > 1 {
            HStack(spacing: 8) {
                ForEach(Array(zip(kinds, colors)), id: \.0) { kind, color in
                    HStack(spacing: 3) {
                        Circle().fill(color).frame(width: 5, height: 5)
                        Text(kind)
                            .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    private var selectedDay: DailyUsageStat? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    /// The hovered day's value, else the thirty-day total.
    private var headline: String {
        if let day = selectedDay { return value(of: day) }
        switch measure {
        case .cost: return Self.money(days.reduce(Decimal(0)) { $0 + $1.totalCost })
        case .tokens: return Self.count(days.reduce(0) { $0 + $1.inputTokens + $1.outputTokens })
        case .cache: return Self.count(days.reduce(0) { $0 + $1.totalCacheTokens })
        }
    }

    private var caption: String {
        selectedDay?.formattedDate ?? "30-day total"
    }

    private func value(of day: DailyUsageStat) -> String {
        switch measure {
        case .cost: Self.money(day.totalCost)
        case .tokens: Self.count(day.inputTokens + day.outputTokens)
        case .cache: Self.count(day.totalCacheTokens)
        }
    }

    // MARK: - Chart

    private var colors: [Color] {
        switch measure {
        case .cost: [.yellow]
        case .tokens: [.green, .mint]
        case .cache: [.blue, .cyan]
        }
    }

    private var segments: [Segment] {
        days.flatMap { day -> [Segment] in
            switch measure {
            case .cost:
                [Segment(date: day.date, kind: "Cost", value: NSDecimalNumber(decimal: day.totalCost).doubleValue)]
            case .tokens:
                [Segment(date: day.date, kind: "Input", value: Double(day.inputTokens)),
                 Segment(date: day.date, kind: "Output", value: Double(day.outputTokens))]
            case .cache:
                [Segment(date: day.date, kind: "Cache write", value: Double(day.cacheCreationTokens)),
                 Segment(date: day.date, kind: "Cache read", value: Double(day.cacheReadTokens))]
            }
        }
    }

    private var kinds: [String] {
        switch measure {
        case .cost: ["Cost"]
        case .tokens: ["Input", "Output"]
        case .cache: ["Cache write", "Cache read"]
        }
    }

    private var chart: some View {
        Chart(segments) { segment in
            BarMark(
                x: .value("Day", segment.date, unit: .day),
                y: .value(measure.rawValue, segment.value)
            )
            .foregroundStyle(by: .value("Kind", segment.kind))
            .opacity(selectedDate == nil || Calendar.current.isDate(segment.date, inSameDayAs: selectedDate!) ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: kinds, range: colors)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(.system(size: 7, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(theme.progressTrack)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(measure == .cost ? Self.money(Decimal(amount), whole: true) : Self.count(Int(amount)))
                            .font(.system(size: 7, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: measure)
    }

    // MARK: - Formatting

    static func money(_ amount: Decimal, whole: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = whole ? 0 : 2
        formatter.minimumFractionDigits = whole ? 0 : 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    static func count(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000_000...: short(Double(tokens) / 1_000_000_000) + "B"
        case 1_000_000...: short(Double(tokens) / 1_000_000) + "M"
        case 1_000...: short(Double(tokens) / 1_000) + "K"
        default: "\(tokens)"
        }
    }

    /// One decimal, without a trailing ".0" — "2.5", "500".
    private static func short(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
