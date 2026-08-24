import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vitest";
import { attachmentUrl } from "../../src/lib/vault-attachments.ts";

const root = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../..",
);
const vault = path.join(root, "tests/fixtures/publication-vault");

function build(extra: string[] = []) {
	const out = mkdtempSync(path.join(tmpdir(), "oyster-publication-"));
	const result = spawnSync(
		process.execPath,
		["bin/oyster-publish.mjs", "build", "-v", vault, "-o", out, ...extra],
		{ cwd: root, encoding: "utf8" },
	);
	if (result.status !== 0)
		throw new Error(`${result.stdout}\n${result.stderr}`);
	return out;
}

const page = (out: string, route: string) =>
	existsSync(path.join(out, route, "index.html"));

test("folder rules, explicit overrides, linked closure, and attachment closure agree", () => {
	const out = build();
	expect(page(out, "blog/post")).toBe(true);
	expect(page(out, "reference")).toBe(true);
	expect(page(out, "explicit")).toBe(true);
	expect(page(out, "blog/drafts/draft")).toBe(false);
	expect(page(out, "secret")).toBe(false);
	expect(page(out, "unlinked")).toBe(false);
	expect(existsSync(path.join(out, attachmentUrl("media/used.svg")))).toBe(
		true,
	);
	expect(existsSync(path.join(out, attachmentUrl("media/private.svg")))).toBe(
		false,
	);
});

test("published-only remains strict publish true", () => {
	const out = build(["--published-only"]);
	expect(page(out, "explicit")).toBe(true);
	expect(page(out, "blog/post")).toBe(false);
	expect(page(out, "reference")).toBe(false);
});
