import { expect, test } from "vitest";
import {
	initiallyPublished,
	type PublicationRules,
} from "./publication-selection.ts";

const rules: PublicationRules = {
	includeFolders: ["blog"],
	excludeFolders: ["blog/drafts"],
	linkedNotes: true,
};

test("explicit note metadata overrides folder selection", () => {
	expect(initiallyPublished("blog/post.md", undefined, rules, false)).toBe(
		true,
	);
	expect(initiallyPublished("blog/drafts/x.md", undefined, rules, false)).toBe(
		false,
	);
	expect(initiallyPublished("blog/post.md", false, rules, false)).toBe(false);
	expect(initiallyPublished("private/launch.md", true, rules, false)).toBe(
		true,
	);
});

test("published-only remains strict regardless of folder rules", () => {
	expect(initiallyPublished("blog/post.md", undefined, rules, true)).toBe(
		false,
	);
	expect(initiallyPublished("private/launch.md", true, rules, true)).toBe(true);
});
