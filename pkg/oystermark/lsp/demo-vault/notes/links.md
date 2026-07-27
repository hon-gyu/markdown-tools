---
title: Links
---

# Links

Every link form, all pointing into [[anchors]]. Go to definition on each;
hover for a preview of what it lands on.

## Wikilinks

- Whole note: [[anchors]]
- Heading: [[anchors#Headings]]
- Nested heading: [[anchors#A nested heading]]
- Block id: [[anchors#^first-law]]
- Attribute id: [[anchors#stable-id]]
- Inline span: [[anchors#key-term]] — lands mid-line
- Explicit heading id: [[anchors#custom-heading-id]]
- Display text: [[anchors#Block ids|the caret form]]

## Markdown links

The same anchors, no wikilink syntax involved: [note](notes/anchors.md),
[heading](notes/anchors.md#Headings), [span](notes/anchors.md#key-term).

## Within this note

`[[#Wikilinks]]` reaches [[#Wikilinks]]; the markdown form reaches
[this section](<#Markdown links>) — a destination with a space needs the angle
brackets, or it is not a link at all.

## Unresolved

[[no-such-note]] is a diagnostic, and the code action on it creates the note.

[[anchors#no-such-heading]] is an unresolved fragment: under the default
`fallback` it lands on the file and stays quiet, under `strict` it is a
diagnostic. Set `goToDefinition.unresolvedFragment` in `oysterlsp.json` to see
both.

## Completion

Type `[[` on the line below for note names, then `#` for that note's anchors.
Inside `[[anchors#` the whole anchor namespace is offered — headings, caret
ids, attribute ids.

## Also here

[[rename-me]], [[command-panel]], [[journal-index]].
