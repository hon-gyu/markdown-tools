import type { APIRoute } from "astro";
import { getVaultIndex } from "../../lib/note-index.ts";
import { previewPayload, previewUrlForPath } from "../../lib/preview-data.ts";

export async function getStaticPaths() {
	const { notes } = await getVaultIndex();
	return notes.map((note) => ({
		params: {
			preview: previewUrlForPath(note.path)
				.split("/")
				.at(-1)
				?.replace(/\.json$/, ""),
		},
		props: { payload: previewPayload(note) },
	}));
}

export const GET: APIRoute = ({ props }) =>
	new Response(JSON.stringify(props.payload), {
		headers: { "Content-Type": "application/json; charset=utf-8" },
	});
