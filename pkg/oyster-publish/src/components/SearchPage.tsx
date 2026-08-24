import { useEffect, useMemo, useRef, useState } from "react";
import { type SearchDoc, type Segment, searchDocs } from "../lib/search-index";
import "./SearchPage.css";

interface Props {
	docs: SearchDoc[];
	tags: string[];
}

function Highlight({ segments }: { segments: Segment[] }) {
	let offset = 0;
	return segments.map((segment) => {
		const key = `${offset}:${segment.hit ? "hit" : "text"}`;
		offset += segment.text.length;
		return segment.hit ? (
			<mark key={key}>{segment.text}</mark>
		) : (
			<span key={key}>{segment.text}</span>
		);
	});
}

function readLocation() {
	const params = new URLSearchParams(window.location.search);
	return { query: params.get("q") ?? "", tags: params.getAll("tag") };
}

export default function SearchPage({ docs, tags }: Props) {
	const input = useRef<HTMLInputElement>(null);
	const [query, setQuery] = useState("");
	const [selectedTags, setSelectedTags] = useState<string[]>([]);
	const [ready, setReady] = useState(false);

	useEffect(() => {
		const syncFromLocation = () => {
			const state = readLocation();
			setQuery(state.query);
			setSelectedTags(state.tags.filter((tag) => tags.includes(tag)));
			setReady(true);
		};
		syncFromLocation();
		window.addEventListener("popstate", syncFromLocation);
		return () => window.removeEventListener("popstate", syncFromLocation);
	}, [tags]);

	useEffect(() => {
		const focusSearch = (event: KeyboardEvent) => {
			const target = event.target as HTMLElement | null;
			const editing = target?.matches(
				"input, textarea, select, [contenteditable=true]",
			);
			if (
				(event.key === "/" && !editing) ||
				(event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey))
			) {
				event.preventDefault();
				input.current?.focus();
			}
		};
		window.addEventListener("keydown", focusSearch);
		return () => window.removeEventListener("keydown", focusSearch);
	}, []);

	const results = useMemo(
		() => searchDocs(docs, query, { tags: selectedTags }),
		[docs, query, selectedTags],
	);

	function updateUrl(nextQuery: string, nextTags: string[], push = false) {
		const params = new URLSearchParams();
		if (nextQuery.trim()) params.set("q", nextQuery.trim());
		for (const tag of nextTags) params.append("tag", tag);
		const url = `${window.location.pathname}${params.size ? `?${params}` : ""}`;
		window.history[push ? "pushState" : "replaceState"]({}, "", url);
	}

	function submit(event: { preventDefault(): void }) {
		event.preventDefault();
		updateUrl(query, selectedTags, true);
	}

	function toggleTag(tag: string) {
		const next = selectedTags.includes(tag)
			? selectedTags.filter((selected) => selected !== tag)
			: [...selectedTags, tag];
		setSelectedTags(next);
		updateUrl(query, next);
	}

	return (
		<div className="search-page">
			<form onSubmit={submit}>
				<label htmlFor="site-search">Search notes</label>
				<div className="search-page-input">
					<input
						ref={input}
						id="site-search"
						name="q"
						type="search"
						value={query}
						placeholder={'Try links or "whole note"'}
						onChange={(event) => {
							setQuery(event.target.value);
							updateUrl(event.target.value, selectedTags);
						}}
					/>
					<button type="submit">Search</button>
				</div>
				<p className="search-page-hint">
					Use quotes for an exact phrase. Press <kbd>/</kbd> or <kbd>⌘K</kbd> to
					focus search.
				</p>
				{tags.length > 0 && (
					<fieldset>
						<legend>Filter by tag</legend>
						<div className="search-page-tags">
							{tags.map((tag) => (
								<label key={tag}>
									<input
										type="checkbox"
										checked={selectedTags.includes(tag)}
										onChange={() => toggleTag(tag)}
									/>
									{tag}
								</label>
							))}
						</div>
					</fieldset>
				)}
			</form>

			<section aria-live="polite" aria-atomic="false">
				{!ready || !query.trim() ? (
					<p className="search-page-empty">
						Enter a word or quoted phrase to search titles, headings, tags, and
						note text.
					</p>
				) : results.length === 0 ? (
					<p className="search-page-empty">
						No notes match this query and tag selection.
					</p>
				) : (
					<>
						<p className="search-page-count">
							{results.length} {results.length === 1 ? "result" : "results"}
						</p>
						<ol className="search-page-results">
							{results.map((result) => (
								<li key={result.href}>
									<h2>
										<a href={result.href}>
											<Highlight segments={result.title} />
										</a>
									</h2>
									{result.breadcrumb && (
										<p className="search-page-path">{result.breadcrumb}</p>
									)}
									{result.snippet && (
										<p>
											<Highlight segments={result.snippet} />
										</p>
									)}
									{result.headings.length > 0 && (
										<ul className="search-page-headings">
											{result.headings.map((heading) => (
												<li key={heading.slug}>
													<a href={`${result.href}#${heading.slug}`}>
														<Highlight segments={heading.text} />
													</a>
												</li>
											))}
										</ul>
									)}
									{result.tags.length > 0 && (
										<p className="search-page-result-tags">
											{result.tags.map((tag) => `#${tag}`).join(" ")}
										</p>
									)}
								</li>
							))}
						</ol>
					</>
				)}
			</section>
		</div>
	);
}
