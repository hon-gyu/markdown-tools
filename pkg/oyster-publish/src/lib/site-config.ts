// Per-site settings — the site's name and favicon — which belong to the *vault*,
// not to this repo. The repo is the engine; a vault is the input (`-v`), and one
// installation publishes many vaults. So the config travels with the notes:
//
//   <vault>/.oyster/config.json    { "title": "My Blog" }
//   <vault>/.oyster/public/        served at the site root (favicon, assets)
//
// A dotfolder keeps it out of Obsidian's file explorer and out of the note tree
// (the collection glob only matches *.md/*.mdx anyway).
//
// Precedence, highest first: CLI flag (via OYSTER_SITE_*) > config.json > a
// derived default. Resolution is sync and happens at module load, because both
// `astro.config.mjs` and `Base.astro` need it before anything renders.

import fs from "node:fs";
import path from "node:path";
import { z } from "astro/zod";
import { vaultDir } from "./project-paths.ts";

const oysterDir = path.join(vaultDir, ".oyster");
const configPath = path.join(oysterDir, "config.json");

// Astro copies `publicDir` to the site root, in dev and in the build alike. Point
// it at the vault's own asset folder when there is one, so a favicon the user
// drops there is served with no copying on our part; otherwise fall back to the
// repo's `public/`, which ships a default icon.
const vaultPublicDir = path.join(oysterDir, "public");
export const publicDir = fs.existsSync(vaultPublicDir)
	? vaultPublicDir
	: path.resolve("./public");

// `strict` so a typo'd key ("titel") fails the build instead of being silently
// dropped — an unknown key here can only ever be a mistake.
const schema = z
	.object({
		title: z.string().min(1).optional(),
		favicon: z.string().min(1).optional(),
		ancestorInitials: z.boolean().optional(),
		publication: z
			.object({
				includeFolders: z.array(z.string()).default([]),
				excludeFolders: z.array(z.string()).default([]),
				linkedNotes: z.boolean().default(false),
			})
			.optional(),
	})
	.strict();

function readConfigFile(): z.infer<typeof schema> {
	if (!fs.existsSync(configPath)) return {};

	let raw: unknown;
	try {
		raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
	} catch (err) {
		throw new Error(
			`${configPath}: not valid JSON — ${(err as Error).message}`,
		);
	}

	const parsed = schema.safeParse(raw);
	if (!parsed.success) {
		const issues = parsed.error.issues
			.map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`)
			.join("; ");
		throw new Error(`${configPath}: ${issues}`);
	}
	return parsed.data;
}

// A favicon the user simply dropped in the public folder, no config needed.
// Ordered by preference: SVG scales, ICO is the legacy fallback.
function detectFavicon(): string | null {
	for (const name of ["favicon.svg", "favicon.png", "favicon.ico"]) {
		if (fs.existsSync(path.join(publicDir, name))) return `/${name}`;
	}
	return null;
}

export interface SiteConfig {
	// Shown in the sidebar and appended to every page's <title>.
	title: string;
	// A URL path served from `publicDir` ("/favicon.svg"), or null to emit no icon
	// link at all. Not a filesystem path: the file reaches the site by living in
	// the public folder, so this only names where it lands.
	favicon: string | null;
	// Abbreviate a note's ancestor folders to their initials in the browser tab:
	// "Pasd/Tasd/Note 1" shows as "P/T/Note 1". On by default; see tabTitle() in
	// display-name.ts. Affects the tab only — the nav and graph still show names
	// in full, where there is room for them.
	ancestorInitials: boolean;
	publication: {
		includeFolders: string[];
		excludeFolders: string[];
		linkedNotes: boolean;
	};
}

const file = readConfigFile();

// On unless explicitly switched off. The env var is tri-state rather than
// truthy: "0" is a real "off" from `--no-ancestor-initials`, and an *unset* var
// must fall through to config.json instead of overriding it — which is why this
// can't be the `X || y` shape the other settings use (`"0" || true` is `true`).
function resolveAncestorInitials(): boolean {
	const env = process.env.OYSTER_SITE_ANCESTOR_INITIALS;
	if (env === "0") return false;
	if (env === "1") return true;
	return file.ancestorInitials ?? true;
}

export const site: SiteConfig = {
	// Defaulting to the vault's folder name beats defaulting to the tool's own
	// name: an unconfigured vault at ~/notes/myblog publishes as "myblog".
	title: process.env.OYSTER_SITE_TITLE || file.title || path.basename(vaultDir),
	favicon: process.env.OYSTER_SITE_FAVICON || file.favicon || detectFavicon(),
	ancestorInitials: resolveAncestorInitials(),
	publication: file.publication ?? {
		includeFolders: [],
		excludeFolders: [],
		linkedNotes: false,
	},
};
