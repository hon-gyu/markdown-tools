// Unit tests for the pure graph-payload shaping. Run with `npm test` (vitest).
// Covers the shaping rules the widget relies on: every file becomes a node,
// links become deduped edges (directed here, so reciprocal pairs stay as two),
// self/unknown links are dropped, degree counts incident edges, and folder is
// derived from the path.

import { expect, test } from "vitest";
import { buildGraphData, localNodeIds, resolveFocusId } from "./graph-data.ts";
import type { LinkGraph, NoteFile } from "./wikilink.ts";

const files: NoteFile[] = [
	{ path: "index.md", slug: "/" },
	{ path: "rust/index.md", slug: "/rust" },
	{ path: "rust/async.md", slug: "/rust/async" },
	{ path: "postgres/indexes.md", slug: "/postgres/indexes" },
];

// forward: index -> rust/async; rust/async -> rust/index; rust/index -> rust/async
// (a reciprocal pair, which must collapse to one edge).
function graph(forward: Record<string, string[]>): LinkGraph {
	return {
		forward: new Map(Object.entries(forward)),
		backlinks: new Map(), // unused by buildGraphData
	};
}

const titles = new Map([
	["index.md", "Home"],
	["rust/index.md", "Rust"],
	["rust/async.md", "Async"],
	["postgres/indexes.md", "Indexes"],
]);
const tags = new Map([["rust/async.md", ["concurrency"]]]);

test("every file becomes a node with derived folder and tags", () => {
	const { nodes } = buildGraphData(files, graph({}), titles, tags);
	expect(nodes).toHaveLength(4);

	const byId = new Map(nodes.map((n) => [n.id, n]));
	expect(byId.get("index.md")).toMatchObject({
		folder: "",
		title: "Home",
		href: "/",
	});
	expect(byId.get("rust/async.md")).toMatchObject({
		folder: "rust",
		tags: ["concurrency"],
		href: "/rust/async",
	});
	// A file with no tags entry defaults to [].
	expect(byId.get("rust/index.md")?.tags).toEqual([]);
});

test("directed: reciprocal links stay as two distinct edges", () => {
	const { edges, directed } = buildGraphData(
		files,
		graph({
			"rust/async.md": ["rust/index.md"],
			"rust/index.md": ["rust/async.md"],
		}),
		titles,
		tags,
	);
	expect(directed).toBe(true);
	expect(edges).toHaveLength(2);
	expect(edges).toContainEqual({
		source: "rust/async.md",
		target: "rust/index.md",
	});
	expect(edges).toContainEqual({
		source: "rust/index.md",
		target: "rust/async.md",
	});
});

test("self-links and links to unknown paths are dropped", () => {
	const { edges } = buildGraphData(
		files,
		graph({ "index.md": ["index.md", "does/not/exist.md", "rust/async.md"] }),
		titles,
		tags,
	);
	expect(edges).toEqual([{ source: "index.md", target: "rust/async.md" }]);
});

test("degree counts incident edges (directed: each direction counts)", () => {
	const { nodes } = buildGraphData(
		files,
		graph({
			"index.md": ["rust/async.md", "postgres/indexes.md"],
			"rust/async.md": ["index.md"], // reciprocal with index -> two edges
		}),
		titles,
		tags,
	);
	const deg = new Map(nodes.map((n) => [n.id, n.degree]));
	// index->async, index->indexes, async->index = 3 edges.
	expect(deg.get("index.md")).toBe(3); // out to async + out to indexes + in from async
	expect(deg.get("rust/async.md")).toBe(2); // in from index + out to index
	expect(deg.get("postgres/indexes.md")).toBe(1);
	expect(deg.get("rust/index.md")).toBe(0); // isolated
});

// == resolveFocusId ==========================================================

// A note page knows its own URL, not its vault path, so it hands the widget an
// href; other callers hand it an id. Both must land on the same node. When this
// returns null the widget has nothing to center on and falls back to the global
// view — which is exactly how the local view went missing on a real vault, where
// the page's URL and the node's href were derived by two different rules.

const data = buildGraphData(
	files,
	graph({ "index.md": ["rust/async.md"], "rust/async.md": ["rust/index.md"] }),
	titles,
	tags,
);

test("focus: resolves a vault path (node id)", () => {
	expect(resolveFocusId(data, "rust/async.md")).toBe("rust/async.md");
});

test("focus: resolves an href (what a note page holds)", () => {
	expect(resolveFocusId(data, "/rust/async")).toBe("rust/async.md");
});

test("focus: an unknown focus resolves to null, not a wrong node", () => {
	expect(resolveFocusId(data, "/Rust/Async")).toBeNull(); // pre-slug URL shape
	expect(resolveFocusId(data, "ghost.md")).toBeNull();
	expect(resolveFocusId(data, null)).toBeNull();
	expect(resolveFocusId(data, undefined)).toBeNull();
});

// == localNodeIds ============================================================

test("local: the focus plus its neighbours, and nothing further", () => {
	// index -> async -> rust/index. From async, both are one hop away; postgres is
	// unreachable and must stay out.
	expect([...localNodeIds(data, "rust/async.md")].sort()).toEqual([
		"index.md",
		"rust/async.md",
		"rust/index.md",
	]);
});

test("local: links count in either direction", () => {
	// rust/index only ever appears as a link *target*, but its linker is still a
	// neighbour of it.
	expect([...localNodeIds(data, "rust/index.md")].sort()).toEqual([
		"rust/async.md",
		"rust/index.md",
	]);
});

test("local: an isolated note is a view of just itself", () => {
	expect([...localNodeIds(data, "postgres/indexes.md")]).toEqual([
		"postgres/indexes.md",
	]);
});
