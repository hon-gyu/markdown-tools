---
title: Anchors
---

# Anchors

The target note: most links in this vault point somewhere inside it. Jumping
from them is [[links]].

## Headings

Reachable by text, not slug: `[[anchors#Headings]]`.

Every heading here has a blank line under it. A heading runs to the next blank
line, so removing it folds this paragraph into the heading and the link above
stops matching.

### A nested heading

Nesting is what document outline renders as a tree.

## Block ids

A caret at the end of a line names that block. ^first-law

Reachable as `[[anchors#^first-law]]`.

## Attribute ids

{#stable-id}
An attribute id is written on the line above the block it names, and is the
only anchor you control: heading text changes with the prose, a caret id needs
the end of a line.

The [key term]{#key-term} is an inline span — `[[anchors#key-term]]` lands on
the phrase, at the character. The other two anchor kinds are line-granular.

{#aside}
> Any block takes an id, callouts included.

{#custom-heading-id}
## An explicit id on a heading

Still reachable by text, and now also as `[[anchors#custom-heading-id]]`.

Pandoc's trailing form (`## Heading {#id}`) is not read here: no anchor is
recorded and the heading text keeps a trailing space, so the by-text link
breaks too.

## Here

Find references on any heading above. Inlay hints count them, per heading and
for the whole file at line 0. Code actions offer *Insert oysterlsp command
block*, since this note has none.
