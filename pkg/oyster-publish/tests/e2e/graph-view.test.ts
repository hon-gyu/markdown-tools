// End-to-end cover for the graph widget, against `tests/fixtures/messy-vault` —
// a vault whose filenames are *not* already slug-shaped (capitals, spaces,
// punctuation, non-Latin scripts), unlike the tidy sample vault in `vault/`.
//
// This exists because of a bug the unit tests structurally could not catch: a
// note's URL and the hrefs linking to it were derived by two different rules, so
// on a real vault the widget could not find its own focus note. It silently fell
// back to the global view and hid the local/global toggle — no error, nothing
// thrown, just the wrong graph. Only a built page in a real browser shows that.
//
// So the assertions below are deliberately about *observable behaviour*: the
// toggle is on screen, the default view is a strict subset of the vault, and a
// link on the page actually leads somewhere.

import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { type Browser, chromium, type Page } from "playwright";
import { afterAll, beforeAll, expect, test } from "vitest";

const root = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../..",
);
const vault = path.join(root, "tests/fixtures/messy-vault");

// The note the local view is anchored on. It links to two others; the rest of
// the fixture vault is unreachable from it, so local must be strictly smaller.
const FOCUS = "/garden/tomatoes";

let browser: Browser;
let page: Page;
let server: Server;
let base: string;

beforeAll(async () => {
	const out = mkdtempSync(path.join(tmpdir(), "oyster-e2e-"));
	const build = spawnSync(
		process.execPath,
		["bin/oyster-publish.mjs", "build", "-v", vault, "-o", out],
		{ cwd: root, encoding: "utf8" },
	);
	if (build.status !== 0) {
		throw new Error(`fixture build failed:\n${build.stdout}\n${build.stderr}`);
	}

	// Serve the built site. Astro emits directory-style routes, so "/a/b" is
	// "/a/b/index.html" on disk.
	server = createServer(async (req, res) => {
		const url = decodeURIComponent((req.url ?? "/").split("?")[0]);
		// Read before responding: a miss on the page must be free to fall through to
		// the asset path, and neither may have sent headers yet.
		const read = async (p: string) => {
			try {
				return await readFile(p);
			} catch {
				return null;
			}
		};

		const page = await read(path.join(out, url, "index.html"));
		if (page) {
			res.writeHead(200, { "content-type": "text/html" });
			res.end(page);
			return;
		}

		const asset = await read(path.join(out, url));
		if (asset) {
			const type = url.endsWith(".js")
				? "text/javascript"
				: url.endsWith(".css")
					? "text/css"
					: "application/octet-stream";
			res.writeHead(200, { "content-type": type });
			res.end(asset);
			return;
		}

		res.writeHead(404);
		res.end("not found");
	});
	await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
	const { port } = server.address() as { port: number };
	base = `http://127.0.0.1:${port}`;

	browser = await chromium.launch();
	page = await browser.newPage();
	await page.goto(base + FOCUS, { waitUntil: "networkidle" });
});

afterAll(async () => {
	await browser?.close();
	await new Promise((r) => server?.close(r));
});

// Scoped to the mount: the control buttons are SVG icons made of <circle>s too,
// and counting those instead of the graph's nodes would quietly pass.
const nodes = () =>
	page.locator("[data-graph-panel] [data-graph-mount] > svg circle").count();
const toggle = () =>
	page.locator("[data-graph-panel] [data-graph-toggle]").first();
const positions = () =>
	page
		.locator("[data-graph-panel] [data-graph-mount]")
		.first()
		.locator("circle[data-node-id]")
		.evaluateAll((elements) =>
			Object.fromEntries(
				elements.map((element) => [
					element.getAttribute("data-node-id")!,
					{
						x: Number(element.getAttribute("cx")),
						y: Number(element.getAttribute("cy")),
					},
				]),
			),
		);

