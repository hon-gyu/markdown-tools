// The sidebar "search page or heading" feature, as plain data + pure matching —
// no Astro, no DOM — so the ranking/snippet/highlight logic is unit-testable,
// like wikilink.ts and graph-data.ts. The Astro-coupled `note-index.ts` builds
// the docs; the Astryx sidebar in components/OysterNav.tsx renders the results.

// Types
// ====================

export interface SearchHeading {
	text: string;
	slug: string; // matches the rendered heading's id, so `#slug` anchors it
}

// One searchable note: its title, where it lives, its headings, and its body as
// plain text (markdown stripped) for snippet matching.
export interface SearchDoc {
	title: string;
	href: string;
	breadcrumb: string; // human folder path, e.g. "Rust" or "A / B"
	text: string;
	headings: SearchHeading[];
	tags?: string[];
}

// A run of result text, flagged when it coincides with a query term so the UI
// can wrap it in <mark>. Returning segments (not HTML) keeps note content from
// ever being interpreted as markup.
export interface Segment {
	text: string;
	hit: boolean;
}

// One note's worth of results: an optional title match, an optional body
// snippet, and any headings that matched. At least one is always present.
export interface SearchResult {
	href: string;
	breadcrumb: string;
	title: Segment[];
	titleMatch: boolean;
	snippet: Segment[] | null;
	headings: { text: Segment[]; slug: string }[];
	tags: string[];
}

export interface SearchOptions {
	tags?: string[];
}

// Matching
// ====================

const MAX_RESULTS = 20;
const MAX_HEADINGS_PER_DOC = 4;
const SNIPPET_BEFORE = 40; // chars of context before the first hit
const SNIPPET_AFTER = 80; // ...and after

function escapeRegExp(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Split `text` into segments, marking the spans that match any query term.
function highlight(text: string, terms: string[]): Segment[] {
	if (terms.length === 0) return [{ text, hit: false }];
	const re = new RegExp(`(${terms.map(escapeRegExp).join("|")})`, "ig");
	const segs: Segment[] = [];
	let last = 0;
	for (const m of text.matchAll(re)) {
		const i = m.index!;
		if (i > last) segs.push({ text: text.slice(last, i), hit: false });
		segs.push({ text: m[0], hit: true });
		last = i + m[0].length;
	}
	if (last < text.length) segs.push({ text: text.slice(last), hit: false });
	return segs;
}

// A snippet of `text` around the earliest term hit, with ellipses and the terms
// highlighted. Null when no term occurs in the body.
function snippetAround(text: string, terms: string[]): Segment[] | null {
	const lower = text.toLowerCase();
	let pos = -1;
	for (const t of terms) {
		const i = lower.indexOf(t);
		if (i !== -1 && (pos === -1 || i < pos)) pos = i;
	}
	if (pos === -1) return null;

	const start = Math.max(0, pos - SNIPPET_BEFORE);
	const end = Math.min(text.length, pos + SNIPPET_AFTER);
	let snip = text.slice(start, end).trim();
	if (start > 0) snip = `…${snip}`;
	if (end < text.length) snip = `${snip}…`;
	return highlight(snip, terms);
}

// Rank + shape the docs for a query. A doc is a hit when every whitespace-split
// term appears somewhere in it (title, a heading, or the body). Results are
// ordered title matches first, then heading matches, then body-only matches.
export function searchTerms(query: string): string[] {
	const terms: string[] = [];
	const matcher = /"([^"]+)"|(\S+)/g;
	for (const match of query.matchAll(matcher)) {
		const term = (match[1] ?? match[2]).trim().toLowerCase();
		if (term) terms.push(term);
	}
	return terms;
}

export function searchDocs(
	docs: SearchDoc[],
	query: string,
	options: SearchOptions = {},
): SearchResult[] {
	const terms = searchTerms(query);
	const selectedTags = (options.tags ?? []).map((tag) => tag.toLowerCase());
	if (terms.length === 0) return [];

	const scored: { result: SearchResult; rank: number }[] = [];
	for (const doc of docs) {
		const docTags = (doc.tags ?? []).map((tag) => tag.toLowerCase());
		if (!selectedTags.every((tag) => docTags.includes(tag))) continue;
		const haystack = (
			doc.title +
			"\n" +
			doc.headings.map((h) => h.text).join("\n") +
			"\n" +
			docTags.join("\n") +
			"\n" +
			doc.text
		).toLowerCase();
		// Every term must be present somewhere in the note.
		if (!terms.every((t) => haystack.includes(t))) continue;

		const titleLower = doc.title.toLowerCase();
		const titleMatch = terms.some((t) => titleLower.includes(t));

		const headings = doc.headings
			.filter((h) => {
				const hl = h.text.toLowerCase();
				return terms.some((t) => hl.includes(t));
			})
			.slice(0, MAX_HEADINGS_PER_DOC)
			.map((h) => ({ text: highlight(h.text, terms), slug: h.slug }));

		const snippet = snippetAround(doc.text, terms);

		// Prefer exact title phrases, then title hits, headings, tags, and body.
		const rank =
			titleLower === terms.join(" ")
				? 0
				: titleMatch
					? 1
					: headings.length > 0
						? 2
						: terms.some((term) => docTags.some((tag) => tag.includes(term)))
							? 3
							: 4;

		scored.push({
			rank,
			result: {
				href: doc.href,
				breadcrumb: doc.breadcrumb,
				title: highlight(doc.title, terms),
				titleMatch,
				snippet,
				headings,
				tags: doc.tags ?? [],
			},
		});
	}

	return scored
		.sort(
			(a, b) => a.rank - b.rank || a.result.href.localeCompare(b.result.href),
		)
		.slice(0, MAX_RESULTS)
		.map((s) => s.result);
}
