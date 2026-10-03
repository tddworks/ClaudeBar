# I built a free menu bar app to track all your AI coding quotas in one place

Hey everyone!

Like many of you, I juggle multiple AI coding assistants throughout the day — Claude, Codex, Gemini, Kimi, Copilot... and I kept running into the same problem: **I'd hit a quota limit mid-task with no warning.**

So I built **ClaudeBar** — a free, open-source macOS menu bar app that monitors all your AI coding assistant quotas in real time.

## What it does

One glance at your menu bar tells you exactly how much quota you have left across all your providers:

- **Claude** (Pro/Max/API) — session, weekly, model-specific quotas + extra usage tracking
- **Codex** (ChatGPT Pro) — daily quota via RPC or API mode
- **Gemini CLI** — usage limits
- **GitHub Copilot** — completions and chat quotas
- **Kimi** — weekly + 5-hour rate limits (NEW: CLI mode, no Full Disk Access needed!)
- **Amp** (Sourcegraph) — usage and plan tier
- **Z.ai** / **Antigravity** / **AWS Bedrock** — and more

Color-coded status (green/yellow/red) so you know at a glance if you're running low. System notifications warn you before you hit a wall.

## What's new (v0.4.31)

Just shipped **Kimi dual-mode support**:

- **CLI mode** (recommended) — runs `kimi /usage` under the hood. Just install the CLI (`uv tool install kimi-cli`) and it works. No special permissions needed.
- **API mode** — reads browser cookies directly for authentication. Requires Full Disk Access.

You can switch between modes in Settings. This follows the same pattern as Claude and Codex which also offer multiple probe modes.

## Screenshots

[Dark Mode + Light Mode + CLI Theme + Christmas Theme screenshots]

*(The app has 4 themes including a terminal-aesthetic CLI theme and an auto-activating Christmas theme with snowfall!)*

## Technical details (for the curious)

- Native SwiftUI, macOS 15+
- Zero ViewModels — views consume rich `@Observable` domain models directly
- Chicago School TDD — 500+ tests
- Built with Tuist, auto-updates via Sparkle
- Each provider is a self-contained module with its own probe, parser, and tests

## Install

```bash
brew install --cask claudebar
```

Or download from [GitHub Releases](https://github.com/tddworks/ClaudeBar/releases/latest) (code-signed + notarized).

## Links

- GitHub: [github.com/tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar)
- Homebrew: `brew install --cask claudebar`

It's completely free and open source (MIT). Would love feedback — what providers should I add next? Any features you'd want?

---

**Suggested subreddits:**

- r/ClaudeAI — title: "I built a free menu bar app to track your Claude quota (+ Codex, Gemini, Kimi, Copilot)"
- r/macapps — title: "ClaudeBar — free menu bar app that monitors all your AI coding assistant quotas"
- r/ChatGPT — title: "Track your Codex/ChatGPT Pro quota from the menu bar (free, open source, also supports Claude, Gemini, Kimi)"
- r/programming — title: "Open source macOS app to monitor AI coding assistant quotas — 500+ TDD tests, zero ViewModels"
- r/swift — title: "ClaudeBar: macOS menu bar app built with SwiftUI + Chicago School TDD (no ViewModels, 500+ tests)"