test("the local/global toggle is on screen", async () => {
	// It hides itself when the focus note can't be resolved — the bug's tell.
	await expect.poll(() => toggle().isVisible()).toBe(true);
});

test("the graph is already settled when it first appears", async () => {
	const initial = await positions();
	await page.waitForTimeout(500);
	const later = await positions();

	for (const [id, position] of Object.entries(initial)) {
		expect(
			Math.hypot(later[id].x - position.x, later[id].y - position.y),
			id,
		).toBeLessThan(1);
	}
});

test("a note opens on its local view, not the whole vault", async () => {
	const local = await nodes();
	expect(local).toBeGreaterThan(0);
	const before = await positions();

	await toggle().click();
	await expect.poll(nodes, { timeout: 10_000 }).toBeGreaterThan(local);

	const entered = await positions();
	await page.waitForTimeout(500);
	const settled = await positions();
	const displacement = (
		a: { x: number; y: number },
		b: { x: number; y: number },
	) => Math.hypot(b.x - a.x, b.y - a.y);

	// Nodes common to both scopes stay put while global-only nodes settle.
	for (const [id, position] of Object.entries(before)) {
		expect(displacement(position, settled[id]), id).toBeLessThan(1);
	}

	// Orphans have no links to establish a natural force equilibrium. They are
	// deliberately held at their deterministic entry position instead of being
	// repelled indefinitely through or beyond the graph.
	const orphanIds = await page.evaluate(() => {
		const payload = document.querySelector("[data-graph-payload]");
		if (!payload?.textContent) throw new Error("Missing graph payload");
		const data = JSON.parse(payload.textContent) as {
			nodes: { id: string; degree: number }[];
		};
		return data.nodes
			.filter((node) => node.degree === 0)
			.map((node) => node.id);
	});
	expect(orphanIds.length).toBeGreaterThan(0);
	for (const id of orphanIds) {
		expect(displacement(entered[id], settled[id]), id).toBeLessThan(1);
	}
});

test("the toggle switches back to the local view", async () => {
	const global = await nodes();
	await toggle().click();
	await expect.poll(nodes, { timeout: 10_000 }).toBeLessThan(global);
});

test("an in-body wikilink resolves to a page that exists", async () => {
	// A wikilink whose target filename needs slugifying ("Soil pH (basics).md").
	// If the href is built by a different rule than the route, this 404s.
	const href = await page.locator("a.wikilink").first().getAttribute("href");
	const res = await page.request.get(base + href!);
	expect(res.status(), `${href} should exist`).toBe(200);
});

test("permalinks are canonical and original paths and aliases redirect", async () => {
	for (const route of [
		"/field-notes/growing-tomatoes",
		"/tomatoes",
		"/old/growing-tomatoes",
	]) {
		await page.goto(base + route, { waitUntil: "networkidle" });
		await expect.poll(() => new URL(page.url()).pathname).toBe(FOCUS);
	}
	await page.goto(`${base}/field-notes/soil-ph-basics`, {
		waitUntil: "networkidle",
	});
	expect(await page.locator(`a[href="${FOCUS}"]`).count()).toBeGreaterThan(0);
});

test("every graph node links to a page that exists", async () => {
	const hrefs: string[] = await page.evaluate(() => {
		const el = document.querySelector("[data-graph-payload]");
		if (!el?.textContent) throw new Error("Missing graph payload");
		const data = JSON.parse(el.textContent) as { nodes: { href: string }[] };
		return data.nodes.map((n) => n.href);
	});
	expect(hrefs.length).toBeGreaterThan(1);

	for (const href of hrefs) {
		const res = await page.request.get(base + href);
		expect(res.status(), `${href} should exist`).toBe(200);
	}
});

