import { expect, test } from "vitest";
import { buildTocTree } from "./toc-tree.ts";

test("nests H2-H6 headings by their nearest shallower predecessor", () => {
	const tree = buildTocTree([
		{ depth: 1, slug: "title", text: "Title" },
		{ depth: 2, slug: "a", text: "A" },
		{ depth: 4, slug: "deep", text: "Deep" },
		{ depth: 3, slug: "middle", text: "Middle" },
		{ depth: 6, slug: "lowest", text: "Lowest" },
		{ depth: 2, slug: "b", text: "B" },
	]);
	expect(tree.map((node) => node.slug)).toEqual(["a", "b"]);
	expect(tree[0].children.map((node) => node.slug)).toEqual(["deep", "middle"]);
	expect(tree[0].children[1].children[0].slug).toBe("lowest");
});
