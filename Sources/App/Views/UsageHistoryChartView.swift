import Charts
import SwiftUI
import Domain

/// *DAILY USAGE — LAST 30 DAYS* — a login's usage history as a chart: one
/// bar a day, with two choices — what is counted (cost, tokens or cache)
/// and how the bars split (by kind, or by model, from the day's lines).
/// Hovering a bar shows its day, named by model when split by model.
/// Everything it says, `Days` answers.
struct UsageHistoryChartView: View {
    let days: Days
    let delay: Double
    @State private var count: Count
    @State private var split: Split
    @State private var selectedDate: Date?
    @State private var isVisible: Bool

    @Environment(\.appTheme) private var theme

    /// - Parameter shown: starts visible instead of fading in — for a still image.
    init(days: Days, delay: Double, shown: Bool = false) {
        self.days = days
        self.delay = delay
        _count = State(initialValue: days.knowsCost ? .cost : .tokens)
        _split = State(initialValue: .kind)
        _isVisible = State(initialValue: shown)
    }

    /// What is counted — cost only when the login is priced.
    enum Count: String, CaseIterable, Identifiable {
        case cost = "Cost"
        case tokens = "Tokens"
        case cache = "Cache"

        var id: String { rawValue }
    }

    /// How the bars split — by model only when the log names models.
    enum Split: String, CaseIterable, Identifiable {
        case kind = "by kind"
        case models = "by model"

        var id: String { rawValue }
    }

    /// The count on show — the chosen one, unless it is no longer offered.
    private var shownCount: Count {
        count == .cost && !days.knowsCost ? .tokens : count
    }

    /// The split on show — the chosen one, unless it is no longer offered.
    private var shownSplit: Split {
        split == .models && !days.hasModels ? .kind : split
    }

    private var countSelection: Binding<Count> {
        Binding(get: { shownCount }, set: { count = $0 })
    }

    private var splitSelection: Binding<Split> {
        Binding(get: { shownSplit }, set: { split = $0 })
    }

    private var counts: [Count] { days.knowsCost ? Count.allCases : Count.allCases.filter { $0 != .cost } }

