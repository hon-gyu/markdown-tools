import fs from "node:fs";
import path from "node:path";
import type { APIRoute } from "astro";
import { getVaultIndex } from "../../lib/note-index.ts";
import { vaultDir } from "../../lib/project-paths.ts";

export async function getStaticPaths() {
	const { reachableAttachments } = await getVaultIndex();
	return reachableAttachments.map((attachment) => ({
		params: {
			asset: `${attachment.url.split("/")[2]}/${attachment.basename}`,
		},
		props: { attachment },
	}));
}

export const GET: APIRoute = ({ props }) => {
	const attachment = props.attachment;
	const source = path.resolve(vaultDir, attachment.path);
	const relative = path.relative(vaultDir, source);
	if (relative.startsWith("..") || path.isAbsolute(relative)) {
		return new Response("Invalid attachment path", { status: 400 });
	}
	return new Response(fs.readFileSync(source), {
		headers: { "Content-Type": attachment.mimeType },
	});
};
