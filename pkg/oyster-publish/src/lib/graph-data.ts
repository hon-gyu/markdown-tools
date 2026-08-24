// Shapes the vault's link graph into the flat node/edge payload the client
// graph widget consumes. Pure — no Astro, no DOM — so it's unit-testable on
// plain data, like wikilink.ts. The Astro-coupled `note-index.ts` feeds it.

import type { LinkGraph, NoteFile } from "./wikilink.ts";

// Types
// ====================

// One graph node. `id` is the vault-relative path (stable key, matches the link
// graph); `href` is where a click navigates; `folder` is the containing
// directory ("" at the root) used to color/cluster; `degree` is the number of
// incident edges, used by the simulation to identify isolated notes.
export interface GraphNode {
	id: string;
	title: string;
	href: string;
	folder: string;
	tags: string[];
	degree: number;
}

// An edge from `source` to `target` (both node ids). When the graph is
// `directed`, source→target and target→source are kept as two separate edges
// (so a reciprocal link pair draws as two arrows); otherwise a pair collapses
// to a single line and the direction is not meaningful.
export interface GraphEdge {
	source: string;
	target: string;
}

export interface GraphData {
	nodes: GraphNode[];
	edges: GraphEdge[];
	// Whether edges carry direction (see DIRECTED). Passed through to the client
	// so the renderer knows to draw arrowheads and split reciprocal pairs.
	directed: boolean;
}

// Knobs
// ====================

// When true, edges are directed: each resolved link becomes its own edge, so
// two notes that link to each other yield two edges (at most). When false,
// reciprocal links collapse into one undirected edge. Hardcoded for now —
// flip it here to change the whole graph's behaviour.
export const DIRECTED = true;

// Build
// ====================

// The directory portion of a vault-relative path: "rust/async.md" -> "rust",
// "index.md" -> "" (root). An index note belongs to its own directory, not the
// parent, matching how it stands in for that directory in the nav.
function folderOf(path: string): string {
	const slash = path.lastIndexOf("/");
	return slash === -1 ? "" : path.slice(0, slash);
}

// A key that dedups edges. In directed mode direction is significant, so A->B
// and B->A get distinct keys; in undirected mode they share one key and
// collapse. The tab separator can't appear in a vault path.
function edgeKey(source: string, target: string): string {
	if (DIRECTED) return `${source}\t${target}`;
	return source < target ? `${source}\t${target}` : `${target}\t${source}`;
}

// Fold the resolved forward-link graph into flat nodes + deduped edges. Every
// file becomes a node (isolated notes included). With DIRECTED on, each
// resolved link is its own edge (reciprocal pairs stay as two); with it off,
// each connected pair collapses to one. `degree` counts incident edges.
export function buildGraphData(
	files: NoteFile[],
	graph: LinkGraph,
	titleByPath: Map<string, string>,
	tagsByPath: Map<string, string[]>,
): GraphData {
	const known = new Set(files.map((f) => f.path));

	const seen = new Set<string>();
	const edges: GraphEdge[] = [];
	const degree = new Map<string, number>(files.map((f) => [f.path, 0]));

	for (const [source, targets] of graph.forward) {
		if (!known.has(source)) continue;
		for (const target of targets) {
			// A self-link or a link to an unknown path yields no drawable edge.
			if (source === target || !known.has(target)) continue;
			const key = edgeKey(source, target);
			if (seen.has(key)) continue;
			seen.add(key);
			edges.push({ source, target });
			degree.set(source, degree.get(source)! + 1);
			degree.set(target, degree.get(target)! + 1);
		}
	}

	const nodes: GraphNode[] = files.map((f) => ({
		id: f.path,
		title: titleByPath.get(f.path) ?? f.path,
		href: f.slug,
		folder: folderOf(f.path),
		tags: tagsByPath.get(f.path) ?? [],
		degree: degree.get(f.path) ?? 0,
	}));

	return { nodes, edges, directed: DIRECTED };
}

// Scoping
// ====================
//
// Which slice of the vault a graph view shows: the whole thing ("global"), or
// the neighbourhood around one note ("local"). Both live here rather than in the
// client island so they're testable on plain data — the local view silently
// degrading to a global one was a real bug, and a DOM-only home for this logic
// was why nothing caught it.

// How many hops from the focus note the local view reaches.
export const LOCAL_DEPTH = 1;

// The id of the note a local view centers on. Callers hold either a node id (a
// vault path) or an href (a URL), so `focus` is matched against ids first and
// hrefs second. Null when no node matches — the caller has nothing to localise
// around and must fall back to the global view.
export function resolveFocusId(
	data: GraphData,
	focus: string | null | undefined,
): string | null {
	if (focus == null) return null;
	const byId = data.nodes.find((n) => n.id === focus);
	if (byId) return byId.id;
	return data.nodes.find((n) => n.href === focus)?.id ?? null;
}

// The node ids visible in the local view: the focus note, plus every note within
// LOCAL_DEPTH hops of it. Links are followed in *either* direction — a note that
// links to the focus is as much a neighbour as one the focus links to.
export function localNodeIds(data: GraphData, focusId: string): Set<string> {
	const adj = new Map<string, Set<string>>(
		data.nodes.map((n) => [n.id, new Set<string>()]),
	);
	for (const e of data.edges) {
		adj.get(e.source)?.add(e.target);
		adj.get(e.target)?.add(e.source);
	}

	const visible = new Set<string>([focusId]);
	let frontier = [focusId];
	for (let depth = 0; depth < LOCAL_DEPTH; depth++) {
		const next: string[] = [];
		for (const id of frontier) {
			for (const nb of adj.get(id) ?? []) {
				if (!visible.has(nb)) {
					visible.add(nb);
					next.push(nb);
				}
			}
		}
		frontier = next;
	}
	return visible;
}
