import Foundation
import Quotas
import DataSources
import Monitoring

/// The recap written out: one self-contained HTML page the person saves and
/// opens anywhere. It holds what the card holds — the total, the change, the
/// split, the highlights — in the card's own words, plus the shape behind
/// them: the day by day, the models, the projects and each day's own figures,
/// in every unit the recap offers. What it shows is `RecapReportPage`'s, read
/// from the recap's owners, never a second count; the dates are the recap's
/// own (`Recap.range`), the colours `ModelColors`'. The page is written twice
/// from that one read: as plain markup in the recap's unit, and as data its
/// own script shows in the unit, the stacking, the day and the order the
/// reader picks (`RecapReportScript`). Its own stylesheet and script, nothing
/// fetched, the system's light or dark — the file travels alone. Written only
/// when the person saves it (`ReportSaver`); the app never reads it back.
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

    /// What the page shows, in every unit the recap offers.
    private var page: RecapReportPage { RecapReportPage(recap: recap, range: range, name: name) }

    /// The whole page.
    var html: String {
        let page = page
        return [
            head,
            "<main>",
            header,
            recap.isEmpty ? empty : page.opening.map { body(page, $0) } ?? empty,
            footer,
            "</main>",
            recap.isEmpty ? "" : script(page),
            "</body>",
            "</html>",
        ].filter { !$0.isEmpty }.joined(separator: "\n")
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

    /// The page in the recap's own unit, as plain markup — what a reader
    /// without the script sees — and the place the script draws into.
    private func body(_ page: RecapReportPage, _ view: RecapReportPage.View) -> String {
        let sections = [
            lead(view),
            section("Day by day", daysMarkup(page, view)),
            view.hours.map { section("Hour by hour", hoursMarkup(page, $0)) } ?? "",
            view.splits.map { section($0.title, rowsMarkup($0)) }.joined(separator: "\n"),
            section("Tokens by kind", tilesMarkup(page.tokens)),
            section("Highlights", tilesMarkup(view.tiles)),
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        return """
        <div id="static" class="sections">
        \(sections)
        </div>
        <div id="live" class="sections" hidden></div>
        <div id="tip" class="tip" role="status" hidden></div>
        """
    }

    private func lead(_ view: RecapReportPage.View) -> String {
        var lead = #"  <section><h2>The \#(range.period.word)</h2>"#
        lead += #"<div class="lead"><span class="total">\#(view.total)</span>"#
        lead += #"<span class="cap">\#(view.caption)</span>"#
        if let change = view.change {
            let direction = change.up ? "up" : "down"
            let arrow = change.up ? "▲" : "▼"
            lead += #"<span class="change"><b class="\#(direction)">\#(arrow) \#(change.text)</b><span>\#(Self.escape(range.comparedWith))</span></span>"#
        }
        lead += "</div>"
        if !view.subline.isEmpty {
            lead += #"<div class="subline">\#(view.subline.joined(separator: " <i>·</i> "))</div>"#
        }
        lead += "</section>"
        return lead
    }

    /// Every day of the range, each a share of the busiest; the peak is the
    /// recap's biggest day. A month's thirty days are drawn quieter than a
    /// week's seven: a value only on the peak.
    private func daysMarkup(_ page: RecapReportPage, _ view: RecapReportPage.View) -> String {
        let bars = zip(view.days, page.days).map { day, own in
            let value = range.period == .week || day.peak ? day.value : ""
            let shown = value.isEmpty ? "" : #"<span class="v">\#(value)</span>"#
            let peak = day.peak ? " peak" : ""
            let height = max(Int(day.share * 100), day.share > 0 ? 2 : 0)
            return #"<div class="day\#(peak)"><div class="plot">\#(shown)<div class="bar" style="height:\#(height)%"></div></div><span class="l">\#(Self.escape(own.label))</span></div>"#
        }
        let quiet = range.period == .month ? " month" : ""
        return "<div class=\"chart\(quiet)\">" + bars.joined(separator: "\n") + "</div>"
    }

    /// Every day of the range hour by hour: a row a day, twenty-four cells,
    /// each shaded by its band against the range's busiest hour; over them
    /// the hours of the day added up. A day whose hours were never kept says
    /// so, never twenty-four empty cells.
    private func hoursMarkup(_ page: RecapReportPage, _ hours: RecapReportPage.Hours) -> String {
        func cells(_ cells: [RecapReportPage.HourCell]) -> String {
            (0..<24).map { hour in
                cells.first { $0.h == hour }.map { #"<i class="h\#($0.level)" title="\#(RecapReportPage.span(hour)) · \#($0.value)"></i>"# } ?? "<i></i>"
            }.joined()
        }
        let axis = #"<div class="hr axis"><span class="hl"></span>"#
            + stride(from: 0, to: 24, by: 3).map { #"<span class="ha">\#(String(format: "%02d", $0))</span>"# }.joined()
            + "</div>"
        let all = #"<div class="hr all"><span class="hl">All</span>\#(cells(hours.ofDay))</div>"#
        let rows = zip(hours.rows, page.days).map { row, own in
            let label = #"<span class="hl">\#(Self.escape(own.label))</span>"#
            return row.known
                ? #"<div class="hr">\#(label)\#(cells(row.cells))</div>"#
                : #"<div class="hr"><span class="hl">\#(Self.escape(own.label))</span><span class="nk">no hours kept for this day</span></div>"#
        }
        let quiet = range.period == .month ? " month" : ""
        return #"<div class="peak">Busiest hour: \#(Self.escape(hours.peak))</div>"#
            + "<div class=\"heat\(quiet)\">" + ([axis, all] + rows).joined(separator: "\n") + "</div>"
            + Self.heatLegend
    }

    /// The bands, lightest first — each cell is shaded against the range's
    /// busiest hour.
    private static let heatLegend = #"<div class="legend"><span>Less</span>"#
        + UsageHeatmap.levels.map { $0 == 0 ? "<i></i>" : #"<i class="h\#($0)"></i>"# }.joined()
        + "<span>More</span></div>"

    /// A split of the range — its providers, its models, its projects — a
    /// stacked bar over a row each, largest first.
    private func rowsMarkup(_ split: RecapReportPage.Split) -> String {
        let stack = "<div class=\"stack\">"
            + split.rows.map { #"<div class="\#($0.hue)" style="width:\#(Int($0.share * 100))%"></div>"# }.joined()
            + "</div>"
        let rows = split.rows.map { row in
            let change = row.change.map { #"<span class="chg \#($0.up ? "up" : "down")">\#($0.text)</span>"# } ?? ""
            return #"<div class="row"><span class="dot \#(row.hue)"></span><span class="name">\#(Self.escape(row.name))</span><span class="val">\#(row.value)</span><span class="share">\#(row.shareText)</span>\#(change)</div>"#
        }
        return stack + "<div class=\"rows\">" + rows.joined(separator: "\n") + "</div>"
    }

    private func tilesMarkup(_ facts: [RecapReportPage.Fact]) -> String {
        guard !facts.isEmpty else { return "" }
        return "<div class=\"tiles\">" + facts.map {
            #"<div class="tile"><div class="k">\#($0.k)</div><div class="v">\#(Self.escape($0.v))</div></div>"#
        }.joined(separator: "\n") + "</div>"
    }

    /// The page's data and the script that shows it. The data is JSON with
    /// every `<`, `>` and `&` written as an escape, so no name read from a
    /// log can close the element it sits in.
    private func script(_ page: RecapReportPage) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = (try? encoder.encode(page)).flatMap({ String(data: $0, encoding: .utf8) }) else { return "" }
        let safe = json.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        return """
        <script type="application/json" id="recap-data">\(safe)</script>
        <script>
        \(RecapReportScript.source)
        </script>
        """
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
        :root{--bg:#F6F4FA;--wash:#EDE8F6;--card:#FFFFFF;--hair:#E6E1F0;--ink:#1D1B2E;--muted:#6B6580;--faint:#9A93AE;--track:#ECE6F5;--up:#C46A00;--down:#1F8A4D;--glow:rgba(140,110,220,.10);--on:#FFFFFF;--tip:#FFFFFF;--accent:#6B4FD8;--heat:123 91 230}
        @media (prefers-color-scheme:dark){:root{--bg:#0C0D12;--wash:#14151D;--card:rgba(255,255,255,.045);--hair:rgba(255,255,255,.09);--ink:#F2F2F5;--muted:#A8A8B3;--faint:#6E6E7A;--track:rgba(255,255,255,.07);--up:#FF9F0A;--down:#30D158;--glow:rgba(120,90,220,.16);--on:rgba(255,255,255,.14);--tip:#1E1F29;--accent:#A892FF;--heat:168 132 255}}
        *{box-sizing:border-box}
        [hidden]{display:none!important}
        body{margin:0;background:radial-gradient(900px 340px at 50% -120px,var(--glow),transparent 70%),var(--bg);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
        main{max-width:720px;margin:0 auto;padding:48px 24px 24px;display:flex;flex-direction:column;gap:14px}
        .eyebrow{font-size:11px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--faint);display:flex;align-items:center;gap:8px}
        .eyebrow::before{content:"";width:18px;height:1px;background:var(--faint)}
        h1{margin:4px 0 2px;font-size:34px;font-weight:800;letter-spacing:-.02em}
        .when{color:var(--muted);font-size:14px}
        .stamp{color:var(--faint);font-size:12px;margin-top:2px}
        section{background:var(--card);border:1px solid var(--hair);border-radius:16px;padding:18px 20px}
        .sections{display:flex;flex-direction:column;gap:14px}
        section>h2{margin:0 0 12px;font-size:11px;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);display:flex;align-items:center;gap:10px;flex-wrap:wrap;min-height:24px}
        section>h2>.seg,section>h2>.link{margin-left:auto}
        button{font:inherit;color:inherit;background:none;border:0;padding:0;margin:0;cursor:pointer}
        button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
        .seg{display:inline-flex;border:1px solid var(--hair);border-radius:8px;overflow:hidden;background:var(--wash)}
        .seg button{padding:5px 10px;font-size:11.5px;font-weight:600;letter-spacing:0;text-transform:none;color:var(--muted)}
        .seg button.on{background:var(--on);color:var(--ink)}
        .link{font-size:12px;font-weight:500;letter-spacing:0;text-transform:none;color:var(--accent)}
        .more{margin-top:10px}
        .hint{margin-top:10px;font-size:12px;color:var(--faint)}
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
        .lead .total.small{font-size:28px}
        .sort{display:flex;align-items:center;gap:12px;margin-bottom:8px;font-size:11.5px;color:var(--faint)}
        .sort button{color:var(--muted)}
        .sort button.on{color:var(--ink);font-weight:700}
        .rows{display:flex;flex-direction:column;gap:9px}
        .row .chg{min-width:52px;text-align:right;font-size:12px;color:var(--faint);font-variant-numeric:tabular-nums}
        .chg.up{color:var(--up)}
        .chg.down{color:var(--down)}
        .row{display:flex;align-items:center;gap:10px;font-size:13.5px}
        .dot{width:8px;height:8px;border-radius:50%;flex:none}
        .row .name{color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        .row .val{margin-left:auto;color:var(--faint);font-variant-numeric:tabular-nums}
        .row .share{font-weight:700;min-width:44px;text-align:right;font-variant-numeric:tabular-nums}
        .stack{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--track);margin-bottom:12px}
        .stack div{height:100%}
        .chart{display:flex;align-items:flex-end;gap:8px;height:150px}
        .chart .plot{flex:1;min-height:0;width:100%;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;gap:4px;padding-top:18px}
        .chart.month{gap:3px}
        .chart.dim .day:not(.sel) .bar{opacity:.4}
        .chart .day.sel .l{color:var(--accent);font-weight:700}
        .chart .bar.stacked{background:none;display:flex;flex-direction:column-reverse;overflow:hidden}
        .chart .bar.stacked i{display:block;flex:none;width:100%}
        .chart button.day:hover .bar{filter:brightness(1.12)}
        .chart .day{flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;gap:6px;height:100%}
        .chart .bar{flex:none;width:100%;max-width:34px;border-radius:5px 5px 2px 2px;background:linear-gradient(180deg,#BF5AF2,#7B5BE6)}
        .chart .v{flex:none;font-size:10.5px;color:var(--faint);font-variant-numeric:tabular-nums;white-space:nowrap}
        .chart .l{font-size:11px;color:var(--faint)}
        .chart .peak .l{color:var(--ink);font-weight:700}
        .peak{margin:-4px 0 12px;font-size:12.5px;color:var(--muted)}
        .heat{display:flex;flex-direction:column;gap:3px}
        .heat.month{gap:2px}
        .hr{display:grid;grid-template-columns:38px repeat(24,1fr);gap:3px;align-items:center}
        .heat.month .hr{gap:2px}
        .hr i{display:block;height:20px;border-radius:3px;background:var(--track)}
        .heat.month .hr i{height:13px;border-radius:2px}
        .hr .h1{background:rgb(var(--heat)/.28)}
        .hr .h2{background:rgb(var(--heat)/.5)}
        .hr .h3{background:rgb(var(--heat)/.75)}
        .hr .h4{background:rgb(var(--heat))}
        .hr .hl{padding-right:8px;text-align:right;font-size:10.5px;color:var(--faint);white-space:nowrap}
        .hr .ha{grid-column:span 3;font-size:10.5px;color:var(--faint)}
        .hr.all{margin-bottom:6px}
        .hr.all .hl{font-weight:700;color:var(--muted)}
        .hr .nk{grid-column:span 24;font-size:10.5px;color:var(--faint);border:1px dashed var(--hair);border-radius:3px;padding:0 8px;line-height:18px}
        .heat.month .hr .nk{line-height:11px;font-size:9.5px}
        .hr.sel .hl{color:var(--accent);font-weight:700}
        .heat.live .hr:not(.axis):not(.all){cursor:pointer}
        .heat.live .hr i:hover{outline:2px solid var(--ink);outline-offset:1px}
        .legend{display:flex;align-items:center;justify-content:flex-end;gap:3px;margin-top:10px;font-size:10.5px;color:var(--faint)}
        .legend span{padding:0 4px}
        .legend i{display:block;width:13px;height:13px;border-radius:2px;background:var(--track)}
        .legend .h1{background:rgb(var(--heat)/.28)}
        .legend .h2{background:rgb(var(--heat)/.5)}
        .legend .h3{background:rgb(var(--heat)/.75)}
        .legend .h4{background:rgb(var(--heat))}
        .tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
        .tile{border:1px solid var(--hair);border-radius:12px;padding:12px 14px;background:var(--wash)}
        .tile .k{font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--faint)}
        .tile .v{margin-top:4px;font-size:15px;font-weight:700}
        .facts{margin-top:14px}
        .tip{position:fixed;z-index:9;pointer-events:none;min-width:170px;max-width:280px;padding:10px 12px;border:1px solid var(--hair);border-radius:10px;background:var(--tip);box-shadow:0 8px 24px rgba(0,0,0,.18);font-size:12px}
        .tip b{display:block;font-size:12.5px}
        .tip .big{margin:1px 0 5px;font-size:17px;font-weight:700}
        .tip .f{display:flex;justify-content:space-between;gap:16px;color:var(--muted)}
        .tip .f>span:last-child{color:var(--ink);font-variant-numeric:tabular-nums}
        .tip .dot{display:inline-block}
        .tip hr{border:0;border-top:1px solid var(--hair);margin:6px 0}
        footer{color:var(--faint);font-size:12px;text-align:center;padding:20px 0 40px}
        footer strong{color:var(--muted);font-weight:600}
        \(colors)
        @media (max-width:560px){.tiles{grid-template-columns:1fr}.change{margin-left:0;text-align:left}}
        """
    }()
}
