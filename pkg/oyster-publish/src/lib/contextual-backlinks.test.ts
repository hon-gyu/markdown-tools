import { expect, test } from "vitest";
import { contextualBacklinks } from "./contextual-backlinks.ts";
import type { NoteRecord } from "./vault-manifest.ts";

function note(overrides: Partial<NoteRecord>): NoteRecord {
	return {
		path: "source.md",
		slug: "/source",
		originalSlug: "/source",
		title: "Source",
		tags: [],
		headings: [],
		anchors: [],
		excerpt: "",
		text: "",
		links: [],
		aliases: [],
		navHidden: false,
		published: true,
		routed: true,
		...overrides,
	};
}

test("groups references per source and links to the referring heading", () => {
	const links = [
		{
			target: "Target",
			fragment: "Details",
			embed: false as const,
			syntax: "wikilink" as const,
			status: "resolved" as const,
			destinationKind: "note" as const,
			destinationPath: "target.md",
			context: "Compare Target details with the overview.",
			sourceFragment: "comparison",
		},
		{
			target: "Target",
			fragment: null,
			embed: false as const,
			syntax: "wikilink" as const,
			status: "resolved" as const,
			destinationKind: "note" as const,
			destinationPath: "target.md",
			context: "The conclusion also cites Target.",
			sourceFragment: "conclusion",
		},
	];
	expect(contextualBacklinks([note({ links })], "target.md")).toEqual([
		{
			slug: "/source#comparison",
			title: "Source",
			count: 2,
			mentions: [
				{
					context: "Compare Target details with the overview.",
					targetFragment: "Details",
					href: "/source#comparison",
				},
				{
					context: "The conclusion also cites Target.",
					targetFragment: null,
					href: "/source#conclusion",
				},
			],
		},
	]);
});

test("omits unrelated and unresolved links", () => {
	const source = note({
		links: [
			{
				target: "Target",
				fragment: null,
				embed: false,
				syntax: "wikilink",
				status: "missing",
				context: "Missing target",
				sourceFragment: null,
			},
		],
	});
	expect(contextualBacklinks([source], "target.md")).toEqual([]);
});
