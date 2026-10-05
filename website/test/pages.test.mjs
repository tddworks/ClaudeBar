// The site's own laws, checked on the files that ship: `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../public/${path}`, import.meta.url), "utf8");
const headers = read("_headers");
const policy = headers;
const pages = { landing: read("index.html"), board: read("leaderboard/index.html") };

test("every page has a strict policy: its own scripts, and only the API to talk to", () => {
  assert.match(policy, /^\/\*$/m);
  assert.match(policy, /default-src 'none'/);
  assert.match(policy, /script-src 'self' 'unsafe-inline';/);
  assert.match(policy, /connect-src 'self' https:\/\/claudebar-api\.tddworks\.com;/);
  assert.match(policy, /frame-ancestors 'none'/);
  assert.match(policy, /X-Content-Type-Options: nosniff/);
});

test("the board writes standings as text, never as HTML, and loads its globe from this origin", () => {
  assert.doesNotMatch(pages.board, /innerHTML/);
  assert.match(pages.board, /src="\/leaderboard\/globe\.js"/);
  assert.match(pages.board, /const API = "https:\/\/claudebar-api\.tddworks\.com";/);
});

test("the landing page shows sample members only, labelled as such", () => {
  const sample = pages.landing.slice(pages.landing.indexOf('id="leaderboard"'), pages.landing.indexOf("</section>", pages.landing.indexOf('id="leaderboard"')));
  assert.match(sample, /Sample data/);
  assert.match(sample, /not real members/);
  const names = [...sample.matchAll(/@([a-z0-9_-]+)/gi)].map((m) => m[1]);
  assert.ok(names.length > 0);
  for (const name of names) assert.ok(name === "you" || name.startsWith("sample-"), `@${name} isn't a sample name`);
});

test("Sparkle's feed stays on GitHub Pages", () => {
  assert.match(pages.landing, /https:\/\/tddworks\.github\.io\/ClaudeBar\/appcast\.xml/);
});
