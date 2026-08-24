import GithubSlugger from "github-slugger";
import { toString as mdToString } from "mdast-util-to-string";

type Node = {
	type: string;
	depth?: number;
	identifier?: string;
	url?: string;
	data?: { hProperties?: Record<string, any>; [key: string]: any };
	children?: Node[];
	[key: string]: any;
};

export interface ContentSlice {
	nodes: Node[];
	label: string | null;
}

function clone<T>(value: T): T {
	return structuredClone(value);
}

function explicitId(node: Node): string | null {
	const id = node.data?.hProperties?.id;
	return typeof id === "string" ? id : null;
}

function findNode(
	nodes: Node[],
	predicate: (node: Node) => boolean,
): Node | null {
	for (const node of nodes) {
		if (predicate(node)) return node;
		const nested = findNode(node.children ?? [], predicate);
		if (nested) return nested;
	}
	return null;
}

/** Select a whole note, heading section, block id, or explicit attribute id. */
export function sliceContent(
	tree: Node,
	fragment: string | null,
): ContentSlice | null {
	const children = tree.children ?? [];
	if (!fragment) return { nodes: clone(children), label: null };

	if (fragment.startsWith("^")) {
		const id = fragment.slice(1).toLowerCase();
		const node = findNode(
			children,
			(candidate) => explicitId(candidate)?.toLowerCase() === id,
		);
		return node ? { nodes: [clone(node)], label: fragment } : null;
	}

	const wanted = fragment.split("#").at(-1)?.trim().toLowerCase();
	const slugger = new GithubSlugger();
	for (let index = 0; index < children.length; index += 1) {
		const node = children[index];
		if (node.type !== "heading") continue;
		const text = mdToString(node);
		const slug = slugger.slug(text);
		const matchesHeading =
			text.trim().toLowerCase() === wanted || slug === wanted;
		const matchesAttribute = explicitId(node)?.toLowerCase() === wanted;
		if (!matchesHeading && !matchesAttribute) continue;

		let end = index + 1;
		while (end < children.length) {
			const candidate = children[end];
			if (candidate.type === "heading" && candidate.depth! <= node.depth!)
				break;
			end += 1;
		}
		return { nodes: clone(children.slice(index, end)), label: text };
	}

	const anchored = findNode(
		children,
		(node) => explicitId(node)?.toLowerCase() === wanted,
	);
	return anchored ? { nodes: [clone(anchored)], label: fragment } : null;
}

function walk(nodes: Node[], visit: (node: Node) => void): void {
	for (const node of nodes) {
		visit(node);
		walk(node.children ?? [], visit);
	}
}

/** Make an embedded tree's headings, explicit anchors, and footnotes page-local. */
export function isolateEmbeddedContent(
	nodes: Node[],
	prefix: string,
	sourceSlug: string,
	minimumHeadingDepth = 2,
): Node[] {
	const safePrefix = prefix.replace(/[^a-zA-Z0-9_-]/g, "-");
	const slugger = new GithubSlugger();
	let shallowest = 6;
	walk(nodes, (node) => {
		if (node.type === "heading")
			shallowest = Math.min(shallowest, node.depth ?? 6);
	});
	const depthShift = Math.max(0, minimumHeadingDepth - shallowest);

	walk(nodes, (node) => {
		if (node.type === "heading") {
			const original = explicitId(node) ?? slugger.slug(mdToString(node));
			node.depth = Math.min(6, (node.depth ?? 1) + depthShift);
			node.data = {
				...(node.data ?? {}),
				hProperties: {
					...(node.data?.hProperties ?? {}),
					id: `${safePrefix}-${original}`,
				},
			};
		} else {
			const id = explicitId(node);
			if (id && node.data?.hProperties) {
				node.data.hProperties.id = `${safePrefix}-${id}`;
			}
		}

		if (
			(node.type === "footnoteDefinition" ||
				node.type === "footnoteReference") &&
			node.identifier
		) {
			node.identifier = `${safePrefix}-${node.identifier}`;
			if (typeof node.label === "string")
				node.label = `${safePrefix}-${node.label}`;
		}

		if (typeof node.url === "string") {
			if (node.url.startsWith("#"))
				node.url = `#${safePrefix}-${node.url.slice(1)}`;
			else if (node.url.startsWith(`${sourceSlug}#`)) {
				node.url = `#${safePrefix}-${node.url.slice(sourceSlug.length + 1)}`;
			}
		}
	});
	return nodes;
}
