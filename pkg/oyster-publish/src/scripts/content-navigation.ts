const article = document.querySelector<HTMLElement>(".content article");

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
	copy.textContent = "Copy";
	copy.setAttribute(
		"aria-label",
		named ? `Copy ${language} code` : "Copy code",
	);
	copy.addEventListener("click", async () => {
		if (await copyText(code.textContent ?? "")) {
			copy.textContent = "Copied";
			setTimeout(() => {
				copy.textContent = "Copy";
			}, 1500);
		}
	});
	toolbar.append(label, copy);
	pre.before(toolbar);
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
