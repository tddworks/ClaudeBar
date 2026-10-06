# <img src="docs/app-icon.png" width="36" height="36" valign="middle" alt=""> ClaudeBar

**Every AI coding quota in your menu bar.**

[![Build](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml)
[![Tests](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/tddworks/ClaudeBar/graph/badge.svg)](https://codecov.io/gh/tddworks/ClaudeBar)
[![Latest Release](https://img.shields.io/github/v/release/tddworks/ClaudeBar)](https://github.com/tddworks/ClaudeBar/releases/latest)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015-blue.svg)](https://developer.apple.com)
[![Homebrew](https://img.shields.io/badge/Homebrew-Install-brightgreen.svg)](https://formulae.brew.sh/cask/claudebar)

A macOS menu bar app that shows how much of your AI coding quota is left — Claude, Codex, Gemini, Copilot, Cursor and 15 more — with reset countdowns and a notification before you run out.

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/Screenshot-dark.png" alt="Dark theme" width="360"/><br/><em>Dark</em></td>
    <td align="center"><img src="docs/screenshots/Screenshot-light.png" alt="Light theme" width="360"/><br/><em>Light</em></td>
  </tr>
</table>

## Quick Start

```bash
brew install --cask claudebar
```

Or download the signed and notarized DMG from [Releases](https://github.com/tddworks/ClaudeBar/releases/latest). Requires macOS 15+. Launch it, open **Settings → Providers** and turn on the tools you use; each provider's doc says what it needs. Building from source: [CONTRIBUTING.md](CONTRIBUTING.md).

## Providers

| Provider | Tracks | Setup |
|---|---|---|
| Claude | 5-hour session and weekly limits, model limits (Opus, Sonnet, Fable), Extra Usage | [docs](docs/providers/claude/README.md) |
| Codex | 5-hour and weekly rate limits, credits | [docs](docs/providers/codex/README.md) |
| Gemini | Per-model Code Assist quota (Pro, Flash, Flash Lite) | [docs](docs/providers/gemini/README.md) |
| Antigravity | Gemini and Claude pools, 5-hour and weekly | [docs](docs/providers/antigravity/README.md) |
| Z.ai | GLM Coding Plan 5-hour, weekly, monthly and MCP usage | [docs](docs/providers/zai/README.md) |
| Copilot | Monthly AI credits | [docs](docs/providers/copilot/README.md) |
| AWS Bedrock | Today's spend and tokens per model, optional daily budget | [docs](docs/providers/bedrock/README.md) |
| Amp Code | Free allowance and credit balance | [docs](docs/providers/ampcode/README.md) |
| Kimi | 5-hour and weekly limits | [docs](docs/providers/kimi/README.md) |
| Kiro | Monthly plan credits and bonus credits | [docs](docs/providers/kiro/README.md) |
| Cursor | Included monthly usage, on-demand and team credits | [docs](docs/providers/cursor/README.md) |
| MiniMax | Coding Plan requests per model | [docs](docs/providers/minimax/README.md) |
| DeepSeek | Account balance (paid and granted) | [docs](docs/providers/deepseek/README.md) |
| OpenRouter | Credit balance (credits minus usage) | [docs](docs/providers/openrouter/README.md) |
| Vercel Gateway | AI Gateway credit balance | [docs](docs/providers/vercel-gateway/README.md) |
| Alibaba | Coding Plan 5-hour, weekly and monthly quota | [docs](docs/providers/alibaba/README.md) |
| Mistral | Today's Mistral Vibe spend and tokens | [docs](docs/providers/mistral/README.md) |
| OpenCode Go | 5-hour, weekly and monthly windows | [docs](docs/providers/opencode-go/README.md) |
| Oh My Pi | Every rate-limit window `omp` reports, per upstream account, and daily usage from its session logs | [docs](docs/providers/omp/README.md) |
| Grok | xAI credit allowance per billing period, per product, plan and prepaid balance | [docs](docs/providers/grok/README.md) |
| Command Code | 5-hour and weekly windows, credit balance | [docs](docs/providers/commandcode/README.md) |
| Cline | Five-hour, weekly and monthly plan limits | [docs](docs/providers/cline/README.md) |
| Warp | Monthly AI credits and add-on credits | [docs](docs/providers/warp/README.md) |
| Devin | Daily and weekly organization quota, with your browser sign-in | [docs](docs/providers/devin/README.md) |
| Windsurf | Daily and weekly quota, or message and flow-action allowances | [docs](docs/providers/windsurf/README.md) |
| JetBrains AI | Monthly AI credits from your IDE | [docs](docs/providers/jetbrains/README.md) |
| OpenAI API | Organization spend over the last 30 days, per line item | [docs](docs/providers/openai/README.md) |
| Your own | Anything a script can print, via `~/.claudebar/extensions/` | [docs](docs/features/extensions/README.md) |

## What It Covers

| Area | What you can do |
|---|---|
| Menu bar | Up to three providers as a percentage and reset countdown, or a status icon → [docs](docs/features/menu-bar/README.md) |
| [Multiple Codex accounts](docs/features/multi-account/README.md) | Separate logins, identified by email, with independent quotas |
| Alerts & colors | Healthy, warning, critical and depleted levels, pace-aware colors, custom colors and High Contrast → [docs](docs/features/status-colors/README.md) |
| Notch | Quota and live Claude Code sessions in the MacBook notch → [docs](docs/features/notch/README.md) |
| Touch Bar | Quota gauges on a MacBook Pro Touch Bar → [docs](docs/features/touch-bar/README.md) |
| Notify! | Quota on your iPhone Lock Screen and Home Screen → [docs](docs/features/notify/README.md) |
| Session hooks | Claude Code Started / Finished notifications → [docs](docs/features/session-hooks/README.md) |
| Daily usage | Today's cost and tokens next to yesterday's → [docs](docs/features/daily-usage/README.md) |
| Leaderboard | Share daily token totals and see where you rank → [docs](docs/features/leaderboard/README.md) |
| Themes | Dark, Light, CLI, Christmas, Pop, or your terminal's `.itermcolors` → [docs](docs/features/themes/README.md) |
| Extensions | Add any quota source with a manifest and a script → [docs](docs/features/extensions/README.md) |
| URL schemes | `claudebar://` actions for Raycast, Alfred and scripts → [docs](docs/features/url-schemes/README.md) |

Every doc, one line each: [docs index](docs/README.md). Something not working: [troubleshooting](docs/troubleshooting.md).

## More

- [Contributing](CONTRIBUTING.md) — build, test, and where things go
- [Architecture](docs/architecture/ARCHITECTURE.md) — layers and data flow
- [Changelog](CHANGELOG.md)

## Sponsors

Apps that use and support ClaudeBar development:

<a href="https://appnexus.app">
  <img src="https://appnexus.app/favicon.ico" width="64" height="64" alt="AppNexus" style="border-radius:14px">
  <br>
  <b>AppNexus for App Store Connect</b>
</a>

## Contributors

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://tddworks.com/"><img src="https://avatars.githubusercontent.com/u/1201118?v=4?s=80" width="80px;" alt="itshan"/><br /><sub><b>itshan</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=hanrw" title="Code">💻</a> <a href="https://github.com/tddworks/claudebar/commits?author=hanrw" title="Documentation">📖</a> <a href="#maintenance-hanrw" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/avishj"><img src="https://avatars.githubusercontent.com/u/58023328?v=4?s=80" width="80px;" alt="Avish Jha"/><br /><sub><b>Avish Jha</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=avishj" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/ramarivera"><img src="https://avatars.githubusercontent.com/u/7547875?v=4?s=80" width="80px;" alt="Ramiro"/><br /><sub><b>Ramiro</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=ramarivera" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/LunarECL"><img src="https://avatars.githubusercontent.com/u/38317983?v=4?s=80" width="80px;" alt="LunarECL"/><br /><sub><b>LunarECL</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=LunarECL" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/zenibako"><img src="https://avatars.githubusercontent.com/u/18584424?v=4?s=80" width="80px;" alt="Chandler Anderson"/><br /><sub><b>Chandler Anderson</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=zenibako" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://frmr.me"><img src="https://avatars.githubusercontent.com/u/620189?v=4?s=80" width="80px;" alt="Matt Farmer"/><br /><sub><b>Matt Farmer</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=farmdawgnation" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://willner.ws"><img src="https://avatars.githubusercontent.com/u/307605?v=4?s=80" width="80px;" alt="Alex"/><br /><sub><b>Alex</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=AlexanderWillner" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/sailesh"><img src="https://avatars.githubusercontent.com/u/493129?v=4?s=80" width="80px;" alt="sailesh"/><br /><sub><b>sailesh</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=sailesh" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/billyjack2"><img src="https://avatars.githubusercontent.com/u/28798344?v=4?s=80" width="80px;" alt="Billy Smith"/><br /><sub><b>Billy Smith</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=billyjack2" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/nero-sensei"><img src="https://avatars.githubusercontent.com/u/77715088?v=4?s=80" width="80px;" alt="nero"/><br /><sub><b>nero</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=nero-sensei" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/BryanQQYue"><img src="https://avatars.githubusercontent.com/u/169884865?v=4?s=80" width="80px;" alt="BryanYue"/><br /><sub><b>BryanYue</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=BryanQQYue" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://blog.d0zingcat.dev/"><img src="https://avatars.githubusercontent.com/u/8235790?v=4?s=80" width="80px;" alt="Tony Tang"/><br /><sub><b>Tony Tang</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=d0zingcat" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://initialize.nl/"><img src="https://avatars.githubusercontent.com/u/7355878?v=4?s=80" width="80px;" alt="Frank Hommers"/><br /><sub><b>Frank Hommers</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=frankhommers" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://www.marcusquinn.com"><img src="https://avatars.githubusercontent.com/u/6428977?v=4?s=80" width="80px;" alt="Marcus Quinn"/><br /><sub><b>Marcus Quinn</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=marcusquinn" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/hagiwaratakayuki"><img src="https://avatars.githubusercontent.com/u/141513?v=4?s=80" width="80px;" alt="hagiwara takayuki"/><br /><sub><b>hagiwara takayuki</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=hagiwaratakayuki" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/jeffscottmtl"><img src="https://avatars.githubusercontent.com/u/33327731?v=4?s=80" width="80px;" alt="jeffscottmtl"/><br /><sub><b>jeffscottmtl</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=jeffscottmtl" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/tomstetson"><img src="https://avatars.githubusercontent.com/u/11658911?v=4?s=80" width="80px;" alt="Tom"/><br /><sub><b>Tom</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=tomstetson" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/jeffWelling"><img src="https://avatars.githubusercontent.com/u/105077?v=4?s=80" width="80px;" alt="Jeff Welling"/><br /><sub><b>Jeff Welling</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=jeffWelling" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/Zada5"><img src="https://avatars.githubusercontent.com/u/91982194?v=4?s=80" width="80px;" alt="Zada5"/><br /><sub><b>Zada5</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=Zada5" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/fredericoricco-debug"><img src="https://avatars.githubusercontent.com/u/75469834?v=4?s=80" width="80px;" alt="fredericoricco-debug"/><br /><sub><b>fredericoricco-debug</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=fredericoricco-debug" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://lystic.dev"><img src="https://avatars.githubusercontent.com/u/15372623?v=4?s=80" width="80px;" alt="Kegan Hollern"/><br /><sub><b>Kegan Hollern</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=KeganHollern" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/jsg333"><img src="https://avatars.githubusercontent.com/u/954990?v=4?s=80" width="80px;" alt="Jeff Green"/><br /><sub><b>Jeff Green</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=jsg333" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/benjaminbelaga"><img src="https://avatars.githubusercontent.com/u/33546317?v=4?s=80" width="80px;" alt="Benjamin Belaga"/><br /><sub><b>Benjamin Belaga</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=benjaminbelaga" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/romanvalent"><img src="https://avatars.githubusercontent.com/u/14106124?v=4?s=80" width="80px;" alt="romanvalent"/><br /><sub><b>romanvalent</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=romanvalent" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="http://aakshintala.com"><img src="https://avatars.githubusercontent.com/u/748697?v=4?s=80" width="80px;" alt="Amogh Akshintala"/><br /><sub><b>Amogh Akshintala</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=aakshintala" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://www.portfolio.isnakolah.me"><img src="https://avatars.githubusercontent.com/u/47239024?v=4?s=80" width="80px;" alt="Daniel Nakolah"/><br /><sub><b>Daniel Nakolah</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=isnakolah" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/Mitsi-ag"><img src="https://avatars.githubusercontent.com/u/141203898?v=4?s=80" width="80px;" alt="Mitsi-ag"/><br /><sub><b>Mitsi-ag</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=Mitsi-ag" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://www.josecancinolinares.com/en/portfolio"><img src="https://avatars.githubusercontent.com/u/65030646?v=4?s=80" width="80px;" alt="José Cancino Linares"/><br /><sub><b>José Cancino Linares</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=josecancino" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/logancox"><img src="https://avatars.githubusercontent.com/u/28828028?v=4?s=80" width="80px;" alt="logancox"/><br /><sub><b>logancox</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=logancox" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="http://ywmei.ca/index.php"><img src="https://avatars.githubusercontent.com/u/5897309?v=4?s=80" width="80px;" alt="y5mei"/><br /><sub><b>y5mei</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=y5mei" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://hansonkim.github.io"><img src="https://avatars.githubusercontent.com/u/1308073?v=4?s=80" width="80px;" alt="Hanson Kim"/><br /><sub><b>Hanson Kim</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=hansonkim" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/jsvisa"><img src="https://avatars.githubusercontent.com/u/3627395?v=4?s=80" width="80px;" alt="Delweng"/><br /><sub><b>Delweng</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=jsvisa" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/SridarDhandapani"><img src="https://avatars.githubusercontent.com/u/18103118?v=4?s=80" width="80px;" alt="Sridar Dhandapani"/><br /><sub><b>Sridar Dhandapani</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=SridarDhandapani" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://weavr.care/"><img src="https://avatars.githubusercontent.com/u/16575586?v=4?s=80" width="80px;" alt="Seunghwan Kim"/><br /><sub><b>Seunghwan Kim</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=shwankim7" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://rasterfactory.com/"><img src="https://avatars.githubusercontent.com/u/194952?v=4?s=80" width="80px;" alt="Ryan"/><br /><sub><b>Ryan</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=rasterfactory" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://www.akeeba.com/"><img src="https://avatars.githubusercontent.com/u/256041?v=4?s=80" width="80px;" alt="Nicholas K. Dionysopoulos"/><br /><sub><b>Nicholas K. Dionysopoulos</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=nikosdion" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/jzd101"><img src="https://avatars.githubusercontent.com/u/48935928?v=4?s=80" width="80px;" alt="jzd101"/><br /><sub><b>jzd101</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=jzd101" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/hubert-alch"><img src="https://avatars.githubusercontent.com/u/3193430?v=4?s=80" width="80px;" alt="Hubert"/><br /><sub><b>Hubert</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=hubert-alch" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://pingie.com/"><img src="https://avatars.githubusercontent.com/u/4954230?v=4?s=80" width="80px;" alt="simplytoast1"/><br /><sub><b>simplytoast1</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=simplytoast1" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/cszhe"><img src="https://avatars.githubusercontent.com/u/3096714?v=4?s=80" width="80px;" alt="Jason He"/><br /><sub><b>Jason He</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=cszhe" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/arkad-cm"><img src="https://avatars.githubusercontent.com/u/96408707?v=4?s=80" width="80px;" alt="Arkadev Banerjee"/><br /><sub><b>Arkadev Banerjee</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=arkad-cm" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/shoo99"><img src="https://avatars.githubusercontent.com/u/10192375?v=4?s=80" width="80px;" alt="shoo99"/><br /><sub><b>shoo99</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=shoo99" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/joakimt90"><img src="https://avatars.githubusercontent.com/u/251045847?v=4?s=80" width="80px;" alt="joakimt90"/><br /><sub><b>joakimt90</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=joakimt90" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://roy-tong.github.io/"><img src="https://avatars.githubusercontent.com/u/196586291?v=4?s=80" width="80px;" alt="Roy Tong"/><br /><sub><b>Roy Tong</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=roy-tong" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/nhonn"><img src="https://avatars.githubusercontent.com/u/22555991?v=4?s=80" width="80px;" alt="Noah"/><br /><sub><b>Noah</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=nhonn" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/NicholasLea"><img src="https://avatars.githubusercontent.com/u/46642679?v=4?s=80" width="80px;" alt="Nicholas"/><br /><sub><b>Nicholas</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=NicholasLea" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/JawsomeJason"><img src="https://avatars.githubusercontent.com/u/787276?v=4?s=80" width="80px;" alt="Jason Featheringham ⊙ω⊙"/><br /><sub><b>Jason Featheringham ⊙ω⊙</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=JawsomeJason" title="Code">💻</a></td>
      <td align="center" valign="top" width="16.66%"><a href="https://github.com/brandonpierce"><img src="https://avatars.githubusercontent.com/u/10343786?v=4?s=80" width="80px;" alt="Brandon Pierce"/><br /><sub><b>Brandon Pierce</b></sub></a><br /><a href="https://github.com/tddworks/claudebar/commits?author=brandonpierce" title="Code">💻</a></td>
    </tr>
  </tbody>
  <tfoot>
    <tr>
      <td align="center" size="13px" colspan="6">
        <img src="https://raw.githubusercontent.com/all-contributors/all-contributors-cli/1b8533af435da9854653492b1327a23a4dbd0a10/assets/logo-small.svg">
          <a href="https://all-contributors.js.org/docs/en/bot/usage">Add your contributions</a>
        </img>
      </td>
    </tr>
  </tfoot>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!

To credit someone, comment on any issue or pull request:

```
@all-contributors please add @username for code, doc
```

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

The notch view uses [matrix-swift](https://github.com/mana-am/matrix-swift), which has its own license: you may use it in an app, but not republish its components as a standalone library.
