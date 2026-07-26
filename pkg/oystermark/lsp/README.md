# oystermark-lsp

Language server for Oystermark vaults.

## Markdown flavor

We use: CommonMark + Github-flavored extensions + Obsidian extensions + djot non-restrictive extensions + our own extensions (struct, etc.)

Extensions are additive. Djot syntax is borrowed as extensions while its
restrictions are not adopted: where djot removes something from Markdown
(indented code blocks, setext headings, CommonMark emphasis flanking, `___`
thematic breaks), the CommonMark behavior is kept.

## Anchors

A `#fragment` is matched against one namespace, in this order; first match wins:

| # | Kind | Written as | Referenced by | Granularity |
|---|---|---|---|---|
| 1 | Heading | `# My Heading` | `[[note#My Heading]]` (heading **text**, not slug) | line |
| 2 | Caret block id | `text ^blk1` | `[[note#^blk1]]` | block |
| 3 | Attribute id | `{#id}` / `[text]{#id}` | `[[note#id]]` | block, or **inline span** |

Attribute ids are author-controlled and stable, and are the only kind that can
pin an arbitrary inline span:

```markdown
{#custom-h}
# My Heading

The [key term]{#kt} is defined here.

{#aside}
> An aside worth linking to.
```

```markdown
See [[my-note#kt]] and [[my-note#aside]]; within the note, [[#My Heading]].
A CommonMark link reaches the same anchors: [the key term](#kt), [aside](#aside).
```

Both link syntaxes reach all three anchor kinds — nothing in resolution is
specific to wikilinks, and nothing is specific to headings. The full 2×3 matrix
is pinned by the expect test *"intra-note: {wikilink, markdown link} x
{heading, block attribute, inline attribute}"* in
[go_to_definition.ml](go_to_definition.ml).

Note: an explicit `{#id}` on a heading *replaces* its generated identifier. The
heading is still reachable by its text (`[[note#My Heading]]`), but not by the
derived slug.

Anchors are collected and resolved in the core (`lib/vault/index.ml`,
`lib/vault/resolve.ml`); the LSP consumes resolved targets and adds no anchor
logic of its own. Spec: [feature-attribute-anchors.mld](docs/feature-attribute-anchors.mld).

## Features

| Feature | Behavior | Spec |
|---|---|---|
| Go to definition | Jumps to a link's target. Inline attribute anchors resolve to line *and* character. | [go-to-definition](docs/feature-go-to-definition.mld) |
| Find references | From a link or an anchor, lists every link resolving to the same target. | [find-references](docs/feature-find-references.mld) |
| Completion | Note names after `[[`; heading texts, block ids and attribute ids after `#`. | [completion](docs/feature-completion.mld) |
| Diagnostics | Unresolved links and fragments; duplicate ids in one file. | [diagnostics](docs/feature-diagnostics.mld) |
| Hover | Preview of the target note or section. | [hover](docs/feature-hover.mld) |
| Document outline | Headings and struct keys as a symbol tree. | [document-outline](docs/feature-document-outline.mld) |
| Inlay hints | Reference counts next to headings and at the top of the file. | [inlay-hints](docs/feature-inlay-hints.mld) |
| Rename | Renames a note and rewrites the links pointing at it. | [rename](docs/feature-rename.mld) |
| Code action | Creates the note behind an unresolved link. | [codeaction](docs/feature-codeaction-create-unresolved-link.mld) |
| Daily notes | Open or create today's / yesterday's / tomorrow's note, and jump to the previous or next existing one. | [daily-notes](docs/feature-daily-notes.mld) |

Daily notes are configured through the client's `initializationOptions`:

```json
{ "dailyNotes": { "format": "YYYY/MM/YYYY-MM-DD", "folder": "journal" } }
```

`format` is a subset of the [moment.js](https://momentjs.com/docs/#/displaying/format/)
tokens and may contain `/` to nest notes in folders; `folder` defaults to the
vault root. Obsidian's own `.obsidian/daily-notes.json` is not read — see
[the reference spec](../../../specification/obsidian/daily-notes.md) for how
Obsidian behaves.

Positions are UTF-16 code units, per the LSP spec — see
[feature-utf16-positions](docs/feature-utf16-positions.mld).
