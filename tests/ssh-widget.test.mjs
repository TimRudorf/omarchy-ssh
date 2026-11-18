import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const base = new URL("../", import.meta.url);
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("Model.js", base), "utf8"), context);
const row = {
  host: "test-server", aliases: ["test-server"], state: "open",
  policy: "master-only", sessions: 2, destination: "user@host:22", error: ""
};
const status = (hosts = [row]) => JSON.stringify({ version: 1, hosts, errors: [] });

test("valid status and unknown session count", () => {
  assert.equal(context.parse(status()).hosts[0].sessions, 2);
  assert.equal(context.parse(status([{ ...row, sessions: null }])).hosts[0].sessions, null);
});

test("reject oversized, malformed, injected aliases and invalid states", () => {
  for (const input of [
    "x".repeat(1048577), "[]", status([{ ...row, host: "-oProxyCommand=bad" }]),
    status([{ ...row, host: "<img src=https://example.invalid>" }]),
    status([{ ...row, sessions: -1 }]), status([{ ...row, state: "made-up" }]),
    status(Array(257).fill(row)), status([row, row])
  ]) assert.throws(() => context.parse(input));
});

test("untrusted errors stay text and shared tooltip sink is escaped", () => {
  const injection = '<img src="https://example.invalid/tracker">';
  assert.equal(context.parse(status([{ ...row, error: injection }])).hosts[0].error, injection);
  assert.equal(context.plainTooltip(injection), '&lt;img src="https://example.invalid/tracker"&gt;');
  const qml = readFileSync(new URL("Panel.qml", base), "utf8");
  assert.match(qml, /component PlainText: Text\s*\{\s*textFormat: Text\.PlainText/);
  for (const line of qml.split("\n").filter(line => line.includes("tooltipText:")))
    assert.match(line, /Model\.plainTooltip\(/);
});

test("German and English catalogs have identical keys", () => {
  const de = JSON.parse(readFileSync(new URL("i18n/de.json", base)));
  const en = JSON.parse(readFileSync(new URL("i18n/en.json", base)));
  assert.deepEqual(Object.keys(de).sort(), Object.keys(en).sort());
});
