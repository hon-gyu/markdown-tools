import { expect, test } from "vitest";
import { buildOystermarkIndex, parseToMdast } from "./index.ts";

test("cached parser results remain isolated mutable trees", () => {
	const first: any = parseToMdast("# Cached\n\nBody");
	first.children[0].children[0].value = "Changed";

	const second: any = parseToMdast("# Cached\n\nBody");
	expect(second.children[0].children[0].value).toBe("Cached");
	expect(second).not.toBe(first);
});

test("indexes and resolves a complete vault", () => {
	const index = buildOystermarkIndex(
		[
			{ path: "a.md", content: "[[b#Section]]" },
			{ path: "b.md", content: "# Section" },
		],
		[],
	);
	expect(index.notes[0].links[0].resolution).toMatchObject({
		kind: "anchor",
		path: "b.md",
	});
});
