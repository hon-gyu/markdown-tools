// The graph-view client island: a force-directed render of the vault link
// graph. It reads the graph payload inlined by `GraphView.astro` and drives a
// d3-force simulation over an SVG.
//
// Kept deliberately small: layout + the interactions Obsidian's graph has
// (drag, zoom/pan, hover highlight, click to open). Pure data shaping lives in
// lib/graph-data.ts; this file is only the visual layer.
//
// Two things beyond the first cut:
//  - Directed edges: each edge draws as an arrow. A reciprocal pair (A->B and
//    B->A) bows to opposite sides so both arrows stay visible.
//  - Scope: a "local" view (the subgraph around a focus note) vs a "global"
//    view (the whole vault). The same `mount` renders either, and drives both
//    the inline right-rail panel and the expanded modal.

import { drag as d3drag } from "d3-drag";
import {
	forceCenter,
	forceCollide,
	forceLink,
	forceManyBody,
	forceRadial,
	forceSimulation,
	forceX,
	forceY,
	type Simulation,
} from "d3-force";
import { select } from "d3-selection";
import { zoom as d3zoom, zoomIdentity } from "d3-zoom";
// Imported for its side effect: it adds `.transition()` to every d3 selection,
// which `fitToContent` animates the zoom with. d3-zoom happens to pull it in
// transitively, so this worked by luck — depend on it outright instead.
import "d3-transition";
import {
	type GraphData,
	type GraphNode,
	localNodeIds,
	resolveFocusId,
} from "../lib/graph-data.ts";

// d3-force mutates nodes with x/y/vx/vy and swaps edge endpoints from ids to
// node objects once the simulation initializes.
type SimNode = GraphNode & {
	x: number;
	y: number;
	vx: number;
	vy: number;
	fx?: number | null;
	fy?: number | null;
};
type SimEdge = { source: SimNode; target: SimNode; hasTwin: boolean };

export type Scope = "local" | "global";

export interface MountOptions {
	// Node id (vault path) or href of the note to center a "local" view on.
	// Matched against node.id first, then node.href. Null => no focus (local
	// view then equals global).
	focus?: string | null;
	scope?: Scope;
}

export interface GraphController {
	setScope(scope: Scope): void;
	getScope(): Scope;
	reset(): void;
	destroy(): void;
}

// Tunables
// ====================

const NODE_R = 7; // quiet default; the focused note receives the emphasis
const FOCUS_NODE_R = 9;
const LINK_DISTANCE = 60;
const CHARGE = -160;
const ORPHAN_CHARGE = -40;
const VELOCITY_DECAY = 0.6; // friction; higher = less overshoot/bounce
const REDRAW_ALPHA = 0.16; // small reheat when adding/removing scope nodes
const CENTER_PULL = 0.035; // keeps disconnected components from drifting away
const ORPHAN_RING_PULL = 0.18; // holds unlinked notes on their seeded ring
const NEW_NODE_OFFSET = 24; // seed linked additions close to a known neighbour
const LABEL_FONT_SIZE = 12;
const LABEL_ZOOM_THRESHOLD = 0.7; // hide labels when zoomed further out than this
const ARROW_PAD = 3; // gap between an arrowhead and its target node
const CURVE = 14; // how far a reciprocal edge bows off the straight line
const FIT_MARGIN = 28;
const GLOBAL_FIT_SCALE = 1.1;
const LOCAL_FIT_SCALE = 1.2;

// A restrained, cool palette keyed by top-level folder. Values live in the
// component CSS so they adapt to the site's light/dark surfaces instead of
// looking like an unrelated data-visualisation theme.
const PALETTE = [
	"var(--graph-folder-1)",
	"var(--graph-folder-2)",
	"var(--graph-folder-3)",
	"var(--graph-folder-4)",
	"var(--graph-folder-5)",
	"var(--graph-folder-6)",
];
const ROOT_COLOR = "var(--graph-root)"; // notes at the vault root (no folder)

// A per-mount id counter so arrow-marker ids stay unique across the inline
// panel and the modal (which live in the DOM at the same time).
let mountSeq = 0;

// The top-level segment of a folder path drives the color, so a whole subtree
// shares one hue ("a/sub/deep" and "a" are both "a").
function topFolder(folder: string): string {
	return folder === "" ? "" : folder.split("/")[0];
}

