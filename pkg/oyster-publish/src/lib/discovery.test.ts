import { expect, test } from "vitest";
import {
	adjacentNotes,
	chronologicalNotes,
	navigationNotes,
	tagGroups,
} from "./discovery.ts";
import { buildVaultManifest } from "./vault-manifest.ts";

const notes = buildVaultManifest([
	{
		path: "b.md",
		body: "B",
		data: {
			title: "B",
			tags: ["OCaml", "C++"],
			date: new Date("2026-01-02"),
			navOrder: 1,
		},
	},
	{
		path: "a.md",
		body: "A",
		data: {
			title: "A",
			tags: ["ocaml", "C#"],
			date: new Date("2026-01-03"),
			navOrder: 2,
		},
	},
	{
		path: "hidden.md",
		body: "H",
		data: { navHidden: true, date: new Date("2026-01-04") },
	},
	{ path: "undated.md", body: "U", data: {} },
]).notes;

test("chronology uses explicit dates and excludes undated notes", () => {
	expect(chronologicalNotes(notes).map((note) => note.path)).toEqual([
		"hidden.md",
		"a.md",
		"b.md",
	]);
});

test("navigation order composes explicit order, path fallback, and hidden notes", () => {
	expect(navigationNotes(notes).map((note) => note.path)).toEqual([
		"b.md",
		"a.md",
		"undated.md",
	]);
	expect(adjacentNotes(notes, "a.md")).toMatchObject({
		previous: { path: "b.md" },
		next: { path: "undated.md" },
	});
});

test("tags group case-insensitively and disambiguate slug collisions", () => {
	const groups = tagGroups(notes);
	expect(
		groups.find((group) => group.label.toLowerCase() === "ocaml")?.notes,
	).toHaveLength(2);
	const punctuation = groups.filter(
		(group) => group.label === "C++" || group.label === "C#",
	);
	expect(new Set(punctuation.map((group) => group.slug)).size).toBe(2);
});
