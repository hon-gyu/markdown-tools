---
title: Features
tags: [meta, features]
---

# Markdown features

This folder is a live test of the extensions the oymarkit parser understands.
Each note renders a family of syntax so you can eyeball the output (and so the
build fails loudly if a feature regresses).

- [[callouts-and-divs]] — Obsidian callouts, djot divs, strikethrough, and the
  curly inline containers (highlight / super- / subscript).
- [[attributes]] — djot inline and block attributes (`{.class #id key=val}`).
- [[math-and-footnotes]] — KaTeX math, footnotes, and block references.
- [[tables-and-tasks]] — GFM tables and task lists.
- [[link-directions]] — rendered direction hints on links within the current
  note.
- [[media]] — vault attachment resolution, generated media URLs, image sizing,
  and missing-attachment presentation.
- [[transclusion]] — whole-note, heading, block, same-note, nested, and circular
  note embeds.

Everything here is plain `.md`; there is no MDX. The reference back to a specific
block lives at [[math-and-footnotes#^euler]].