// Stable, cheap string hash for deterministic scope-switch seeding. Positions
// must not depend on array order or Math.random(), otherwise toggling the same
// graph repeatedly makes newly introduced nodes jump to different places.
function hashId(id: string): number {
	let hash = 2166136261;
	for (let i = 0; i < id.length; i++) {
		hash ^= id.charCodeAt(i);
		hash = Math.imul(hash, 16777619);
	}
	return hash >>> 0;
}

// Boot
// ====================

// Wire every inline panel rendered by GraphView.astro: mount the graph, then
// hook up the scope toggle, reset, and expand-to-modal buttons. (A page may
// carry more than one panel — e.g. a note's right rail plus an inline graph.)
document.querySelectorAll<HTMLElement>("[data-graph-panel]").forEach((p) => {
	bootPanel(p);
});

function bootPanel(panel: HTMLElement): void {
	const payloadEl = panel.querySelector<HTMLElement>("[data-graph-payload]");
	const mountEl = panel.querySelector<HTMLElement>("[data-graph-mount]");
	if (!payloadEl?.textContent || !mountEl) return;

	const data = JSON.parse(payloadEl.textContent) as GraphData;
	const focus = panel.dataset.graphFocus || null;
	const initialScope = (panel.dataset.graphScope as Scope) || "global";
	const canFocus = resolveFocusId(data, focus) !== null;

	const controller = mount(mountEl, data, { focus, scope: initialScope });

	// The stage overlay is the first [data-graph-controls]-ish group; the modal's
	// own controls are wired separately in wireModal. Scope down to this stage.
	const stage = mountEl.parentElement ?? panel;

	// Scope toggle. Only meaningful when there's a focus note to localise around.
	const toggle = stage.querySelector<HTMLButtonElement>("[data-graph-toggle]");
	if (toggle) {
		if (!canFocus) {
			toggle.hidden = true;
		} else {
			syncToggle(toggle, controller.getScope());
			toggle.addEventListener("click", () => {
				const next = controller.getScope() === "local" ? "global" : "local";
				controller.setScope(next);
				syncToggle(toggle, next);
			});
		}
	}

	// Reset zoom/pan and any manual node drags back to the framed default.
	stage
		.querySelector<HTMLButtonElement>("[data-graph-reset]")
		?.addEventListener("click", () => controller.reset());

	// Expand: pop the graph open in a full-viewport modal, mounted fresh so the
	// two instances don't fight over the same DOM/simulation.
	const expand = panel.querySelector<HTMLButtonElement>("[data-graph-expand]");
	const modal = panel.querySelector<HTMLElement>("[data-graph-modal]");
	if (expand && modal) {
		wireModal(expand, modal, data, {
			focus,
			canFocus,
			scope: controller.getScope(),
		});
	}
}

// Reflect the current scope on the toggle: pressed = showing the global view,
// and the tooltip advertises where a click will take you.
function syncToggle(btn: HTMLButtonElement, scope: Scope): void {
	const global = scope === "global";
	btn.setAttribute("aria-pressed", String(global));
	btn.title = global ? "Show local view" : "Show global view";
}

function wireModal(
	expand: HTMLButtonElement,
	modal: HTMLElement,
	data: GraphData,
	cfg: { focus: string | null; canFocus: boolean; scope: Scope },
): void {
	const mountEl = modal.querySelector<HTMLElement>("[data-graph-mount]");
	const toggle = modal.querySelector<HTMLButtonElement>("[data-graph-toggle]");
	const reset = modal.querySelector<HTMLButtonElement>("[data-graph-reset]");
	const closers = modal.querySelectorAll<HTMLElement>("[data-graph-close]");
	if (!mountEl) return;

	let controller: GraphController | null = null;

	const open = (): void => {
		modal.hidden = false;
		document.body.style.overflow = "hidden"; // freeze the page behind the modal
		controller = mount(mountEl, data, { focus: cfg.focus, scope: cfg.scope });
		if (toggle) {
			if (!cfg.canFocus) {
				toggle.hidden = true;
			} else {
				toggle.hidden = false;
				syncToggle(toggle, controller.getScope());
			}
		}
	};

	const close = (): void => {
		controller?.destroy();
		controller = null;
		modal.hidden = true;
		document.body.style.overflow = "";
	};

	expand.addEventListener("click", open);
	closers.forEach((el) => {
		el.addEventListener("click", close);
	});
	toggle?.addEventListener("click", () => {
		if (!controller) return;
		const next = controller.getScope() === "local" ? "global" : "local";
		controller.setScope(next);
		syncToggle(toggle, next);
	});
	reset?.addEventListener("click", () => controller?.reset());
	document.addEventListener("keydown", (e) => {
		if (e.key === "Escape" && !modal.hidden) close();
	});
}

