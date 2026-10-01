// Replays a corpus of real `claude /usage` PTY captures through the shipping
// readiness rule and checks that the two classes of capture stay apart.
//
// A `/usage` capture is either a **settled** screen — the Usage tab, quota bars
// and all — or a **boot** screen: the CLI still submitting `/usage` with its
// SessionStart hooks running, which is what issue #317 was about. Readiness has
// to accept every settled capture and none of the boot ones, because a boot
// capture ends the wait and is then parsed as if it were a Usage screen.
//
// The rule under test is the real one: this file is compiled together with
// `Sources/Infrastructure/Shared/CLICompletionRule.swift`, so a change to the
// matcher is measured here rather than re-described in a commit message.
//
//   scripts/replay-claude-usage-captures.sh                    # committed corpus
//   scripts/replay-claude-usage-captures.sh --corpus <dir>     # some other captures
//   scripts/replay-claude-usage-captures.sh --extract <ClaudeBar.log> --out <dir> [--all]
//
// `--extract` splits a log into redacted capture files (see `redact`); pass
// `--all` to keep every capture instead of the balanced subset the repo carries.
//
// Ground truth is independent of the rule under test: a capture counts as
// settled when the CLI printed a quota bar (`38% used` / `12% left`), which is
// data only a finished Usage tab has.

import Foundation

// MARK: - Ground truth

enum GroundTruth {
    /// A capture is settled when the CLI painted a quota bar. The bar is
    /// `38% used` / `12% left`, and the CLI writes it in runs split by cursor
    /// moves, so the digits, the percent sign and the word are compared after
    /// collapsing each run of non-alphanumerics — the same normalisation the
    /// rule does, but answering a completely different question.
    static func isSettled(_ capture: String) -> Bool {
        let bar = try? NSRegularExpression(pattern: #"\d+\s+(?:used|left)\b"#)
        let collapsed = collapse(capture)
        return bar?.firstMatch(in: collapsed, range: NSRange(collapsed.startIndex..., in: collapsed)) != nil
    }

    private static func collapse(_ text: String) -> String {
        guard let escapes = try? NSRegularExpression(
            pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B\[[0-9;?]*[A-Za-z]|\x1B[()][AB012]|\x1B[78]"#
        ) else { return text }
        let stripped = escapes.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        )
        var out = ""
        out.reserveCapacity(stripped.count)
        for character in stripped.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
            } else if out.last != " " {
                out.append(" ")
            }
        }
        return out
    }
}

// MARK: - Entry point

@main
enum Replay {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        if let logPath = value(after: "--extract") {
            let directory = value(after: "--out") ?? defaultCorpusPath
            try extract(from: logPath, into: URL(fileURLWithPath: directory), keepAll: arguments.contains("--all"))
            return
        }

