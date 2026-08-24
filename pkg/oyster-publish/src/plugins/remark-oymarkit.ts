// Parser replacement: make the unified/remark pipeline parse markdown with the
// oymarkit OCaml parser instead of micromark/remark-parse.
//
// unified's parser is just `this.parser`: remark-parse sets it, and a later
// plugin can overwrite it with any `(document, file) => mdastRoot` function.
// Astro applies remark-parse first and user remark plugins after, so assigning
// `this.parser` here wins. Everything downstream of parsing (remark transforms,
// remark-rehype, Shiki highlighting, the TOC) is untouched — it just sees an
// mdast tree that oymarkit produced.
//
// Only `.md` goes through this: `@astrojs/mdx` keeps its own MDX parser.
import type { Plugin } from "unified";
import { parseToMdast } from "../lib/oystermark/index.ts";

const remarkOymarkit: Plugin = function () {
	this.parser = (document: string) => parseToMdast(document) as never;
};

export default remarkOymarkit;
