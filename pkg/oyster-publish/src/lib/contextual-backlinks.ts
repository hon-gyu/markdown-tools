import type { NoteRecord } from "./vault-manifest.ts";

export interface ContextualBacklink {
	slug: string;
	title: string;
	count: number;
	mentions: { context: string; targetFragment: string | null; href: string }[];
}

export function contextualBacklinks(
	notes: NoteRecord[],
	targetPath: string,
): ContextualBacklink[] {
	return notes.flatMap((note) => {
		const links = note.links.filter(
			(link) =>
				link.status === "resolved" &&
				link.destinationKind === "note" &&
				link.destinationPath === targetPath,
		);
		if (links.length === 0) return [];

		const seen = new Set<string>();
		const mentions = links.flatMap((link) => {
			const key = `${link.sourceFragment ?? ""}\0${link.context}\0${link.fragment ?? ""}`;
			if (seen.has(key)) return [];
			seen.add(key);
			return [
				{
					context: link.context,
					targetFragment: link.fragment,
					href: `${note.slug}${link.sourceFragment ? `#${link.sourceFragment}` : ""}`,
				},
			];
		});
		const sourceFragment = links.find(
			(link) => link.sourceFragment,
		)?.sourceFragment;
		return [
			{
				slug: `${note.slug}${sourceFragment ? `#${sourceFragment}` : ""}`,
				title: note.title,
				count: links.length,
				mentions,
			},
		];
	});
}
