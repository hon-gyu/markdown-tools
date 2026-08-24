const tray = document.querySelector<HTMLElement>("[data-note-stack]");
const cache = new Map<string, { title: string; html: string }>();
const desktop = () => matchMedia("(min-width: 64rem)").matches;
const canonical = (href: string) => {
	const url = new URL(href, location.href);
	return `${url.pathname.replace(/\/+$/, "") || "/"}${url.hash}`;
};

async function loadNote(route: string) {
	const path = route.split("#")[0] || "/";
	const cached = cache.get(path);
	if (cached) return cached;
	const response = await fetch(path, { headers: { "X-Oyster-Stack": "1" } });
	if (!response.ok) throw new Error(`Stack request failed: ${response.status}`);
	const document = new DOMParser().parseFromString(
		await response.text(),
		"text/html",
	);
	const article = document.querySelector<HTMLElement>(".content article");
	if (!article) throw new Error("Stack response has no article");
	article.querySelector(".astryx-breadcrumbs")?.remove();
	for (const script of article.querySelectorAll("script")) script.remove();
	const note = {
		title: document.title.split(" · ")[0],
		html: article.innerHTML,
	};
	cache.set(path, note);
	return note;
}

function routesFromUrl(): string[] {
	return new URL(location.href).searchParams.getAll("stack").map(canonical);
}

function writeHistory(routes: string[], mode: "push" | "replace") {
	const url = new URL(location.href);
	url.searchParams.delete("stack");
	for (const route of routes) url.searchParams.append("stack", route);
	history[`${mode}State`]({}, "", url);
}

async function render(routes: string[]) {
	if (!tray) return;
	if (!desktop() || routes.length === 0) {
		tray.replaceChildren();
		tray.hidden = true;
		document.body.removeAttribute("data-note-stacking");
		return;
	}
	const unique = [...new Set(routes)];
	if (unique.length !== routes.length) writeHistory(unique, "replace");
	const panes = await Promise.all(
		unique.map(async (route) => {
			const note = await loadNote(route);
			const pane = document.createElement("section");
			pane.className = "note-stack-pane";
			pane.tabIndex = 0;
			pane.dataset.stackRoute = route;
			const heading = document.createElement("header");
			const open = document.createElement("a");
			open.href = route;
			open.textContent = note.title;
			open.title = "Open as a normal page";
			const close = document.createElement("button");
			close.type = "button";
			close.textContent = "Close";
			close.setAttribute("aria-label", `Close ${note.title}`);
			close.addEventListener("click", () => {
				const next = routesFromUrl().filter((candidate) => candidate !== route);
				writeHistory(next, "push");
				void render(next);
			});
			heading.append(open, close);
			const content = document.createElement("article");
			content.innerHTML = note.html;
			heading.querySelectorAll("script").forEach((script) => {
				script.remove();
			});
			pane.append(heading, content);
			const fragment = route.split("#")[1];
			if (fragment)
				requestAnimationFrame(() =>
					content
						.querySelector<HTMLElement>(
							`#${CSS.escape(decodeURIComponent(fragment))}`,
						)
						?.scrollIntoView(),
				);
			return pane;
		}),
	);
	tray.replaceChildren(...panes);
	tray.hidden = false;
	document.body.dataset.noteStacking = "";
	panes.at(-1)?.focus();
}

document.addEventListener("click", (event) => {
	if (
		!desktop() ||
		event.defaultPrevented ||
		event.button !== 0 ||
		!event.altKey ||
		event.metaKey ||
		event.ctrlKey ||
		event.shiftKey
	)
		return;
	const target =
		event.target instanceof Element
			? event.target.closest<HTMLAnchorElement>("article a.wikilink")
			: null;
	if (
		!target ||
		target.classList.contains("wikilink-unresolved") ||
		target.target === "_blank"
	)
		return;
	const url = new URL(target.href, location.href);
	if (url.origin !== location.origin || url.pathname === location.pathname)
		return;
	event.preventDefault();
	const route = canonical(url.href);
	const current = routesFromUrl();
	const routes = current.includes(route) ? current : [...current, route];
	writeHistory(routes, "push");
	void render(routes).catch(() => {
		location.href = target.href;
	});
});

addEventListener("popstate", () => void render(routesFromUrl()));
addEventListener("resize", () => void render(routesFromUrl()));
document.addEventListener("keydown", (event) => {
	if (!event.ctrlKey || !["ArrowLeft", "ArrowRight"].includes(event.key))
		return;
	const panes = [...document.querySelectorAll<HTMLElement>(".note-stack-pane")];
	const index = panes.findIndex(
		(pane) =>
			pane === document.activeElement || pane.contains(document.activeElement),
	);
	if (index === -1) return;
	event.preventDefault();
	panes[
		Math.max(
			0,
			Math.min(panes.length - 1, index + (event.key === "ArrowRight" ? 1 : -1)),
		)
	]?.focus();
});
void render(routesFromUrl()).catch(() => writeHistory([], "replace"));
