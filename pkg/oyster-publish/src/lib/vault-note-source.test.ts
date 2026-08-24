import { expect, test } from "vitest";
import { parseNoteSource, stripFrontmatter } from "./vault-note-source.ts";

test("strips a leading YAML frontmatter document", () => {
	expect(stripFrontmatter("---\ntitle: Note\n---\n# Body\n")).toBe("# Body\n");
	expect(stripFrontmatter("---\r\ntitle: Note\r\n---\r\nBody\r\n")).toBe(
		"Body\r\n",
	);
});

test("parses publication metadata with YAML semantics", () => {
	expect(
		parseNoteSource("---\npublish: true\ntags: [one, two]\n---\nBody"),
	).toEqual({
		body: "Body",
		data: { publish: true, tags: ["one", "two"] },
	});
});

test("leaves ordinary thematic breaks and unterminated frontmatter untouched", () => {
	expect(stripFrontmatter("Text\n---\nMore")).toBe("Text\n---\nMore");
	expect(stripFrontmatter("---\ntitle: nope")).toBe("---\ntitle: nope");
});
