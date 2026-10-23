import Foundation
import Domain

/// The recap written out: one self-contained HTML page the person saves and
/// opens anywhere. It holds what the card holds — the total, the change, the
/// split, the highlights — in the card's own words (`UsageFormat`,
/// `RecapRange`'s), plus the shape behind them: the day by day is `Recap.days`
/// and the model by model `Recap.models`, never a second count. The dates are
/// the recap's own (`Recap.range`), the peak its biggest day, the colours
/// `ModelColors`'. Its own stylesheet, no script, the system's light or dark
/// — the file travels alone. Written only when the person saves it
/// (`ReportSaver`); the app never reads it back.
struct RecapHTMLReport {
    /// The recap on screen, in the range the person chose.
    let recap: Recap
    /// The range the recap was read for: its words, and its period the
    /// chart's rhythm.
    let range: RecapRange
    /// A provider's name, from its id — the card's.
    let name: (String) -> String

    /// The moment the report was written, said in its stamp.
    private let written: Date

    init(recap: Recap, range: RecapRange, name: @escaping (String) -> String, written: Date = Date()) {
        self.recap = recap
        self.range = range
        self.name = name
        self.written = written
    }

    /// The name the save panel offers.
    var fileName: String { "Usage recap — \(range.title)" }

    /// The whole page.
    var html: String {
        [
            head,
            "<main>",
            header,
            recap.isEmpty ? empty : body,
            footer,
            "</main>",
            "</body>",
            "</html>",
        ].joined(separator: "\n")
    }

    // MARK: - The page's pieces

