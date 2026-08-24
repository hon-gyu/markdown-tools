import { Icon } from "@astryxdesign/core/Icon";
import { SideNav, SideNavHeading } from "@astryxdesign/core/SideNav";
import { TextInput } from "@astryxdesign/core/TextInput";
import { TreeList, type TreeListItemData } from "@astryxdesign/core/TreeList";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral";
import {
	DocumentTextIcon,
	FolderIcon,
	MagnifyingGlassIcon,
} from "@heroicons/react/24/outline";
import { type KeyboardEvent, type ReactNode, useMemo, useState } from "react";
import { type SearchDoc, type Segment, searchDocs } from "../lib/search-index";
import type { TreeNode } from "../lib/tree";
import "./OysterNav.css";

interface Props {
	siteTitle: string;
	tree: TreeNode[];
	pathname: string;
	searchCorpus: SearchDoc[];
}

// Notes are the common case in the explorer, so their repeated document icon
// adds more noise than information. Keep this as an explicit switch in case a
// site with a more mixed tree wants the icons back; folders always keep theirs.
const SHOW_NOTE_ICONS = false;

const norm = (path: string) => path.replace(/\/+$/, "") || "/";

function containsPath(node: TreeNode, pathname: string): boolean {
	return (
		norm(node.urlPath) === pathname ||
		node.children.some((child) => containsPath(child, pathname))
	);
}

function toTreeItems(nodes: TreeNode[], pathname: string): TreeListItemData[] {
	return nodes.map((node) => {
		const children = toTreeItems(node.children, pathname);
		const hasChildren = children.length > 0;
		return {
			id: node.urlPath,
			label: node.title,
			href: node.hasPage ? node.urlPath : undefined,
			isSelected: node.hasPage && norm(node.urlPath) === pathname,
			isExpanded: hasChildren && containsPath(node, pathname),
			startContent:
				hasChildren || SHOW_NOTE_ICONS ? (
					<Icon icon={hasChildren ? FolderIcon : DocumentTextIcon} size="xsm" />
				) : undefined,
			children: hasChildren ? children : undefined,
		};
	});
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

export default function OysterNav({
	siteTitle,
	tree,
	pathname,
	searchCorpus,
}: Props) {
	const current = norm(pathname);
	const items = useMemo(() => toTreeItems(tree, current), [tree, current]);
	const [query, setQuery] = useState("");
	const [active, setActive] = useState(-1);
	const results = useMemo(
		() => (query.trim() ? searchDocs(searchCorpus, query.trim()) : []),
		[query, searchCorpus],
	);

	const links = results.flatMap((result) => [
		result.href,
		...(result.snippet ? [result.href] : []),
		...result.headings.map((heading) => `${result.href}#${heading.slug}`),
	]);

	function onSearchKeyDown(event: KeyboardEvent) {
		if (links.length === 0) return;
		if (event.key === "ArrowDown" || event.key === "ArrowUp") {
			event.preventDefault();
			const direction = event.key === "ArrowDown" ? 1 : -1;
			setActive((value) => (value + direction + links.length) % links.length);
		} else if (event.key === "Enter" && active >= 0) {
			window.location.href = links[active];
		} else if (event.key === "Escape") {
			setQuery("");
			setActive(-1);
		}
	}

	let linkIndex = -1;
	const resultPanel: ReactNode = query.trim() ? (
		<div className="oyster-search-results" role="listbox">
			{results.length === 0 ? (
				<div className="oyster-search-empty">No matches</div>
			) : (
				results.map((result) => (
					<div className="oyster-search-group" key={result.href}>
						<a
							className={
								"oyster-search-item oyster-search-title" +
								(++linkIndex === active ? " is-active" : "")
							}
							href={result.href}
						>
							<Highlight segments={result.title} />
						</a>
						{result.snippet && (
							<a
								className={
									"oyster-search-item oyster-search-snippet" +
									(++linkIndex === active ? " is-active" : "")
								}
								href={result.href}
							>
								<Highlight segments={result.snippet} />
							</a>
						)}
						{result.headings.map((heading) => (
							<a
								className={
									"oyster-search-item" +
									(++linkIndex === active ? " is-active" : "")
								}
								href={`${result.href}#${heading.slug}`}
								key={heading.slug}
							>
								<span className="oyster-search-label">
									<Highlight segments={heading.text} />
								</span>
								<span className="oyster-search-badge">H</span>
							</a>
						))}
						{result.breadcrumb && (
							<div className="oyster-search-path">{result.breadcrumb}</div>
						)}
					</div>
				))
			)}
		</div>
	) : null;

	return (
		<Theme theme={neutralTheme}>
			<SideNav
				className="oyster-side-nav"
				header={<SideNavHeading heading={siteTitle} headingHref="/" />}
				topContent={
					<search className="oyster-search" onKeyDown={onSearchKeyDown}>
						<TextInput
							label="Search page or heading"
							isLabelHidden
							size="sm"
							startIcon={MagnifyingGlassIcon}
							placeholder="Search page or heading…"
							value={query}
							onChange={(value) => {
								setQuery(value);
								setActive(-1);
							}}
							hasClear
						/>
						{resultPanel}
					</search>
				}
				resizable={{
					defaultWidth: 289,
					minWidth: 190,
					maxWidth: 460,
					autoSaveId: "oyster-sidebar",
				}}
			>
				<TreeList items={items} density="compact" />
			</SideNav>
		</Theme>
	);
}
