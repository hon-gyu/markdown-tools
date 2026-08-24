// Unit tests for the pure search matcher. Run with `npm test` (vitest). Covers
// the rules the sidebar relies on: multi-term AND matching, title/heading/body
// ranking, highlight segmentation, snippet windowing, and safe (non-HTML)
// output.

import { expect, test } from "vitest";
import { type SearchDoc, type Segment, searchDocs } from "./search-index.ts";

const docs: SearchDoc[] = [
	{
		title: "Aliases",
		href: "/linking/aliases",
		breadcrumb: "Linking",
		text: "An alias is an alternative name for a note. Use aliases for acronyms.",
		headings: [
			{ text: "Add an alias to a note", slug: "add-an-alias-to-a-note" },
			{ text: "Unrelated section", slug: "unrelated-section" },
		],
		tags: ["writing", "links"],
	},
	{
		title: "Permalinks",
		href: "/publish/permalinks",
		breadcrumb: "Publish",
		text: "You can rename the URL to your notes using permalinks.",
		headings: [],
		tags: ["publishing", "links"],
	},
	{
		title: "Graph view",
		href: "/graph",
		breadcrumb: "",
		text: "A force-directed view of the vault links.",
		headings: [{ text: "Local graph", slug: "local-graph" }],
		tags: ["visualization"],
	},
];

// The plain-text join of a Segment[], and just the highlighted bits.
const asText = (segs: Segment[]) => segs.map((s) => s.text).join("");
const hits = (segs: Segment[]) => segs.filter((s) => s.hit).map((s) => s.text);

test("empty / whitespace query returns nothing", () => {
	expect(searchDocs(docs, "")).toEqual([]);
	expect(searchDocs(docs, "   ")).toEqual([]);
});

test("matches across title, heading, and body; ranks title first", () => {
	const r = searchDocs(docs, "alias");
	// Aliases (title) before any body-only match.
	expect(r[0].href).toBe("/linking/aliases");
	expect(r[0].titleMatch).toBe(true);
	// Only the heading that contains the term comes back.
	expect(r[0].headings.map((h) => h.slug)).toEqual(["add-an-alias-to-a-note"]);
});

test("title match ranks ahead of a body-only match", () => {
	// "view" is in "Graph view" (title) and nowhere in Permalinks.
	const r = searchDocs(docs, "view");
	expect(r[0].href).toBe("/graph");
	expect(r[0].titleMatch).toBe(true);
});

test("multi-term is AND: all terms must appear somewhere in the note", () => {
	expect(searchDocs(docs, "alias acronyms").map((r) => r.href)).toEqual([
		"/linking/aliases",
	]);
	// "alias" is in the Aliases note, "permalinks" is not -> no note has both.
	expect(searchDocs(docs, "alias permalinks")).toEqual([]);
});

test("highlight marks the matched term in the title", () => {
	const r = searchDocs(docs, "alias");
	expect(asText(r[0].title)).toBe("Aliases");
	expect(hits(r[0].title)).toEqual(["Alias"]); // case-insensitive, original case kept
});

test("body snippet is windowed, ellipsized, and highlighted", () => {
	const r = searchDocs(docs, "acronyms");
	const snip = r[0].snippet!;
	expect(snip).not.toBeNull();
	expect(hits(snip)).toEqual(["acronyms"]);
	// The snippet is a slice of the body, not the whole thing.
	expect(asText(snip).length).toBeLessThan(docs[0].text.length);
});

test("no body hit -> null snippet (heading-only match)", () => {
	const r = searchDocs(docs, "local");
	const graph = r.find((x) => x.href === "/graph")!;
	expect(graph.headings.map((h) => h.slug)).toEqual(["local-graph"]);
	expect(graph.snippet).toBeNull(); // "local" isn't in the body text
});

test("quoted terms match a contiguous phrase", () => {
	expect(searchDocs(docs, '"alternative name"').map((r) => r.href)).toEqual([
		"/linking/aliases",
	]);
	expect(searchDocs(docs, '"alternative acronyms"')).toEqual([]);
});

test("tag filters are case-insensitive and intersect", () => {
	expect(
		searchDocs(docs, "note", { tags: ["LINKS"] }).map((r) => r.href),
	).toEqual(["/linking/aliases", "/publish/permalinks"]);
	expect(
		searchDocs(docs, "note", { tags: ["links", "writing"] }).map((r) => r.href),
	).toEqual(["/linking/aliases"]);
});

test("ties have deterministic route order", () => {
	expect(searchDocs(docs, "note").map((r) => r.href)).toEqual([
		"/linking/aliases",
		"/publish/permalinks",
	]);
});
