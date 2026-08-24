import { createHash } from "node:crypto";
import { slug as githubSlug } from "github-slugger";
import type { NoteRecord } from "./vault-manifest.ts";

export interface TagGroup {
	label: string;
	slug: string;
	notes: NoteRecord[];
}

function pathOrder(a: NoteRecord, b: NoteRecord): number {
	return a.path.localeCompare(b.path, "en");
}

export function chronologicalNotes(notes: NoteRecord[]): NoteRecord[] {
	return notes
		.filter((note) => note.date)
		.sort((a, b) => b.date?.localeCompare(a.date!) || pathOrder(a, b));
}

export function navigationNotes(notes: NoteRecord[]): NoteRecord[] {
	type NavNode = { note?: NoteRecord; children: Map<string, NavNode> };
	const root: NavNode = { children: new Map() };
	for (const note of notes) {
		const segments =
			note.originalSlug === "/" ? [] : note.originalSlug.slice(1).split("/");
		let cursor = root;
		for (const segment of segments) {
			let child = cursor.children.get(segment);
			if (!child) {
				child = { children: new Map() };
				cursor.children.set(segment, child);
			}
			cursor = child;
		}
		cursor.note = note;
	}
	const ordered: NoteRecord[] = [];
	if (root.note && !root.note.navHidden) ordered.push(root.note);
	const walk = (node: NavNode) => {
		const children = [...node.children.values()].sort((a, b) => {
			const aOrder = a.note?.navOrder ?? Number.POSITIVE_INFINITY;
			const bOrder = b.note?.navOrder ?? Number.POSITIVE_INFINITY;
			const aLabel = a.note?.path ?? [...a.children.keys()][0] ?? "";
			const bLabel = b.note?.path ?? [...b.children.keys()][0] ?? "";
			return (
				(aOrder === bOrder ? 0 : aOrder - bOrder) ||
				aLabel.localeCompare(bLabel, "en")
			);
		});
		for (const child of children) {
			const hiddenFolder =
				child.note?.navHidden && /(?:^|\/)index\.mdx?$/i.test(child.note.path);
			if (hiddenFolder) continue;
			if (child.note && !child.note.navHidden) ordered.push(child.note);
			walk(child);
		}
	};
	walk(root);
	return ordered;
}

export function adjacentNotes(
	notes: NoteRecord[],
	path: string,
): { previous: NoteRecord | null; next: NoteRecord | null } {
	const ordered = navigationNotes(notes);
	const index = ordered.findIndex((note) => note.path === path);
	return {
		previous: index > 0 ? ordered[index - 1] : null,
		next: index >= 0 && index < ordered.length - 1 ? ordered[index + 1] : null,
	};
}

export function tagGroups(notes: NoteRecord[]): TagGroup[] {
	const groups = new Map<string, { label: string; notes: NoteRecord[] }>();
	for (const note of notes) {
		for (const rawTag of note.tags) {
			const label = rawTag.trim();
			if (!label) continue;
			const key = label.toLocaleLowerCase();
			const group = groups.get(key) ?? { label, notes: [] };
			group.notes.push(note);
			groups.set(key, group);
		}
	}
	const usedSlugs = new Map<string, string>();
	return [...groups.entries()]
		.sort(([, a], [, b]) => a.label.localeCompare(b.label, "en"))
		.map(([key, group]) => {
			let slug = githubSlug(group.label) || "tag";
			const collision = usedSlugs.get(slug);
			if (collision && collision !== key) {
				slug += `-${createHash("sha256").update(key).digest("hex").slice(0, 6)}`;
			}
			usedSlugs.set(slug, key);
			return {
				label: group.label,
				slug,
				notes: [...group.notes].sort(
					(a, b) =>
						(b.date ?? "").localeCompare(a.date ?? "") || pathOrder(a, b),
				),
			};
		});
}
