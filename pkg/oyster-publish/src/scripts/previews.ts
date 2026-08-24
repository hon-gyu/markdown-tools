type PreviewPayload = {
	title: string;
	breadcrumb: string;
	href: string;
	excerpt: string;
	anchors: Record<string, { label: string; excerpt: string }>;
};

const preview = document.querySelector<HTMLElement>("#note-preview")!;
const previewTitle = preview.querySelector<HTMLElement>(
	"[data-preview-title]",
)!;
const previewBreadcrumb = preview.querySelector<HTMLElement>(
	"[data-preview-breadcrumb]",
)!;
const previewExcerpt = preview.querySelector<HTMLElement>(
	"[data-preview-excerpt]",
)!;
const previewOpen = preview.querySelector<HTMLAnchorElement>(
	"[data-preview-open]",
)!;
const previewCache = new Map<string, Promise<PreviewPayload>>();
const previewRoutes = JSON.parse(
	document.querySelector("#note-preview-routes")?.textContent || "{}",
) as Record<string, string>;

// Previews are a reading aid, not shell chrome. Restrict them to links in note
// content: focusing the first item in a mobile navigation drawer must not open
// a preview card over the drawer itself.
for (const link of document.querySelectorAll<HTMLAnchorElement>(
	".content article a[href], .note-stack a[href]",
)) {
	const target = new URL(link.href, location.href);
	if (
		target.origin !== location.origin ||
		target.pathname === location.pathname
	)
		continue;
	const previewUrl = previewRoutes[target.pathname.replace(/\/+$/, "") || "/"];
	if (previewUrl) link.dataset.previewUrl = previewUrl;
}

let activeLink: HTMLAnchorElement | null = null;
let showTimer = 0;
let hideTimer = 0;
let touchArmed: HTMLAnchorElement | null = null;

const linkAt = (target: EventTarget | null) =>
	target instanceof Element
		? target.closest<HTMLAnchorElement>("a[data-preview-url]")
		: null;

const payloadFor = (url: string) => {
	let pending = previewCache.get(url);
	if (!pending) {
		pending = fetch(url).then((response) => {
			if (!response.ok)
				throw new Error(`Preview request failed: ${response.status}`);
			return response.json() as Promise<PreviewPayload>;
		});
		previewCache.set(url, pending);
	}
	return pending;
};

const placePreview = (link: HTMLAnchorElement) => {
	if (matchMedia("(max-width: 40rem)").matches) return;
	const anchor = link.getBoundingClientRect();
	const box = preview.getBoundingClientRect();
	const gap = 10;
	const left = Math.max(
		gap,
		Math.min(anchor.left, innerWidth - box.width - gap),
	);
	let top = anchor.bottom + gap;
	if (top + box.height > innerHeight - gap) top = anchor.top - box.height - gap;
	preview.style.left = `${left}px`;
	preview.style.top = `${Math.max(gap, top)}px`;
};

const closePreview = () => {
	clearTimeout(showTimer);
	clearTimeout(hideTimer);
	activeLink?.removeAttribute("aria-describedby");
	activeLink = null;
	preview.hidden = true;
	touchArmed = null;
};

const showPreview = async (link: HTMLAnchorElement) => {
	const url = link.dataset.previewUrl;
	if (!url) return;
	activeLink?.removeAttribute("aria-describedby");
	activeLink = link;
	link.setAttribute("aria-describedby", preview.id);
	try {
		const payload = await payloadFor(url);
		if (activeLink !== link) return;
		const fragment = decodeURIComponent(link.hash.slice(1)).toLowerCase();
		const anchor = fragment ? payload.anchors[fragment] : undefined;
		previewTitle.textContent = anchor?.label ?? payload.title;
		previewBreadcrumb.textContent = payload.breadcrumb;
		previewBreadcrumb.hidden = !payload.breadcrumb;
		previewExcerpt.textContent = anchor?.excerpt || payload.excerpt;
		previewOpen.href = link.href;
		preview.hidden = false;
		requestAnimationFrame(() => placePreview(link));
	} catch {
		if (activeLink === link) closePreview();
	}
};

const scheduleShow = (link: HTMLAnchorElement, delay: number) => {
	clearTimeout(showTimer);
	clearTimeout(hideTimer);
	showTimer = window.setTimeout(() => showPreview(link), delay);
};
const scheduleHide = () => {
	clearTimeout(hideTimer);
	hideTimer = window.setTimeout(closePreview, 120);
};

document.addEventListener("pointerover", (event) => {
	const link = linkAt(event.target);
	if (link && event.pointerType !== "touch") scheduleShow(link, 320);
});
document.addEventListener("pointerout", (event) => {
	const link = linkAt(event.target);
	if (link && !preview.contains(event.relatedTarget as Node | null))
		scheduleHide();
});
document.addEventListener("focusin", (event) => {
	const link = linkAt(event.target);
	if (link) scheduleShow(link, 0);
});
document.addEventListener("focusout", (event) => {
	if (
		linkAt(event.target) &&
		!preview.contains(event.relatedTarget as Node | null)
	) {
		scheduleHide();
	}
});
document.addEventListener("click", (event) => {
	const link = linkAt(event.target);
	if (link && matchMedia("(hover: none)").matches && touchArmed !== link) {
		event.preventDefault();
		touchArmed = link;
		showPreview(link);
		return;
	}
	if (!link && !preview.contains(event.target as Node)) closePreview();
});
document.addEventListener("keydown", (event) => {
	if (event.key === "Escape" && !preview.hidden) {
		event.preventDefault();
		const link = activeLink;
		closePreview();
		link?.focus();
	}
});
preview.addEventListener("pointerenter", () => clearTimeout(hideTimer));
preview.addEventListener("pointerleave", scheduleHide);
document.addEventListener("oyster:mobile-panel", closePreview);
addEventListener("resize", () => activeLink && placePreview(activeLink));
addEventListener("scroll", () => activeLink && placePreview(activeLink), true);
