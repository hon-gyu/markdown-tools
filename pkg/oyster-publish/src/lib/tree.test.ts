import { expect, test } from "vitest";
import { treeFromIndex } from "./tree.ts";
import { buildVaultManifest } from "./vault-manifest.ts";

test("navigation uses filesystem hierarchy but canonical page URLs", () => {
	const index = buildVaultManifest([
		{
			path: "folder/index.md",
			body: "",
			data: { title: "Folder", permalink: "/topics" },
		},
		{ path: "folder/child.md", body: "", data: { title: "Child" } },
	]);
	const [folder] = treeFromIndex(index);
	expect(folder).toMatchObject({
		name: "folder",
		urlPath: "/topics",
		title: "Folder",
	});
	expect(folder.children[0]).toMatchObject({
		name: "child",
		urlPath: "/folder/child",
	});
});

test("a hidden folder removes its visible descendants from navigation only", () => {
	const index = buildVaultManifest([
		{ path: "private/index.md", body: "", data: { navHidden: true } },
		{ path: "private/visible.md", body: "", data: {} },
	]);
	expect(treeFromIndex(index)).toEqual([]);
	expect(index.searchDocs.map((doc) => doc.href)).toContain("/private/visible");
	expect(index.files).toHaveLength(2);
});

test("duplicate sibling navigation order is rejected", () => {
	expect(() =>
		buildVaultManifest([
			{ path: "a.md", body: "", data: { navOrder: 1 } },
			{ path: "b.md", body: "", data: { navOrder: 1 } },
		]),
	).toThrow(/duplicate navOrder/i);
});
