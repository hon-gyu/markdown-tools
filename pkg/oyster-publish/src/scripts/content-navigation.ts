const article = document.querySelector<HTMLElement>(".content article");

// The code block's copy control is an icon, not a word: the toolbar is a quiet
// strip over the code and "Copy" repeated down a page reads as noise. The
// clipboard swaps to a check on success, which is the whole feedback channel
// now that there is no label to reword, so the accessible name changes with it.
const ICON_COPY = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
const ICON_COPIED = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m20 6-11 11-5-5"/></svg>`;

async function copyText(text: string): Promise<boolean> {
	try {
		await navigator.clipboard.writeText(text);
		return true;
	} catch {
		const field = document.createElement("textarea");
		field.value = text;
		field.style.position = "fixed";
		field.style.opacity = "0";
		document.body.append(field);
		field.select();
		const copied = (
			document as unknown as { execCommand(command: string): boolean }
		).execCommand("copy");
		field.remove();
		return copied;
	}
}

for (const pre of article?.querySelectorAll<HTMLPreElement>("pre") ?? []) {
	const code = pre.querySelector("code");
	if (!code) continue;
	const language =
		pre.dataset.language ??
		[...code.classList]
			.find((name) => name.startsWith("language-"))
			?.slice(9) ??
		"text";
	// A fence with no info string is highlighted as "plaintext". Naming that in
	// the toolbar says nothing the reader cannot already see, so the label is
	// left empty and only the copy button shows.
	const named = language !== "plaintext" && language !== "text";
	const toolbar = document.createElement("div");
	toolbar.className = "code-toolbar";
	const label = document.createElement("span");
	if (named)
		label.textContent = language === "mermaid" ? "Mermaid source" : language;
	const copy = document.createElement("button");
	copy.type = "button";
	copy.className = "code-copy";
	const copyLabel = named ? `Copy ${language} code` : "Copy code";
	const rest = () => {
		copy.innerHTML = ICON_COPY;
		copy.setAttribute("aria-label", copyLabel);
		copy.title = "Copy";
	};
	rest();
	copy.addEventListener("click", async () => {
		if (await copyText(code.textContent ?? "")) {
			copy.innerHTML = ICON_COPIED;
			copy.setAttribute("aria-label", "Copied");
			copy.title = "Copied";
			setTimeout(rest, 1500);
		}
	});
	toolbar.append(label, copy);
	// One container: the toolbar and the scrolling <pre> are wrapped so a single
	// element carries the border, radius and background. The <pre> stays a
	// separate scroll container, but nothing about it reads as a second box.
	const block = document.createElement("div");
	block.className = "code-block";
	pre.before(block);
	block.append(toolbar, pre);
	if (language === "mermaid") {
		pre.classList.add("mermaid-source");
		pre.setAttribute("aria-label", "Mermaid diagram source");
	}
}

for (const heading of article?.querySelectorAll<HTMLElement>(
	"h2[id], h3[id], h4[id], h5[id], h6[id]",
) ?? []) {
	const button = document.createElement("button");
	button.type = "button";
	button.className = "copy-heading-link";
	button.setAttribute(
		"aria-label",
		`Copy link to ${heading.textContent?.trim() ?? "section"}`,
	);
	button.textContent = "Copy link";
	button.addEventListener("click", async () => {
		const url = new URL(`#${heading.id}`, location.href).href;
		if (await copyText(url)) {
			button.textContent = "Copied";
			setTimeout(() => {
				button.textContent = "Copy link";
			}, 1500);
		} else {
			location.hash = heading.id;
		}
	});
	heading.append(button);
}

const backToTop =
	document.querySelector<HTMLButtonElement>("[data-back-to-top]");
if (backToTop) {
	const update = () => {
		backToTop.hidden =
			document.documentElement.scrollHeight < innerHeight * 2 ||
			scrollY < innerHeight;
	};
	backToTop.addEventListener("click", () =>
		scrollTo({ top: 0, behavior: "smooth" }),
	);
	addEventListener("scroll", update, { passive: true });
	addEventListener("resize", update);
	update();
}
