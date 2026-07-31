---
title: Inlay hints
---

# Inlay hints

Two kinds of hint, both drawn by the editor as virtual text — you cannot
select them, and they are not in the file.

One count sits at the very top of the file, on line 0 above the frontmatter:
every link in the vault that resolves to this note, whatever fragment it
named.

## Reference counts

A count after a heading is how many links in the vault land on *that heading*,
not on the note. [[links]] points at this section and the next one; the links
under [[#Link direction]] add to those counts too, since a note's links to its
own headings are references like any other.

Find references on a heading lists what its count counted. A heading nothing
points at carries no hint at all — a count of zero would be noise.

## Link direction

A link whose target is in this same note gets an arrow and the number of lines
to it — the two things a list of near-identical `[[#…]]` tokens otherwise
hides:

- [[#Reference counts]] points back up
- [[#Where the arrows stop]] points down
- [[#^caret-line]] points at a block, not a heading
- [[#pivot]] points at an inline span, further down

The arrow carries the direction, so the number is always a plain distance:
`↑6`, never `↑-6`.

Two links on one line each get their own arrow, beside their own link:
[[#Reference counts]] and [[#Where the arrows stop]]. That is why the hint
sits after the link rather than at the end of the line — one arrow at the end
of this line could belong to either.

A target on the *same line* is the one case with no distance to report, so the
arrow turns sideways instead. The line below holds a span and a link on either
side of it:

[[#pivot]] before the [pivot]{#pivot} and [[#pivot]] after it.

Only an inline span can be a same-line target — a heading or a caret id owns
its whole line.

This paragraph is named by a caret instead. ^caret-line

## Where the arrows stop

Silence, not an empty hint, wherever there is no direction to give:

- cross-note links — [[anchors]], [[links#Wikilinks]] — the arrow would be
  about a file you are not looking at
- unresolved links: [[no-such-note-here]]
- a link to this note as a whole: [[inlay-hints]]

## Turning them off

`inlayHints.linkDirection` in `oysterlsp.json` switches the arrows off on
their own; the reference counts are unaffected and have no switch. Set it to
`false`, restart the server, and only the counts above remain.