test("previews load lazily, select fragments, cache, and dismiss by keyboard", async () => {
	const requests: string[] = [];
	const record = (request: { url(): string }) => {
		if (request.url().includes("/oyster-previews/"))
			requests.push(request.url());
	};
	page.on("request", record);
	await page.goto(base + FOCUS, { waitUntil: "networkidle" });
	expect(requests).toEqual([]);

	const link = page.locator('article a.wikilink[href*="#details"]').first();
	await link.focus();
	await expect.poll(() => requests.length).toBe(1);
	await expect.poll(() => page.locator("#note-preview").isVisible()).toBe(true);
	expect(
		await page.locator("#note-preview [data-preview-title]").textContent(),
	).toBe("Details");
	expect(
		await page.locator("#note-preview [data-preview-excerpt]").textContent(),
	).toContain("fragment-specific context");

	await page.keyboard.press("Escape");
	await expect.poll(() => page.locator("#note-preview").isHidden()).toBe(true);
	await link.hover();
	await expect.poll(() => page.locator("#note-preview").isVisible()).toBe(true);
	expect(requests).toHaveLength(1);
	page.off("request", record);
});

test("dedicated search restores URL state and supports phrase queries", async () => {
	await page.goto(`${base}/search?q=%22local+view%22`, {
		waitUntil: "networkidle",
	});
	const input = page.locator("#site-search");
	await expect.poll(() => input.inputValue()).toBe('"local view"');
	expect(
		await page.locator(".search-page-results > li").count(),
	).toBeGreaterThan(0);
	expect(await page.locator(".search-page-count").textContent()).toMatch(
		/result/,
	);

	await input.fill("tomatoes");
	await expect
		.poll(() => new URL(page.url()).searchParams.get("q"))
		.toBe("tomatoes");
	await page.locator("body").click({ position: { x: 700, y: 500 } });
	await page.keyboard.press("/");
	expect(
		await input.evaluate((element) => element === document.activeElement),
	).toBe(true);
});

test("the page outline tracks fragments and exposes heading copy actions", async () => {
	await page.goto(`${base}/field-notes/soil-ph-basics#details`, {
		waitUntil: "networkidle",
	});
	const tocLink = page.locator('[data-toc-link="details"]');
	await expect.poll(() => tocLink.getAttribute("class")).toContain("active");
	const copy = page.locator("#details .copy-heading-link");
	expect(await copy.getAttribute("aria-label")).toContain("Details");
	await copy.click();
	await expect.poll(() => copy.textContent()).toBe("Copied");
});

test("rich content controls preserve code, Mermaid fallback, comments, and visible properties", async () => {
	await page.goto(base + FOCUS, { waitUntil: "networkidle" });
	expect(await page.locator(".code-toolbar").count()).toBe(2);
	expect(await page.locator(".code-toolbar").first().textContent()).toContain(
		"typescript",
	);
	expect(
		await page.locator("pre.mermaid-source").getAttribute("aria-label"),
	).toBe("Mermaid diagram source");
	expect(await page.locator("article").textContent()).not.toContain(
		"private growing note",
	);
	expect(await page.locator(".note-meta").textContent()).toContain(
		"By Garden Desk",
	);
	expect(await page.locator(".note-meta").textContent()).toContain(
		"Status: Evergreen",
	);
	const copy = page.locator(
		'.code-toolbar button[aria-label="Copy typescript code"]',
	);
	await copy.click();
	await expect.poll(() => copy.textContent()).toBe("Copied");
});

