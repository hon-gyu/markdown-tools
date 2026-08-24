import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { z } from "astro/zod";
import { vaultDir } from "./lib/project-paths";
import { publishedGlob } from "./lib/published-glob";
import { site } from "./lib/site-config";
import { pathToId } from "./lib/wikilink";

// The "vault": a plain directory of markdown notes. The glob loader is Astro's
// built-in registry — it hands us every note with parsed, schema-validated
// frontmatter, so we never walk the filesystem by hand.
//
// An entry's `id` comes from `pathToId` (see published-glob.ts), which drops the
// extension, slugifies every path segment, and lets an index file stand in for
// its directory. The id *is* the route, so a note's real filename need not be
// URL-shaped:
//   index.md                        -> "index"      (served at "/")
//   rust/async.md                   -> "rust/async"
//   rust/index.md                   -> "rust"
//   Field Notes/Soil pH (basics).md -> "field-notes/soil-ph-basics"
//
// A `slug:` in frontmatter is ignored, unlike Astro's default: the path is the
// single source of truth for a note's identity, so that the hrefs we link with
// (wikilinks, graph nodes, search hits) cannot drift from the routes we serve.
const noteSchema = z.object({
	title: z.string().optional(),
	tags: z.array(z.string()).default([]),
	// Tri-state is intentional: false is always private, true is selected by
	// --published-only, and absence remains visible in the normal all-notes mode.
	publish: z.boolean().optional(),
	date: z.coerce.date().optional(),
	updated: z.coerce.date().optional(),
	author: z.string().min(1).optional(),
	status: z.string().min(1).optional(),
	permalink: z.string().optional(),
	aliases: z.array(z.string()).default([]),
	navOrder: z.number().optional(),
	navHidden: z.boolean().default(false),
});

const notes = defineCollection({
	loader: publishedGlob(
		{ pattern: "**/*.{md,mdx}", base: vaultDir },
		site.publication,
	),
	schema: noteSchema,
});

// The manifest needs knowledge of unpublished notes so it can distinguish a
// private target from a typo. This collection is never used to generate pages.
const vaultNotes = defineCollection({
	loader: glob({
		pattern: "**/*.{md,mdx}",
		base: vaultDir,
		generateId: ({ entry }) => pathToId(entry),
	}),
	schema: noteSchema,
});

export const collections = { notes, vaultNotes };
