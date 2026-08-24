// How a note is *named* on screen — the nav, the graph, search hits, the browser
// tab. Pure path/string work, so it unit-tests without Astro.
//
// The rule, vault-wide: frontmatter `title:` if present, else the file or folder
// name exactly as it is on disk. Nothing is prettified. A slug has already lost
// its capitals ("Modern AI" -> "modern-ai") and no guess brings them back, so
// names are always read from the real path; see tree.ts.

const NOTE_EXT = /\.(md|mdx)$/;

// The path segments as the author wrote them, with an index file collapsed into
// its directory ("Recipe/index.md" -> ["Recipe"]), matching how an index note
// stands in for its folder everywhere else. The vault root's own "index.md" has
// no directory to collapse into and stays ["index"].
export function nameSegments(relPath: string): string[] {
	const bare = relPath.replace(NOTE_EXT, "");
	if (bare === "") return [];
	const segments = bare.split("/");
	if (segments.length > 1 && segments.at(-1) === "index") segments.pop();
	return segments;
}

// A note's own display name.
export function displayName(
	relPath: string,
	frontmatterTitle?: string,
): string {
	return frontmatterTitle ?? nameSegments(relPath).at(-1) ?? "";
}

// The first *character* of a segment — by code point, so a non-Latin or emoji
// name isn't sliced in half mid-surrogate ("笔记" -> "笔", not a broken half).
// Taken verbatim, not upper-cased: the whole point of this module is to show
// what the author typed, and a lowercase folder is a lowercase folder.
function initial(segment: string): string {
	return Array.from(segment)[0] ?? "";
}

export interface TabTitleOptions {
	// Abbreviate each ancestor directory to its first character.
	ancestorInitials: boolean;
}

// The name for the browser tab. Tabs are narrow and a deep note's own name is
// often ambiguous on its own ("Note 1"), so `ancestorInitials` prefixes a
// squeezed-down path: enough to place the note, cheap in pixels.
//
//   "Pasd/Tasd/Note 1.md"  -> "P/T/Note 1"
//   "Modern AI.md"         -> "Modern AI"   (no ancestors: unchanged)
//
// The note's own name is never abbreviated — only its ancestors. A frontmatter
// `title:` still wins for that final part.
export function tabTitle(
	relPath: string,
	frontmatterTitle: string | undefined,
	opts: TabTitleOptions,
): string {
	const name = displayName(relPath, frontmatterTitle);
	if (!opts.ancestorInitials) return name;

	const ancestors = nameSegments(relPath).slice(0, -1);
	if (ancestors.length === 0) return name;
	return [...ancestors.map(initial), name].join("/");
}
