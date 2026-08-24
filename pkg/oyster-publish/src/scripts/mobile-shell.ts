type PanelName = "sidebar" | "rightbar";

const mobile = matchMedia("(max-width: 48rem)");
const backdrop = document.querySelector<HTMLButtonElement>(
	"[data-mobile-close]",
)!;
const panels = new Map<PanelName, HTMLElement>();
for (const panel of document.querySelectorAll<HTMLElement>(
	"[data-mobile-panel]",
)) {
	panels.set(panel.dataset.mobilePanel as PanelName, panel);
}
let activePanel: HTMLElement | null = null;
let returnFocus: HTMLElement | null = null;

const controlsFor = (name: PanelName) =>
	document.querySelectorAll<HTMLElement>(
		`[data-mobile-open="${name}"], ${name === "sidebar" ? "[data-mobile-search]" : "[data-never]"}`,
	);
const focusable = (panel: HTMLElement) =>
	Array.from(
		panel.querySelectorAll<HTMLElement>(
			'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
		),
	).filter((element) => !element.hidden && element.getClientRects().length > 0);

function closePanel(restoreFocus = true): void {
	if (!activePanel) return;
	const name = activePanel.dataset.mobilePanel as PanelName;
	const focusTarget = returnFocus;
	delete activePanel.dataset.open;
	activePanel = null;
	backdrop.hidden = true;
	delete document.body.dataset.mobilePanelOpen;
	for (const control of controlsFor(name))
		control.setAttribute("aria-expanded", "false");
	returnFocus = null;
	if (restoreFocus) requestAnimationFrame(() => focusTarget?.focus());
}

function openPanel(
	name: PanelName,
	trigger: HTMLElement,
	focusSearch = false,
): void {
	const panel = panels.get(name);
	if (!panel || !mobile.matches) return;
	closePanel(false);
	document.dispatchEvent(new CustomEvent("oyster:mobile-panel"));
	activePanel = panel;
	returnFocus = trigger;
	panel.dataset.open = "";
	backdrop.hidden = false;
	document.body.dataset.mobilePanelOpen = name;
	for (const control of controlsFor(name))
		control.setAttribute("aria-expanded", "true");
	requestAnimationFrame(() => {
		const target = focusSearch
			? panel.querySelector<HTMLElement>("input")
			: focusable(panel)[0];
		(target ?? panel).focus();
	});
}

document.addEventListener("click", (event) => {
	const target = event.target instanceof Element ? event.target : null;
	const search = target?.closest<HTMLElement>("[data-mobile-search]");
	if (search) return openPanel("sidebar", search, true);
	const opener = target?.closest<HTMLElement>("[data-mobile-open]");
	if (opener) openPanel(opener.dataset.mobileOpen as PanelName, opener);
	if (target?.closest("[data-mobile-close]")) closePanel();
});

document.addEventListener("keydown", (event) => {
	if (!activePanel) return;
	if (event.key === "Escape") {
		event.preventDefault();
		closePanel();
		return;
	}
	if (event.key !== "Tab") return;
	const items = focusable(activePanel);
	if (items.length === 0) {
		event.preventDefault();
		activePanel.focus();
		return;
	}
	const first = items[0];
	const last = items.at(-1)!;
	if (event.shiftKey && document.activeElement === first) {
		event.preventDefault();
		last.focus();
	} else if (!event.shiftKey && document.activeElement === last) {
		event.preventDefault();
		first.focus();
	}
});

mobile.addEventListener("change", (event) => {
	if (!event.matches) closePanel(false);
});
