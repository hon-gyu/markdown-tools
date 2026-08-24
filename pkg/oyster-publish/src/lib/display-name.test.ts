// How a note is named on screen. The rule is "frontmatter title, else the name
// on disk, never prettified" — so most of these cases are about *not* mangling a
// name that a slug would have flattened.

import { expect, test } from "vitest";
import { displayName, nameSegments, tabTitle } from "./display-name.ts";

const plain = { ancestorInitials: false };
const initials = { ancestorInitials: true };

// == displayName =============================================================

test("name: the filename as it is on disk, capitals and all", () => {
	expect(displayName("Modern AI/Transformers.md")).toBe("Transformers");
	// Never title-cased: a slug-shaped filename stays slug-shaped.
	expect(displayName("getting-started/first-steps.md")).toBe("first-steps");
});

test("name: frontmatter title wins over the filename", () => {
	expect(
		displayName("Modern AI/Transformers.md", "Attention Is All You Need"),
	).toBe("Attention Is All You Need");
});

test("name: an index note is named for its folder, not 'index'", () => {
	expect(displayName("Field Notes/index.md")).toBe("Field Notes");
});

// == nameSegments ============================================================

test("segments: authored names, index collapsed into its directory", () => {
	expect(nameSegments("Modern AI/Transformers.md")).toEqual([
		"Modern AI",
		"Transformers",
	]);
	expect(nameSegments("Field Notes/index.md")).toEqual(["Field Notes"]);
	// The vault root's own index has no directory to collapse into.
	expect(nameSegments("index.md")).toEqual(["index"]);
});

// == tabTitle ================================================================

test("tab: off by default — just the note's name", () => {
	expect(tabTitle("Pasd/Tasd/Note 1.md", undefined, plain)).toBe("Note 1");
});

test("tab: ancestors abbreviate to their initials", () => {
	expect(tabTitle("Pasd/Tasd/Note 1.md", undefined, initials)).toBe(
		"P/T/Note 1",
	);
});

test("tab: a note with no ancestors is unchanged", () => {
	expect(tabTitle("Modern AI.md", undefined, initials)).toBe("Modern AI");
});

test("tab: only ancestors shrink — the note keeps its full name", () => {
	expect(tabTitle("Modern AI/Transformers.md", undefined, initials)).toBe(
		"M/Transformers",
	);
});

test("tab: a frontmatter title is still the final part", () => {
	expect(tabTitle("Pasd/Tasd/Note 1.md", "Real Title", initials)).toBe(
		"P/T/Real Title",
	);
});

test("tab: an index note's own folder is the name, not an ancestor", () => {
	expect(tabTitle("Pasd/Tasd/index.md", undefined, initials)).toBe("P/Tasd");
});

test("tab: initials are whole code points, not half a character", () => {
	// A naive charAt(0) would slice a surrogate pair and emit a broken glyph.
	expect(tabTitle("笔记/示例.md", undefined, initials)).toBe("笔/示例");
	expect(tabTitle("🌱 seedlings/Notes.md", undefined, initials)).toBe(
		"🌱/Notes",
	);
});