// Mount
// ====================

// Render `data` into `container` and return a controller. A scope change tears
// the SVG down and re-renders — simpler than diffing, and the graphs are small.
export function mount(
	container: HTMLElement,
	data: GraphData,
	opts: MountOptions = {},
): GraphController {
	const uid = ++mountSeq;
	const focusId = resolveFocusId(data, opts.focus);
	// Without a focus note there's nothing to localise around, so force global.
	let scope: Scope = focusId ? (opts.scope ?? "local") : "global";

	let sim: Simulation<SimNode, undefined> | null = null;
	// Survives SVG teardown so nodes shared by local/global views do not restart
	// from d3's default phyllotaxis layout on every scope switch.
	const positions = new Map<string, { x: number; y: number }>();
	// Assigned by draw(); resets zoom/pan and clears manual node drags.
	let resetView: () => void = () => {};
	// The first draw settles from scratch; later draws (scope switches) reheat
	// gently so nodes ease into place instead of springing apart.
	let firstDraw = true;

	function draw(): void {
		if (sim) {
			for (const n of sim.nodes()) {
				if (Number.isFinite(n.x) && Number.isFinite(n.y)) {
					positions.set(n.id, { x: n.x, y: n.y });
				}
			}
		}
		sim?.stop();
		container.replaceChildren();

		// Colors are keyed off the *whole* graph's folders so a note keeps its hue
		// whether we're in local or global scope.
		const topFolders = [
			...new Set(data.nodes.map((n) => topFolder(n.folder))),
		].sort();
		const color = (n: GraphNode): string => {
			if (n.id === focusId) return "var(--graph-focus)";
			const tf = topFolder(n.folder);
			if (tf === "") return ROOT_COLOR;
			return PALETTE[topFolders.indexOf(tf) % PALETTE.length];
		};

		// Pick the visible slice for this scope.
		const visible =
			scope === "local" && focusId
				? localNodeIds(data, focusId)
				: new Set(data.nodes.map((n) => n.id));

		const nodes = data.nodes
			.filter((n) => visible.has(n.id))
			.map((n) => ({ ...n })) as SimNode[];

		// Directed keys let us spot reciprocal pairs so they can bow apart.
		const directedKeys = new Set(
			data.edges.map((e) => `${e.source}\t${e.target}`),
		);
		const rawEdges = data.edges.filter(
			(e) => visible.has(e.source) && visible.has(e.target),
		);
		const edges = rawEdges.map((e) => ({
			source: e.source,
			target: e.target,
			hasTwin: data.directed && directedKeys.has(`${e.target}\t${e.source}`),
		})) as unknown as SimEdge[];

		const nodeRadius = (n: GraphNode): number =>
			n.id === focusId ? FOCUS_NODE_R : NODE_R;

		// Undirected adjacency (within the visible slice) for hover highlighting.
		const adj = new Map<string, Set<string>>(
			nodes.map((n) => [n.id, new Set()]),
		);
		for (const e of rawEdges) {
			adj.get(e.source)?.add(e.target);
			adj.get(e.target)?.add(e.source);
		}

		const width = container.clientWidth || 800;
		const height = container.clientHeight || 600;
		const ringRadius = Math.max(36, Math.min(width, height) * 0.28);
		const autoPins = new Map<string, { x: number; y: number }>();

		// A local graph is a neighbourhood: begin with its focus in the middle and
		// the surrounding notes evenly distributed around it. D3's generic spiral
		// seed can put the focus on the perimeter and create avoidable crossings
		// before the forces have any topology-aware geometry to work with.
		if (firstDraw && scope === "local" && focusId) {
			const focusNode = nodes.find((n) => n.id === focusId);
			if (focusNode) {
				focusNode.x = width / 2;
				focusNode.y = height / 2;
				focusNode.fx = focusNode.x;
				focusNode.fy = focusNode.y;
				autoPins.set(focusNode.id, { x: focusNode.x, y: focusNode.y });
			}
			const surrounding = nodes
				.filter((n) => n.id !== focusId)
				.sort((a, b) => a.id.localeCompare(b.id));
			const localRadius = Math.min(
				Math.max(LINK_DISTANCE, Math.min(width, height) * 0.24),
				Math.min(width, height) / 2 - FIT_MARGIN,
			);
			surrounding.forEach((n, index) => {
				const angle = -Math.PI / 2 + (index * Math.PI * 2) / surrounding.length;
				n.x = width / 2 + Math.cos(angle) * localRadius;
				n.y = height / 2 + Math.sin(angle) * localRadius;
				n.vx = 0;
				n.vy = 0;
			});
		}

		// Preserve every node already on screen. Introduce linked nodes close to a
		// retained neighbour; truly disconnected additions start on a bounded,
		// deterministic ring rather than at the center where charge ejects them.
		if (!firstDraw) {
			const neighbours = new Map<string, string[]>(
				data.nodes.map((n) => [n.id, []]),
			);
			for (const edge of data.edges) {
				neighbours.get(edge.source)?.push(edge.target);
				neighbours.get(edge.target)?.push(edge.source);
			}
			for (const n of nodes) {
				const saved = positions.get(n.id);
				if (saved) {
					n.x = saved.x;
					n.y = saved.y;
					// Hold the old local layout steady while additions find their place.
					n.fx = n.x;
					n.fy = n.y;
					autoPins.set(n.id, saved);
				} else {
					const known = (neighbours.get(n.id) ?? [])
						.map((id) => positions.get(id))
						.filter((p): p is { x: number; y: number } => p !== undefined);
					const angle = (hashId(n.id) / 0xffffffff) * Math.PI * 2;
					if (known.length > 0) {
						n.x =
							known.reduce((sum, p) => sum + p.x, 0) / known.length +
							Math.cos(angle) * NEW_NODE_OFFSET;
						n.y =
							known.reduce((sum, p) => sum + p.y, 0) / known.length +
							Math.sin(angle) * NEW_NODE_OFFSET;
					} else {
						n.x = width / 2 + Math.cos(angle) * ringRadius;
						n.y = height / 2 + Math.sin(angle) * ringRadius;
						if (n.degree === 0) {
							// An orphan has no structural force to determine a better spot.
							// Keep its stable seeded position instead of letting charge fire
							// it through (or beyond) the graph during the transition.
							n.fx = n.x;
							n.fy = n.y;
							autoPins.set(n.id, { x: n.x, y: n.y });
						}
					}
				}
				// Scope changes should carry position, not momentum.
				n.vx = 0;
				n.vy = 0;
			}
		}

		// SVG scaffold
		// --------------------
		const svg = select(container)
			.append("svg")
			.attr("width", "100%")
			.attr("height", "100%")
			.attr("viewBox", `0 0 ${width} ${height}`);

		// Arrowhead marker. `context-stroke` makes the head inherit each edge's
		// stroke, so hover recoloring carries through to the arrow too.
		const markerId = `graph-arrow-${uid}`;
		svg
			.append("defs")
			.append("marker")
			.attr("id", markerId)
			.attr("viewBox", "0 -5 10 10")
			.attr("refX", 9)
			.attr("refY", 0)
			.attr("markerWidth", 6)
			.attr("markerHeight", 6)
			.attr("orient", "auto")
			.append("path")
			.attr("d", "M0,-4L9,0L0,4")
			.attr("fill", "context-stroke");

		// Everything pannable/zoomable lives in this group.
		const root = svg.append("g");

		const link = root
			.append("g")
			.attr("fill", "none")
			.attr("stroke", "currentColor")
			.attr("stroke-opacity", 0.25)
			.selectAll<SVGPathElement, SimEdge>("path")
			.data(edges)
			.join("path")
			.attr("stroke-width", 1)
			.attr("marker-end", data.directed ? `url(#${markerId})` : null);

		const node = root
			.append("g")
			.attr("stroke", "var(--graph-node-stroke, #fff)")
			.selectAll<SVGCircleElement, SimNode>("circle")
			.data(nodes)
			.join("circle")
			.attr("data-node-id", (d) => d.id)
			.attr("r", nodeRadius)
			.attr("fill", color)
			.attr("stroke-width", (d) => (d.id === focusId ? 2 : 1))
			.style("cursor", "pointer");

		const label = root
			.append("g")
			.attr("font-family", "system-ui, sans-serif")
			.attr("font-size", LABEL_FONT_SIZE)
			.attr("fill", "currentColor")
			.attr("pointer-events", "none")
			.selectAll<SVGTextElement, SimNode>("text")
			.data(nodes)
			.join("text")
			.text((d) => d.title)
			.attr("font-weight", (d) => (d.id === focusId ? 600 : 400))
			.attr("dx", (d) => nodeRadius(d) + 3)
			.attr("dy", 4);

		// The arced/straight path for a directed edge, trimmed so its arrowhead
		// lands just outside the target node.
		function edgePath(e: SimEdge): string {
			const sx = e.source.x,
				sy = e.source.y;
			const tx = e.target.x,
				ty = e.target.y;
			const dx = tx - sx,
				dy = ty - sy;
			const dist = Math.hypot(dx, dy) || 1;
			const ux = dx / dist,
				uy = dy / dist;
			const endGap = nodeRadius(e.target) + ARROW_PAD;
			const ex = tx - ux * endGap,
				ey = ty - uy * endGap;
			if (data.directed && e.hasTwin) {
				// Bow to a side chosen by id order, so the twin bows the other way.
				const sign = e.source.id < e.target.id ? 1 : -1;
				const cx = (sx + tx) / 2 - uy * CURVE * sign;
				const cy = (sy + ty) / 2 + ux * CURVE * sign;
				return `M${sx},${sy} Q${cx},${cy} ${ex},${ey}`;
			}
			return `M${sx},${sy} L${ex},${ey}`;
		}

		// Simulation
		// --------------------
		sim = forceSimulation(nodes)
			.velocityDecay(VELOCITY_DECAY)
			.alpha(firstDraw ? 1 : REDRAW_ALPHA)
			.force(
				"link",
				forceLink<SimNode, SimEdge>(edges)
					.id((d) => d.id)
					.distance(LINK_DISTANCE),
			)
			.force(
				"charge",
				forceManyBody<SimNode>().strength((n) =>
					n.degree === 0 ? ORPHAN_CHARGE : CHARGE,
				),
			)
			.force("center", forceCenter(width / 2, height / 2))
			.force(
				"x",
				forceX<SimNode>(width / 2).strength((n) =>
					n.degree === 0 ? 0 : CENTER_PULL,
				),
			)
			.force(
				"y",
				forceY<SimNode>(height / 2).strength((n) =>
					n.degree === 0 ? 0 : CENTER_PULL,
				),
			)
			.force(
				"orphan-ring",
				forceRadial<SimNode>(ringRadius, width / 2, height / 2).strength((n) =>
					n.degree === 0 ? ORPHAN_RING_PULL : 0,
				),
			)
			.force(
				"collide",
				forceCollide<SimNode>().radius((d) => nodeRadius(d) + 4),
			);
		firstDraw = false;

		const renderPositions = (): void => {
			link.attr("d", edgePath);
			node.attr("cx", (d) => d.x).attr("cy", (d) => d.y);
			label.attr("x", (d) => d.x).attr("y", (d) => d.y);
		};

		// Do the expensive-looking part before the graph is painted. Letting the
		// simulation run on its timer makes every page open with nodes visibly
		// flying into place; synchronous ticks give us the same settled layout as
		// the first rendered frame. The simulation remains available for explicit
		// interactions such as dragging and Reset.
		sim.stop();
		const settleTicks = Math.ceil(
			Math.log(sim.alphaMin()) / Math.log(1 - sim.alphaDecay()),
		);
		sim.tick(settleTicks);
		renderPositions();
		sim.on("tick", renderPositions);

		// Interaction
		// --------------------
		node.call(
			d3drag<SVGCircleElement, SimNode>()
				.on("start", (event, d) => {
					if (!event.active) sim?.alphaTarget(0.3).restart();
					d.fx = d.x;
					d.fy = d.y;
				})
				.on("drag", (event, d) => {
					d.fx = event.x;
					d.fy = event.y;
				})
				.on("end", (event, d) => {
					if (!event.active) sim?.alphaTarget(0);
					d.fx = null;
					d.fy = null;
				}),
		);

		node.on("click", (_event, d) => {
			window.location.href = d.href;
		});

		// Hover: spotlight the node, its neighbors, and the edges between them.
		node
			.on("mouseenter", (_event, d) => {
				const near = adj.get(d.id)!;
				const lit = (n: SimNode) => n.id === d.id || near.has(n.id);
				node.attr("opacity", (n) => (lit(n) ? 1 : 0.15));
				label.attr("opacity", (n) => (lit(n) ? 1 : 0.15));
				link
					.attr("stroke-opacity", (e) =>
						e.source.id === d.id || e.target.id === d.id ? 0.85 : 0.05,
					)
					.attr("stroke", (e) =>
						e.source.id === d.id || e.target.id === d.id
							? "var(--graph-link-hover, #e0a800)"
							: "currentColor",
					);
			})
			.on("mouseleave", () => {
				node.attr("opacity", 1);
				label.attr("opacity", labelOpacityForZoom(currentScale));
				link.attr("stroke-opacity", 0.25).attr("stroke", "currentColor");
			});

		// Zoom + pan. Labels fade out when zoomed far enough that they'd overlap.
		let currentScale = 1;
		const labelOpacityForZoom = (k: number) =>
			k < LABEL_ZOOM_THRESHOLD ? 0 : 1;

		const zoomBehavior = d3zoom<SVGSVGElement, unknown>()
			.scaleExtent([0.2, 6])
			.on("zoom", (event) => {
				currentScale = event.transform.k;
				root.attr("transform", event.transform.toString());
				// Keep label typography at a stable screen size. The graph may zoom a
				// little to fit its stage, but its text should still belong to the
				// surrounding page rather than looking optically enlarged.
				label
					.attr("font-size", LABEL_FONT_SIZE / currentScale)
					.attr("dx", (d) => (nodeRadius(d) + 3) / currentScale)
					.attr("dy", 4 / currentScale)
					.attr("opacity", labelOpacityForZoom(currentScale));
			});
		svg.call(zoomBehavior);

		// Frame the whole (visible) graph once the layout settles.
		function fitToContent(animate = true): void {
			if (nodes.length === 0) return;
			let minX = Infinity,
				minY = Infinity,
				maxX = -Infinity,
				maxY = -Infinity;
			for (const n of nodes) {
				const r = nodeRadius(n);
				minX = Math.min(minX, n.x - r);
				minY = Math.min(minY, n.y - r);
				maxX = Math.max(maxX, n.x + r);
				maxY = Math.max(maxY, n.y + r);
			}
			const boxW = maxX - minX || 1;
			const boxH = maxY - minY || 1;
			const fit = Math.min(
				(width - FIT_MARGIN * 2) / boxW,
				(height - FIT_MARGIN * 2) / boxH,
				scope === "local" ? LOCAL_FIT_SCALE : GLOBAL_FIT_SCALE,
			);
			const tx = width / 2 - (fit * (minX + maxX)) / 2;
			const ty = height / 2 - (fit * (minY + maxY)) / 2;
			const transform = zoomIdentity.translate(tx, ty).scale(fit);
			if (animate) {
				svg.transition().duration(400).call(zoomBehavior.transform, transform);
			} else {
				svg.call(zoomBehavior.transform, transform);
			}
		}
		const releaseAutoPins = (): void => {
			// Release only anchors we still own. A pointer drag may have changed a
			// node's fixed coordinates in the meantime; never undo the user's move.
			for (const n of nodes) {
				const pin = autoPins.get(n.id);
				if (pin && n.fx === pin.x && n.fy === pin.y) {
					n.fx = null;
					n.fy = null;
				}
			}
		};
		releaseAutoPins();
		fitToContent(false);
		sim.on("end", () => {
			releaseAutoPins();
			fitToContent();
		});

		// Undo manual drags and re-frame: release fixed positions, reheat gently so
		// dragged nodes rejoin the layout, and refit once it settles.
		resetView = (): void => {
			for (const n of nodes) {
				n.fx = null;
				n.fy = null;
			}
			fitToContent();
			sim?.alpha(REDRAW_ALPHA).restart();
		};

		label.attr("opacity", labelOpacityForZoom(currentScale));
	}

	draw();

	return {
		getScope: () => scope,
		setScope(next: Scope): void {
			if (next === scope) return;
			scope = focusId ? next : "global";
			draw();
		},
		reset(): void {
			resetView();
		},
		destroy(): void {
			sim?.stop();
			sim = null;
			container.replaceChildren();
		},
	};
}
