import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, expect, test } from "vitest";
import {
	attachmentKind,
	attachmentRecord,
	attachmentUrl,
	scanVaultAttachments,
} from "./vault-attachments.ts";

const temporaryDirectories: string[] = [];

afterEach(() => {
	for (const directory of temporaryDirectories.splice(0)) {
		fs.rmSync(directory, { recursive: true, force: true });
	}
});

test("classifies supported media independently of extension case", () => {
	expect(attachmentKind(".PNG")).toBe("image");
	expect(attachmentKind("mp3")).toBe("audio");
	expect(attachmentKind("WebM")).toBe("video");
	expect(attachmentKind("pdf")).toBe("pdf");
	expect(attachmentKind("zip")).toBe("file");
});

test("records Unicode paths and duplicate basenames without collapsing identity", () => {
	expect(attachmentRecord("一/diagram.png")).toMatchObject({
		path: "一/diagram.png",
		basename: "diagram.png",
		kind: "image",
	});
	expect(attachmentRecord("二/diagram.png").path).toBe("二/diagram.png");
	expect(attachmentUrl("一/diagram.png")).not.toBe(
		attachmentUrl("二/diagram.png"),
	);
	expect(attachmentUrl("一/diagram.png")).toMatch(
		/^\/oyster-assets\/[a-f0-9]{16}\/diagram\.png$/,
	);
});

test("inventory is deterministic and ignores notes, dot-directories, and symlinks", () => {
	const vault = fs.mkdtempSync(path.join(os.tmpdir(), "oyster-attachments-"));
	temporaryDirectories.push(vault);
	fs.mkdirSync(path.join(vault, "Media"));
	fs.mkdirSync(path.join(vault, ".oyster"));
	fs.writeFileSync(path.join(vault, "note.md"), "# Note");
	fs.writeFileSync(path.join(vault, "Media", "β image.PNG"), "image");
	fs.writeFileSync(path.join(vault, "Media", "audio.mp3"), "audio");
	fs.writeFileSync(path.join(vault, ".oyster", "private.bin"), "private");
	fs.symlinkSync(path.dirname(vault), path.join(vault, "outside"));

	expect(scanVaultAttachments(vault)).toEqual([
		{
			path: "Media/audio.mp3",
			basename: "audio.mp3",
			extension: "mp3",
			kind: "audio",
			url: attachmentUrl("Media/audio.mp3"),
			mimeType: "audio/mpeg",
		},
		{
			path: "Media/β image.PNG",
			basename: "β image.PNG",
			extension: "png",
			kind: "image",
			url: attachmentUrl("Media/β image.PNG"),
			mimeType: "image/png",
		},
	]);
});