        let corpus = URL(fileURLWithPath: value(after: "--corpus") ?? defaultCorpusPath)
        let rule = CLICompletionRule.claudeUsage
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: corpus.path) else {
            FileHandle.standardError.write(Data("no corpus at \(corpus.path)\n".utf8))
            exit(2)
        }

        var settled = 0, settledReady = 0, boot = 0, bootReady = 0
        var markerHits: [String: Int] = [:]
        var failures: [String] = []

        for name in names.sorted() where name.hasSuffix(".txt") {
            let capture = try String(contentsOf: corpus.appendingPathComponent(name), encoding: .utf8)
            let ready = rule.isReady(capture)
            for marker in rule.matchedMarkers(in: capture) { markerHits[marker, default: 0] += 1 }

            if GroundTruth.isSettled(capture) {
                settled += 1
                if ready {
                    settledReady += 1
                } else {
                    failures.append("\(name): settled screen not recognised as ready")
                }
            } else {
                boot += 1
                if ready {
                    bootReady += 1
                    failures.append("\(name): boot screen wrongly recognised as ready")
                }
            }
        }

        print("corpus: \(corpus.path)")
        print("  settled (painted a quota bar): \(settled)")
        print("    ready                      : \(settledReady)")
        print("  boot    (no quota bar)      : \(boot)")
        print("    wrongly ready              : \(bootReady)")
        print("  markers that fired:")
        for (marker, count) in markerHits.sorted(by: { $0.value > $1.value }) {
            print("    \(count)\t\(marker)")
        }

        if failures.isEmpty {
            print("OK: every settled capture is ready, no boot capture is.")
            return
        }
        print("FAIL (\(failures.count)):")
        for failure in failures.prefix(20) { print("  \(failure)") }
        exit(1)
    }

    /// Resolved next to this file so the script runs from anywhere.
    static var defaultCorpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("claude-usage-captures")
            .path
    }

    // MARK: - Corpus extraction

    /// Splits a `ClaudeBar.log` into one file per `/usage` capture.
    ///
    /// The log is the only place these captures exist, and they are the
    /// evidence every claim about the rule rests on, so the split ships as a
    /// script rather than living in somebody's shell history.
    static func extract(from logPath: String, into directory: URL, keepAll: Bool) throws {
        let log = try String(contentsOfFile: logPath, encoding: .utf8)
        let marker = "[INFO] [probes] Claude /usage output:"
        let logLine = try NSRegularExpression(pattern: #"^\[\d{4}-\d\d-\d\dT"#)

        var captures: [String] = []
        var current: [String]?
        for line in log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasSuffix(marker) {
                if let current { captures.append(current.joined(separator: "\n")) }
                current = []
                continue
            }
            guard var buffer = current else { continue }
            if logLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                captures.append(buffer.joined(separator: "\n"))
                current = nil
                continue
            }
            buffer.append(line)
            current = buffer
        }
        if let current { captures.append(current.joined(separator: "\n")) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The committed corpus is a balanced subset: both classes matter, and a
        // subset of only one would let a rule that never fires look fine.
        var boot: [String] = []
        var settled: [String] = []
        for capture in captures {
            if GroundTruth.isSettled(capture) { settled.append(capture) } else { boot.append(capture) }
        }
        if !keepAll {
            let each = min(25, min(boot.count, settled.count))
            boot = Array(boot.prefix(each))
            settled = Array(settled.prefix(each))
        }

        var written = 0
        for (label, group) in [("boot", boot), ("settled", settled)] {
            for (index, capture) in group.enumerated() {
                let name = String(format: "%@-%03d.txt", label, index)
                try redact(capture).write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
                written += 1
            }
        }
        print("extracted \(written) of \(captures.count) captures into \(directory.path)")
        print("  boot \(boot.count), settled \(settled.count)")
        print("  re-run with --corpus \(directory.path) to replay them")
    }

    /// Removes what would identify the machine or the account from a capture.
    ///
    /// The captures come from a user's log, and they carry that account's email,
    /// the organisation it belongs to, the user's first name, their timezone,
    /// session ids and filesystem paths. None of it is evidence for the rule —
    /// the rule reads quota bars and ready markers — so it is replaced rather
    /// than kept.
    ///
    /// Patterns are matched against a *masked* copy of the capture, in which
    /// every escape sequence is replaced by an equal number of separator
    /// characters, and the match ranges are then blanked in the original. That
    /// is what makes this work at all: the CLI writes every word run at its own
    /// column, so `Welcome back Eric!` reaches the log as
    /// `Welcome␛[27Gback␛[32GEric␛[39G!` and a pattern that expects the words
    /// side by side matches nothing. Matching the mask and rewriting the
    /// original keeps the cursor-split structure — which is the whole point of
    /// the corpus — while still removing the name.
    static func redact(_ capture: String) -> String {
        // No capture groups: a match found in the mask is replaced by its whole
        // template, so nothing has to be rendered against text the regex never
        // matched. A value the CLI wrote in one run is redacted exactly; a value
        // split by a cursor move is redacted up to the gap, which is why the
        // character classes below tolerate a space — the mask's filler.
        let patterns: [(pattern: String, template: String)] = [
            // Credentials, in the shapes the CLI, its hooks and its status line use.
            (#"(?i)\b(?:sk-ant-[A-Za-z0-9_ -]{4,}|sk-[A-Za-z0-9_ -]{12,}|gh[pousr]_[A-Za-z0-9 ]{16,}|xox[baprs]-[A-Za-z0-9 -]{10,})"#, "<credential>"),
            // Authorization headers, OAuth material and JWTs.
            (#"(?i)bearer\s+[A-Za-z0-9._~+/= -]{8,}"#, "<credential>"),
            (#"(?i)\b(?:oauth|access|refresh|api|id)_token\b[\s:=]{1,4}[A-Za-z0-9._~+/= -]{4,}"#, "<credential>"),
            (#"\beyJ[A-Za-z0-9_ -]{8,}"#, "<credential>"),
            // Account identity.
            (#"(?i)[A-Za-z0-9._%+-]+@[A-Za-z0-9. -]{2,}\.[A-Za-z]{2,}"#, "<email>"),
            (#"(?i)welcome\s+back\s+[^!\n]{1,40}!"#, "Welcome back <name>!"),
            // The reset text names the account's timezone, which narrows it to a
            // region. The rule never looks at it.
            (#"\((?:America|Europe|Asia|Africa|Australia|Pacific|Atlantic|Indian|Antarctica)[\s/]*[A-Za-z_\s]{2,30}\)"#, "(<timezone>)"),
            // Session and message ids.
            (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, "<session-id>"),
            // Home directories. The probe's own working directory is left alone:
            // it is the same on every machine and is part of the boot screen.
            (#"/(?:Users|home)/[^/\s]{1,40}"#, "~"),
            (#"/Volumes/[^/\s]{1,40}"#, "<volume>"),
            // Query strings: tokens ride in them.
            (#"\?[A-Za-z0-9._~:/?&=+%-]{1,200}"#, "?<query>"),
        ]

        var text = capture
        for entry in patterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern) else { continue }
            // Re-masked per pattern: a replacement changes the length, so the
            // offsets of the previous pass no longer line up.
            let mask = maskingEscapes(in: text)
            let matches = regex.matches(in: mask, range: NSRange(mask.startIndex..., in: mask))
            // Back to front, so each replacement leaves the earlier ranges valid.
            for match in matches.reversed() {
                guard let found = Range(match.range, in: text) else { continue }
                text.replaceSubrange(found, with: entry.template)
            }
        }
        return text
    }

    /// The capture with every escape sequence replaced by an equal number of
    /// spaces, so offsets in the result line up with the original while the
    /// words a pattern sees are the words on the screen. Spaces rather than
    /// nothing, because a gap inside a word (`America/Detroi` then a cursor
    /// move, then `t`) still has to read as one word to a pattern.
    private static func maskingEscapes(in text: String) -> String {
        guard let escapes = try? NSRegularExpression(
            pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B\[[0-9;?]*[A-Za-z]|\x1B[()][AB012]|\x1B[78]"#
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = escapes.matches(in: text, range: range)
        var masked = text
        for match in matches.reversed() {
            guard let found = Range(match.range, in: masked) else { continue }
            let width = masked.distance(from: found.lowerBound, to: found.upperBound)
            masked.replaceSubrange(found, with: String(repeating: " ", count: width))
        }
        return masked
    }
}
