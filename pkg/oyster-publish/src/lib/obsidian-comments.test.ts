import { expect, test } from "vitest";
import { stripObsidianComments } from "./obsidian-comments.ts";
import { parseToMdast } from "./oystermark/index.ts";

test("removes inline and cross-node comments but preserves code", () => {
	const tree: any = parseToMdast(
		"Before %% hidden *and emphasized* %% after.\n\n`%% code %%`",
	);
	stripObsidianComments(tree);
	expect(JSON.stringify(tree)).not.toContain("hidden");
	expect(JSON.stringify(tree)).not.toContain("emphasized");
	expect(JSON.stringify(tree)).toContain("after");
	expect(JSON.stringify(tree)).toContain("%% code %%");
});
