export interface TocHeading {
	depth: number;
	slug: string;
	text: string;
}

export interface TocNode extends TocHeading {
	children: TocNode[];
}

export function buildTocTree(headings: TocHeading[]): TocNode[] {
	const roots: TocNode[] = [];
	const stack: TocNode[] = [];
	for (const heading of headings.filter(
		(item) => item.depth >= 2 && item.depth <= 6,
	)) {
		const node = { ...heading, children: [] };
		let previous = stack.at(-1);
		while (previous && previous.depth >= node.depth) {
			stack.pop();
			previous = stack.at(-1);
		}
		const parent = stack.at(-1);
		(parent ? parent.children : roots).push(node);
		stack.push(node);
	}
	return roots;
}
