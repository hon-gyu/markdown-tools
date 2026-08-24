---
title: Tables and Tasks
tags: [features]
---

# Tables and task lists

## Tables

GFM pipe tables with per-column alignment become a real `<table>`:

| Feature      | Syntax           | Renders to        |
| :----------- | :--------------: | ----------------: |
| Callout      | `> [!note]`      | `blockquote`      |
| Div          | `::: class`      | `div`             |
| Inline math  | `$x$`            | KaTeX span        |
| Footnote     | `[^1]`           | `sup` + section   |

## Task lists

Checkbox items carry their checked state:

- [x] parse markdown with oymarkit
- [x] emit mdast
- [ ] wire up the remaining backends
- [ ] write the docs
