---
title: Table of contents
---

# Table of contents

::: toc
- [Table of contents](#table-of-contents)
  - [Getting one](#getting-one)
  - [Why a div and not marker comments](#why-a-div-and-not-marker-comments)
  - [When it goes stale](#when-it-goes-stale)
  - [What ends up in the list](#what-ends-up-in-the-list)
:::

The list above is generated. It lives in a `toc` div, and that div is the
whole trick: it tells the server which part of the note it owns, so it can say
when that part has stopped being true.

## Getting one

Put the cursor anywhere outside a `toc` div and take **Insert table of
contents** from the code-action menu. The fences and the list are inserted at
the cursor's line.

The action is offered everywhere else too — a note may want a second one — and
inserting into a note with no headings gives you an empty div that fills in as
the note grows.

## Why a div and not marker comments

`doctoc` and `markdown-toc` delimit their tables with a pair of HTML comments.
This vault has real divs, so it uses one.

A div's body is ordinary block content: the list is a list, and its links
resolve like every other link here. A raw `<div>` would not manage that —
CommonMark stops reading Markdown inside an HTML block until a blank line — so
the meaning of the body would hinge on blank lines you have to remember. And
`::: toc` renders to something a stylesheet can reach, where a comment renders
to nothing.

The cost is that you can see it. A comment is invisible in the source and in
the output; this is invisible in neither.

## When it goes stale

Add a heading, rename one, delete one: the opening fence gets a warning,
`table of contents is out of date`, and **Update table of contents** appears
as its quick fix. The fix rewrites what is between the fences and never the
fences themselves, so an update cannot lose the div.

Whitespace is forgiven — trailing spaces, a blank line above or below the
list. Nothing else is: a reordered entry or an edited link text is a
difference, which is the point.

Try it: delete a line from the list above and watch the fence light up.

## What ends up in the list

One entry per heading, linking to its identifier rather than its text, so a
heading with an explicit `{#id}` links to the id the author will keep. See
[[anchors]] for what those identifiers are.

Indentation counts the levels this note actually uses, not the number in the
`#`. A note whose headings start at `##` is flush left, and a level skipped in
the note costs no indentation in the list.

A `:::` on its own is not this feature's business — it closes whichever div it
belongs to:

::: warning
This warning has nothing to do with the table of contents, and neither its
fence nor its heading-free body is reported.
:::
