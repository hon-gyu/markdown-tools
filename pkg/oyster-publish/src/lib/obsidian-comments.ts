type Node = { type?: string; value?: string; children?: Node[] };

/** Remove Obsidian %% comments from parsed prose without touching code nodes. */
export function stripObsidianComments(tree: Node): void {
	let hidden = false;
	const walk = (node: Node) => {
		if (node.type === "code" || node.type === "inlineCode") return;
		if (node.type === "text" && typeof node.value === "string") {
			let source = node.value;
			let visible = "";
			while (source) {
				const marker = source.indexOf("%%");
				if (marker === -1) {
					if (!hidden) visible += source;
					break;
				}
				if (!hidden) visible += source.slice(0, marker);
				hidden = !hidden;
				source = source.slice(marker + 2);
			}
			node.value = visible;
			return;
		}
		for (const child of node.children ?? []) walk(child);
	};
	walk(tree);
}
