import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type AttachmentKind = "image" | "audio" | "video" | "pdf" | "file";

export interface VaultAttachment {
	path: string;
	basename: string;
	extension: string;
	kind: AttachmentKind;
	url: string;
	mimeType: string;
}

const imageExtensions = new Set(["gif", "jpeg", "jpg", "png", "svg", "webp"]);
const audioExtensions = new Set(["flac", "m4a", "mp3", "oga", "ogg", "wav"]);
const videoExtensions = new Set(["m4v", "mov", "mp4", "ogv", "webm"]);

export function attachmentKind(extension: string): AttachmentKind {
	const ext = extension.toLowerCase().replace(/^\./, "");
	if (imageExtensions.has(ext)) return "image";
	if (audioExtensions.has(ext)) return "audio";
	if (videoExtensions.has(ext)) return "video";
	if (ext === "pdf") return "pdf";
	return "file";
}

export function attachmentRecord(relativePath: string): VaultAttachment {
	const normalized = relativePath.split(path.sep).join("/");
	const extension = path.posix.extname(normalized).slice(1).toLowerCase();
	return {
		path: normalized,
		basename: path.posix.basename(normalized),
		extension,
		kind: attachmentKind(extension),
		url: attachmentUrl(normalized),
		mimeType: attachmentMimeType(extension),
	};
}

const mimeTypes: Record<string, string> = {
	gif: "image/gif",
	jpeg: "image/jpeg",
	jpg: "image/jpeg",
	png: "image/png",
	svg: "image/svg+xml",
	webp: "image/webp",
	flac: "audio/flac",
	m4a: "audio/mp4",
	mp3: "audio/mpeg",
	oga: "audio/ogg",
	ogg: "audio/ogg",
	wav: "audio/wav",
	m4v: "video/mp4",
	mov: "video/quicktime",
	mp4: "video/mp4",
	ogv: "video/ogg",
	webm: "video/webm",
	pdf: "application/pdf",
};

export function attachmentMimeType(extension: string): string {
	return (
		mimeTypes[extension.toLowerCase().replace(/^\./, "")] ??
		"application/octet-stream"
	);
}

export function attachmentUrl(relativePath: string): string {
	const normalized = relativePath.replaceAll("\\", "/");
	const identity = createHash("sha256")
		.update(normalized)
		.digest("hex")
		.slice(0, 16);
	return `/oyster-assets/${identity}/${encodeURIComponent(path.posix.basename(normalized))}`;
}

/** Inventory non-note files without following symlinks outside the vault. */
export function scanVaultAttachments(vaultDir: string): VaultAttachment[] {
	const attachments: VaultAttachment[] = [];

	function scan(directory: string, prefix: string): void {
		const entries = fs
			.readdirSync(directory, { withFileTypes: true })
			.sort((a, b) => a.name.localeCompare(b.name, "en"));
		for (const entry of entries) {
			if (entry.name.startsWith(".")) continue;
			const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
			if (entry.isDirectory()) {
				scan(path.join(directory, entry.name), relativePath);
			} else if (entry.isFile() && !/\.(md|mdx)$/i.test(entry.name)) {
				attachments.push(attachmentRecord(relativePath));
			}
		}
	}

	scan(vaultDir, "");
	return attachments;
}
