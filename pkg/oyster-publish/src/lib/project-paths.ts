import path from "node:path";

// The publishing CLI supplies an absolute vault path. Direct Astro commands
// retain their original behavior and use the repository's local vault.
export const vaultDir = path.resolve(process.env.OYSTER_VAULT ?? "./vault");
export const outputDir = path.resolve(process.env.OYSTER_OUT_DIR ?? "./dist");

// A collection entry's vault-relative path, e.g. "Modern AI/Transformers.md".
// The entry's `id` is slugified and collapses index files, so it can't be turned
// back into a path — and it has lost the note's real *name*. `filePath` is the
// only place the name as the author typed it survives.
export function notePath(entry: { filePath?: string }): string {
	return entry.filePath
		? path.relative(vaultDir, path.resolve(entry.filePath))
		: "";
}
