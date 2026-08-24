import { nameSegments } from "./display-name";
import type { VaultManifest } from "./vault-manifest.ts";

// Turns the flat list of notes into a nested tree, where each directory segment
// is a taxonomy level and the path is the URL. This is the same idea as the
// Next `lib/tree.ts`, but the filesystem walk + frontmatter parsing is already
// done for us by the content collection — we only reshape flat -> nested.

export interface TreeNode {
	name: string; // path segment, e.g. "async"
	urlPath: string; // route, e.g. "/rust/async"
	title: string; // frontmatter title, else the name as it is on disk
	tags: string[];
	hasPage: boolean; // renders a note itself, or just a grouping folder?
	children: TreeNode[];
	navOrder?: number;
	hidden: boolean;
}

// == Helpers =================================================================

// A note's id -> its URL slug. `index` files stand in for their directory.
export function idToSlug(id: string): string {
	if (id === "index") return "";
	return id.replace(/\/index$/, "");
}

// Display names come from lib/display-name.ts: frontmatter `title:`, else the
// name on disk, never prettified. Nothing here transforms them — the nav, the
// graph, search hits and the browser tab must all call a note the same thing.

function sortRec(node: TreeNode): void {
	node.children.sort((a, b) => {
		const aOrder = a.navOrder ?? Number.POSITIVE_INFINITY;
		const bOrder = b.navOrder ?? Number.POSITIVE_INFINITY;
		if (aOrder !== bOrder) return aOrder - bOrder;
		if (a.hasPage !== b.hasPage) return a.hasPage ? -1 : 1;
		return a.title.localeCompare(b.title);
	});
	node.children.forEach(sortRec);
}

// == Public API ==============================================================

export function treeFromIndex(index: VaultManifest): TreeNode[] {
	const root: TreeNode = {
		name: "",
		urlPath: "/",
		title: "Home",
		tags: [],
		hasPage: false,
		children: [],
		hidden: false,
	};

	for (const note of index.notes) {
		const slug = note.originalSlug.replace(/^\//, "");

		// The vault's index.md is the site root itself.
		if (slug === "") {
			root.hasPage = true;
			root.title = note.title;
			root.tags = note.tags;
			root.navOrder = note.navOrder;
			root.hidden = note.navHidden;
			continue;
		}

		const segments = slug.split("/");
		// The same segments as the author wrote them, for display. Falls back to the
		// slug segment if a path is somehow unavailable (no `filePath`).
		const names = nameSegments(note.path);
		let cursor = root;
		let acc = "";
		segments.forEach((seg, i) => {
			acc += `/${seg}`;
			let child = cursor.children.find((c) => c.name === seg);
			if (!child) {
				child = {
					name: seg,
					urlPath: acc,
					title: names[i] ?? seg,
					tags: [],
					hasPage: false,
					children: [],
					hidden: false,
				};
				cursor.children.push(child);
			}
			// The last segment is the note itself; earlier ones are ancestor folders
			// (which may or may not have their own index note).
			if (i === segments.length - 1) {
				child.urlPath = note.slug;
				child.hasPage = !note.navHidden;
				child.title = note.title;
				child.tags = note.tags;
				child.navOrder = note.navOrder;
				child.hidden =
					note.navHidden && /(?:^|\/)index\.mdx?$/i.test(note.path);
			}
			cursor = child;
		});
	}

	sortRec(root);
	const visible = (nodes: TreeNode[]): TreeNode[] =>
		nodes
			.filter((node) => !node.hidden)
			.map((node) => ({ ...node, children: visible(node.children) }))
			.filter((node) => node.hasPage || node.children.length > 0);
	return visible(root.children);
}

export async function getTree(): Promise<TreeNode[]> {
	const { getVaultIndex } = await import("./note-index.ts");
	return treeFromIndex(await getVaultIndex());
}