    private var head: String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Self.escape(fileName)) · ClaudeBar</title>
        <style>\(Self.stylesheet)</style>
        </head>
        <body>
        """
    }

    private var header: String {
        let stamp = Self.escape(written.formatted(.dateTime.month().day().hour().minute()))
        return [
            "<header>",
            #"  <div class="eyebrow">ClaudeBar · Usage recap</div>"#,
            #"  <h1>\#(Self.escape(range.title))</h1>"#,
            #"  <div class="when">\#(when)</div>"#,
            #"  <div class="stamp">\#(stamp) · written on this Mac</div>"#,
            "</header>",
        ].joined(separator: "\n")
    }

    /// The days the recap sums, first to last.
    private var when: String {
        let style = Date.FormatStyle().weekday(.wide).month(.wide).day()
        return Self.escape("\(recap.range.first.formatted(style)) – \(recap.range.last.formatted(style.year()))")
    }

    /// A range that held nothing is said, never shown as zeros.
    private var empty: String {
        """
          <section>
            <p class="nothing">\(Self.escape(range.emptyNote))</p>
          </section>
        """
    }

    private var body: String {
        [
            lead,
            section("Where it went", providersMarkup),
            section("Day by day", daysMarkup),
            section("Models", modelsMarkup),
            section("Highlights", highlightsMarkup),
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var lead: String {
        var subline: [String] = []
        if let tokens = recap.tokens { subline.append("\(UsageFormat.count(Int(tokens))) tokens") }
        if recap.workingTime > 0 { subline.append(UsageFormat.duration(recap.workingTime)) }
        if recap.sessions > 0 { subline.append("\(recap.sessions) sessions") }

        var lead = #"  <section><h2>The \#(range.period.word)</h2>"#
        lead += #"<div class="lead"><span class="total">\#(UsageFormat.value(recap.total, in: recap.unit))</span>"#
        lead += #"<span class="cap">\#(recap.unit.caption)</span>"#
        if let change = recap.change {
            let direction = change > 0 ? "up" : "down"
            let arrow = change > 0 ? "▲" : "▼"
            lead += #"<span class="change"><b class="\#(direction)">\#(arrow) \#(UsageFormat.change(change))</b><span>\#(Self.escape(range.comparedWith))</span></span>"#
        }
        lead += "</div>"
        if !subline.isEmpty {
            lead += #"<div class="subline">\#(subline.joined(separator: " <i>·</i> "))</div>"#
        }
        lead += "</section>"
        return lead
    }

    /// The providers the range spans, a stacked bar over their rows.
    private var providersMarkup: String {
        let stack = "<div class=\"stack\">"
            + recap.providers
            .enumerated()
            .map { index, part in #"<div class="\#(Self.hue(index))" style="width:\#(Int(part.share * 100))%"></div>"# }
            .joined() + "</div>"
        let rows = recap.providers.enumerated().map { index, part in
            row(hue: Self.hue(index), label: name(part.provider), value: UsageFormat.value(part.value, in: recap.unit),
                share: UsageFormat.share(part.share))
        }
        return stack + "<div class=\"rows\">" + rows.joined(separator: "\n") + "</div>"
    }

    /// Every day of the range, each a share of the busiest; the peak is the
    /// recap's biggest day. A month's thirty days are drawn quieter than a
    /// week's seven: a value only on the peak, a day-number label.
    private var daysMarkup: String {
        let bars = recap.days.map { day in
            let isPeak = day.date == recap.biggestDay?.date
            let value: String
            let label: String
            switch range.period {
            case .week:
                value = UsageFormat.value(day.value, in: recap.unit)
                label = day.date.formatted(.dateTime.weekday(.abbreviated))
            case .month:
                value = isPeak ? UsageFormat.value(day.value, in: recap.unit) : ""
                label = day.date.formatted(.dateTime.day())
            }
            let shown = value.isEmpty ? "" : #"<span class="v">\#(value)</span>"#
            let peak = isPeak ? " peak" : ""
            let height = max(Int(day.share * 100), day.value > 0 ? 2 : 0)
            return #"<div class="day\#(peak)">\#(shown)<div class="bar" style="height:\#(height)%"></div><span class="l">\#(Self.escape(label))</span></div>"#
        }
        return "<div class=\"chart\">" + bars.joined(separator: "\n") + "</div>"
    }

    /// Every model the mix reads, largest first, each in the colour the app
    /// gives it (`ModelColors`).
    private var modelsMarkup: String {
        let names = recap.models.map(\.line.model)
        return "<div class=\"rows\">" + recap.models.map { part in
            row(hue: ModelColors.index(of: part.line.model, among: names).map(Self.hue) ?? "cu",
                label: part.line.displayName, value: UsageFormat.value(part.value, in: recap.unit),
                share: UsageFormat.share(part.share))
        }.joined(separator: "\n") + "</div>"
    }

    private var highlightsMarkup: String {
        var tiles: [String] = []
        if let model = recap.topModel {
            tiles.append(tile("Top model", Self.escape(model.line.displayName)))
        }
        if let day = recap.biggestDay {
            tiles.append(tile("Biggest day", Self.escape(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))))
        }
        if recap.cacheSavings > 0 {
            tiles.append(tile("Cache saved", UsageFormat.money(recap.cacheSavings)))
        }
        return "<div class=\"tiles\">" + tiles.joined(separator: "\n") + "</div>"
    }

    private var footer: String {
        #"  <footer>Written by <strong>ClaudeBar</strong> from your local usage logs — a read of the \#(range.period.word), never stored.</footer>"#
    }

    // MARK: - Helpers

    /// One titled section, or nothing when it holds no markup.
    private func section(_ title: String, _ markup: @autoclosure () -> String) -> String {
        let content = markup()
        guard !content.isEmpty else { return "" }
        return #"  <section><h2>\#(title)</h2>\#(content)</section>"#
    }

    /// The stylesheet's class for the palette's hue at `index`, cycled.
    private static func hue(_ index: Int) -> String { "c\(index % ModelColors.palette.count + 1)" }

    private func row(hue: String, label: String, value: String, share: String) -> String {
        #"<div class="row"><span class="dot \#(hue)"></span><span class="name">\#(Self.escape(label))</span><span class="val">\#(value)</span><span class="share">\#(share)</span></div>"#
    }

    private func tile(_ title: String, _ value: String) -> String {
        #"<div class="tile"><div class="k">\#(title)</div><div class="v">\#(value)</div></div>"#
    }

    /// The report's own words for text from the logs: everything read is
    /// escaped before it is written.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The stylesheet: light by the page's own palette, dark when the system
    /// asks — the file travels alone, so no theme follows it.
    private static let stylesheet: String = {
        // The app's palette, written out in each appearance; `cu` the unnamed line.
        func hues(dark: Bool) -> String {
            (ModelColors.palette.enumerated().map { index, color in
                ".c\(index + 1){background:\(ModelColors.hex(color, dark: dark))}"
            } + [".cu{background:\(ModelColors.hex(ModelColors.unnamed, dark: dark))}"]).joined()
        }
        let colors = "\(hues(dark: false))\n@media (prefers-color-scheme:dark){\(hues(dark: true))}"
        return """
        :root{--bg:#F6F4FA;--wash:#EDE8F6;--card:#FFFFFF;--hair:#E6E1F0;--ink:#1D1B2E;--muted:#6B6580;--faint:#9A93AE;--track:#ECE6F5;--up:#C46A00;--down:#1F8A4D;--glow:rgba(140,110,220,.10)}
        @media (prefers-color-scheme:dark){:root{--bg:#0C0D12;--wash:#14151D;--card:rgba(255,255,255,.045);--hair:rgba(255,255,255,.09);--ink:#F2F2F5;--muted:#A8A8B3;--faint:#6E6E7A;--track:rgba(255,255,255,.07);--up:#FF9F0A;--down:#30D158;--glow:rgba(120,90,220,.16)}}
        *{box-sizing:border-box}
        body{margin:0;background:radial-gradient(900px 340px at 50% -120px,var(--glow),transparent 70%),var(--bg);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
        main{max-width:720px;margin:0 auto;padding:48px 24px 24px;display:flex;flex-direction:column;gap:14px}
        .eyebrow{font-size:11px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--faint);display:flex;align-items:center;gap:8px}
        .eyebrow::before{content:"";width:18px;height:1px;background:var(--faint)}
        h1{margin:4px 0 2px;font-size:34px;font-weight:800;letter-spacing:-.02em}
        .when{color:var(--muted);font-size:14px}
        .stamp{color:var(--faint);font-size:12px;margin-top:2px}
        section{background:var(--card);border:1px solid var(--hair);border-radius:16px;padding:18px 20px}
        section>h2{margin:0 0 12px;font-size:11px;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}
        .nothing{margin:4px 0;color:var(--faint)}
        .lead{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
        .lead .total{font:700 44px/1 "SF Pro Rounded","SF Pro Display",-apple-system,system-ui;letter-spacing:-.02em}
        .lead .cap{color:var(--faint);font-size:13px}
        .change{margin-left:auto;text-align:right}
        .change b{font-size:17px;font-weight:700;color:var(--up)}
        .change b.up{color:var(--up)}
        .change b.down{color:var(--down)}
        .change span{display:block;font-size:11px;color:var(--faint)}
        .subline{margin-top:10px;color:var(--muted);font-size:13px}
        .subline i{font-style:normal;color:var(--faint);padding:0 6px}
        .rows{display:flex;flex-direction:column;gap:9px}
        .row{display:flex;align-items:center;gap:10px;font-size:13.5px}
        .dot{width:8px;height:8px;border-radius:50%;flex:none}
        .row .name{color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        .row .val{margin-left:auto;color:var(--faint);font-variant-numeric:tabular-nums}
        .row .share{font-weight:700;min-width:44px;text-align:right;font-variant-numeric:tabular-nums}
        .stack{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--track);margin-bottom:12px}
        .stack div{height:100%}
        .chart{display:flex;align-items:flex-end;gap:8px;height:120px}
        .chart .day{flex:1;display:flex;flex-direction:column;align-items:center;gap:6px;height:100%;justify-content:flex-end}
        .chart .bar{width:100%;max-width:34px;border-radius:5px 5px 2px 2px;background:linear-gradient(180deg,#BF5AF2,#7B5BE6)}
        .chart .v{font-size:10.5px;color:var(--faint);font-variant-numeric:tabular-nums}
        .chart .l{font-size:11px;color:var(--faint)}
        .chart .peak .l{color:var(--ink);font-weight:700}
        .tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
        .tile{border:1px solid var(--hair);border-radius:12px;padding:12px 14px;background:var(--wash)}
        .tile .k{font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--faint)}
        .tile .v{margin-top:4px;font-size:15px;font-weight:700}
        footer{color:var(--faint);font-size:12px;text-align:center;padding:20px 0 40px}
        footer strong{color:var(--muted);font-weight:600}
        \(colors)
        @media (max-width:560px){.tiles{grid-template-columns:1fr}.change{margin-left:0;text-align:left}}
        """
    }()
}