    private var splits: [Split] { days.hasModels ? Split.allCases : [.kind] }

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
                if theme.isOutlined {
                    InkSegmentedPicker(title: "Count", options: counts, selection: countSelection, label: \.rawValue)
                    if days.hasModels {
                        InkSegmentedPicker(title: "Split", options: splits, selection: splitSelection, label: \.rawValue)
                    }
                } else {
                    ForEach(counts) { choice in
                        chip(choice, selection: countSelection, shown: shownCount)
                    }
                    if days.hasModels {
                        ForEach(splits) { choice in
                            chip(choice, selection: splitSelection, shown: shownSplit)
                        }
                    }
                }
                Spacer(minLength: 0)
                legend
            }
            if shownSplit == .models {
                modelsLegend
            }

            chart
                .frame(height: 110)
            if shownSplit == .models, let day = selectedDay {
                modelsDetail(for: day)
            }
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
        .themeRivets()
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
                    .font(theme.font(size: 8, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(headline)
                    .font(theme.displayFont(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Text(caption)
                    .font(theme.font(size: 8, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func chip<T: Identifiable & Equatable>(_ choice: T, selection: Binding<T>, shown: T) -> some View where T.ID == String {
        let isOn = shown == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection.wrappedValue = choice }
        } label: {
            Text(choice.id)
                .font(theme.font(size: 9, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.controlShape.fill(isOn ? theme.progressTrack : Color.clear))
                .overlay(theme.controlShape.stroke(theme.glassBorder, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The colours' names, when a bar has more than one part. Models keep
    /// their names in the wrapped key under the controls.
    @ViewBuilder
    private var legend: some View {
        if shownSplit != .models, kinds.count > 1 {
            HStack(spacing: 8) {
                ForEach(Array(zip(kinds, colors)), id: \.0) { kind, color in
                    HStack(spacing: 3) {
                        Circle().fill(color).frame(width: 5, height: 5)
                        Text(kind)
                            .font(theme.font(size: 8, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    /// The models' colour key, wrapped — a log may name several.
    private var modelsLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 4) {
            ForEach(modelKinds, id: \.self) { model in
                HStack(spacing: 3) {
                    Circle().fill(color(of: model)).frame(width: 5, height: 5)
                    Text(ModelUsageLine.displayName(model))
                        .font(theme.font(size: 8, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var selectedDay: DailyUsageStat? {
        guard let selectedDate else { return nil }
        return days.stats.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    /// The hovered day's value, else the thirty-day total — in the count's
    /// unit, which `Days` carries.
    private var headline: String {
        if let day = selectedDay { return unit(days.value(of: day)) }
        return unit(days.total)
    }

    private var caption: String {
        selectedDay?.formattedDate ?? "30-day total"
    }

    private func unit(_ value: Double) -> String {
        shownCount == .cost ? Self.money(Decimal(value)) : Self.count(Int(value))
    }

    // MARK: - Chart

    /// The models the days name, and the unnamed line when a day holds one.
    private var modelKinds: [String] {
        let unnamed = days.stats.contains { $0.lines.contains { $0.model.isEmpty } }
        return unnamed ? days.models + [""] : days.models
    }

    private var kinds: [String] {
        switch shownSplit {
        case .models: modelKinds
        case .kind:
            switch shownCount {
            case .cost: ["Cost"]
            case .tokens: ["Input", "Output"]
            case .cache: ["Cache write", "Cache read"]
            }
        }
    }

    private var colors: [Color] {
        switch shownSplit {
        case .models: modelColors
        case .kind:
            switch shownCount {
            case .cost: [.yellow]
            case .tokens: [.green, .mint]
            case .cache: [.blue, .cyan]
            }
        }
    }

    /// The models' colours — hues far apart, cycled when the log names more
    /// models than the palette holds. The unnamed line is grey.
    private static let modelPalette: [Color] = [.purple, .green, .blue, .orange, .pink, .cyan, .indigo, .mint, .red]

    private var modelColors: [Color] {
        modelKinds.map { kind in
            guard let index = days.models.firstIndex(of: kind) else { return Color.gray }
            return Self.modelPalette[index % Self.modelPalette.count]
        }
    }

    /// The colour the chart gives `model` — its place among the days' models.
    private func color(of model: String) -> Color {
        guard let index = days.models.firstIndex(of: model) else { return Color.gray }
        return Self.modelPalette[index % Self.modelPalette.count]
    }

    private var segments: [Segment] {
        days.stats.flatMap { day -> [Segment] in
            switch shownSplit {
            case .models:
                day.lines.map { Segment(date: day.date, kind: $0.model, value: days.value(of: $0)) }
            case .kind:
                switch shownCount {
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
    }

    private var chart: some View {
        Chart(segments) { segment in
            BarMark(
                x: .value("Day", segment.date, unit: .day),
                y: .value(shownCount.rawValue, segment.value)
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
                    .font(theme.font(size: 7))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(theme.progressTrack)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(shownCount == .cost ? Self.money(Decimal(amount), whole: true) : Self.count(Int(amount)))
                            .font(theme.font(size: 7))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shownCount)
        .animation(.easeInOut(duration: 0.25), value: shownSplit)
    }

    // MARK: - Formatting

    /// The hovered day's models, by name, largest part first — wrapped, since
    /// a day may name more models than one row holds. The unnamed line among
    /// them, so they read as adding up to the day.
    private func modelsDetail(for day: DailyUsageStat) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 4) {
            ForEach(days.lines(of: day), id: \.model) { line in
                HStack(spacing: 4) {
                    Circle().fill(color(of: line.model)).frame(width: 5, height: 5)
                    Text(ModelUsageLine.displayName(line.model))
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Text(unit(days.value(of: line)))
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .padding(.top, 2)
    }

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
