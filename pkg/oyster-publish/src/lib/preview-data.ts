import { createHash } from "node:crypto";
import type { NoteRecord } from "./vault-manifest.ts";

export interface PreviewPayload {
	title: string;
	breadcrumb: string;
	href: string;
	excerpt: string;
	anchors: Record<string, { label: string; excerpt: string }>;
}

export function previewUrlForPath(notePath: string): string {
	const id = createHash("sha256").update(notePath).digest("hex").slice(0, 16);
	return `/oyster-previews/${id}.json`;
}

export function previewPayload(note: NoteRecord): PreviewPayload {
	const slash = note.path.lastIndexOf("/");
	const breadcrumb =
		slash === -1 ? "" : note.path.slice(0, slash).split("/").join(" / ");
	return {
		title: note.title,
		breadcrumb,
		href: note.slug,
		excerpt: note.excerpt,
		anchors: Object.fromEntries(
			note.anchors.map((anchor) => [
				anchor.id.toLowerCase(),
				{ label: anchor.text || anchor.id, excerpt: anchor.excerpt },
			]),
		),
	};
}