test("desktop internal links navigate normally and Alt-click opens a note stack", async () => {
	await page.setViewportSize({ width: 1280, height: 800 });
	await page.goto(base + FOCUS, { waitUntil: "networkidle" });
	let link = page
		.locator('article a.wikilink[href*="soil-ph-basics#details"]')
		.first();
	await link.click();
	expect(new URL(page.url()).pathname).toBe("/field-notes/soil-ph-basics");
	expect(new URL(page.url()).hash).toBe("#details");
	expect(await page.locator(".note-stack-pane").count()).toBe(0);

	await page.goBack({ waitUntil: "networkidle" });
	link = page
		.locator('article a.wikilink[href*="soil-ph-basics#details"]')
		.first();
	await link.click({ modifiers: ["Alt"] });
	const pane = page.locator(
		'.note-stack-pane[data-stack-route="/field-notes/soil-ph-basics#details"]',
	);
	await expect.poll(() => pane.count()).toBe(1);
	expect(new URL(page.url()).searchParams.getAll("stack")).toEqual([
		"/field-notes/soil-ph-basics#details",
	]);
	expect(await pane.locator("#details").count()).toBe(1);

	await page.goBack({ waitUntil: "networkidle" });
	await expect.poll(() => page.locator(".note-stack-pane").count()).toBe(0);
	await page.goForward({ waitUntil: "networkidle" });
	await expect.poll(() => page.locator(".note-stack-pane").count()).toBe(1);
	await pane.locator("header button").click();
	await expect.poll(() => page.locator(".note-stack-pane").count()).toBe(0);
});

test("mobile drawers remain operable and content never widens the viewport", async () => {
	for (const width of [320, 375, 768]) {
		await page.setViewportSize({ width, height: 720 });
		await page.goto(`${base}/field-notes/soil-ph-basics`, {
			waitUntil: "networkidle",
		});
		const menu = page.locator('[data-mobile-open="sidebar"]');
		expect(await menu.isVisible(), `${width}px menu`).toBe(true);
		expect(
			await page.evaluate(
				() => document.documentElement.scrollWidth <= innerWidth,
			),
		).toBe(true);

		await menu.click();
		await expect
			.poll(() => page.locator("#mobile-sidebar").getAttribute("data-open"))
			.toBe("");
		expect(
			await page.evaluate(() => document.body.dataset.mobilePanelOpen),
		).toBe("sidebar");
		expect(
			await page.locator("#mobile-sidebar a[data-preview-url]").count(),
		).toBe(0);
		expect(await page.locator("#note-preview").isHidden()).toBe(true);

		// Header controls stay reachable while a drawer is open, so readers can
		// switch directly from navigation to search instead of closing it first.
		const search = page.locator("[data-mobile-search]");
		await search.click();
		await expect
			.poll(() =>
				page
					.locator("#mobile-sidebar input")
					.evaluate((element) => element === document.activeElement),
			)
			.toBe(true);
		await page.keyboard.press("Escape");
		expect(await menu.getAttribute("aria-expanded")).toBe("false");
		await expect
			.poll(() =>
				search.evaluate((element) => element === document.activeElement),
			)
			.toBe(true);

		await search.click();
		await expect
			.poll(() =>
				page
					.locator("#mobile-sidebar input")
					.evaluate((element) => element === document.activeElement),
			)
			.toBe(true);
		await page
			.locator("[data-mobile-close]")
			.click({ position: { x: width - 4, y: 400 } });

		const pageTools = page.locator('[data-mobile-open="rightbar"]');
		await pageTools.click();
		await expect
			.poll(() => page.locator("#mobile-rightbar").getAttribute("data-open"))
			.toBe("");
		expect(
			await page.locator("#mobile-rightbar [data-graph-panel]").isVisible(),
		).toBe(true);
		expect(await page.locator("#mobile-rightbar .toc").isVisible()).toBe(true);
		expect((await page.screenshot()).byteLength).toBeGreaterThan(1_000);
		await page.keyboard.press("Escape");
	}

	await page.setViewportSize({ width: 1024, height: 768 });
	await page.goto(base + FOCUS, { waitUntil: "networkidle" });
	expect(await page.locator(".mobile-header").isHidden()).toBe(true);
	expect(await page.locator(".sidebar").isVisible()).toBe(true);
	expect(
		await page.evaluate(
			() => document.documentElement.scrollWidth <= innerWidth,
		),
	).toBe(true);
	expect((await page.screenshot()).byteLength).toBeGreaterThan(1_000);
});
