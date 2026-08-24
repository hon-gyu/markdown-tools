import fs from "node:fs";
import path from "node:path";
import { load as parseYaml } from "js-yaml";
import type { NoteFile } from "./wikilink.ts";

export interface ParsedNoteSource {
	body: string;
	data: Record<string, unknown>;
}

export function parseNoteSource(source: string): ParsedNoteSource {
	const lines = source.split(/(?<=\n)/);
	if (lines[0]?.replace(/\r?\n$/, "") !== "---") {
		return { body: source, data: {} };
	}
	for (let index = 1; index < lines.length; index += 1) {
		if (lines[index].replace(/\r?\n$/, "") === "---") {
			const parsed = parseYaml(lines.slice(1, index).join(""));
			return {
				body: lines.slice(index + 1).join(""),
				data:
					parsed && typeof parsed === "object"
						? (parsed as Record<string, unknown>)
						: {},
			};
		}
	}
	return { body: source, data: {} };
}

export function stripFrontmatter(source: string): string {
	return parseNoteSource(source).body;
}

export function readVaultNoteSources(
	vaultDir: string,
	files: NoteFile[],
	options: { publishedOnly?: boolean } = {},
): Map<string, string> {
	const sources = new Map<string, string>();
	for (const file of files) {
		const parsed = parseNoteSource(
			fs.readFileSync(path.join(vaultDir, file.path), "utf8"),
		);
		if (parsed.data.publish === false) continue;
		if (options.publishedOnly && parsed.data.publish !== true) continue;
		sources.set(file.path, parsed.body);
	}
	return sources;
}
