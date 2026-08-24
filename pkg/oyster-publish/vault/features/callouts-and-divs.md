---
title: Callouts and Divs
tags: [features]
---

# Callouts and divs

## Callouts

An Obsidian callout is a blockquote whose first line is a `[!kind]` header. It
becomes a `blockquote.callout` carrying `data-callout`, with the title and body
split into `.callout-title` / `.callout-content`.

> [!note] A note callout
> The body can contain **bold**, `code`, and a [[async|wikilink]].

> [!warning]
> Without an explicit title the kind name is used as the heading.

> [!tip]+ Foldable, open by default
> A `+` after the kind marks it foldable-open (`-` marks foldable-closed); the
> fold state rides along as a data attribute.

## Divs

A djot `:::` fence is a block container with an optional class — it renders as a
plain `<div class="…">`, so you can hang your own styling off it.

::: warning
This whole block is a `div.warning`. Divs can hold any block content, including
lists:

- one
- two
:::

To give a div an id or extra attributes, precede it with a block attribute line
(see [[attributes]]):

{#callout-demo .callout-ish}
::: info
A `div.info` wrapped in an outer `div#callout-demo.callout-ish`.
:::

## Strikethrough and inline containers

Plain GFM ~~strikethrough~~ works, as do the curly inline containers:
H{~2~}O is a subscript, E = mc{^2^} a superscript, and {=this is highlighted=}.
