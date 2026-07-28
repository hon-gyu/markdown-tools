# Struct Specification

- date: April 8

Struct is a syntax extension that restructures the document tree based on colon-suffixed labels. A colon at the end of a list item or paragraph declares that the following contiguous content is its children, causing the `Cmarkit.Doc` tree to be rewritten with new parent-child relationships.

## Syntax

A **keyed node** is a list item or paragraph whose text content ends with `:` (a single colon, excluding trailing whitespace).

```
- foo:          ← keyed list item
foo:            ← keyed paragraph
- foo: bar:     ← "foo:" is parent, "bar:" is a nested keyed node
- foo\: bar:    ← "foo: bar" is the label (escaped colon), keyed
- foo           ← not keyed (no trailing colon)
```

### Escaped Colons

A colon preceded by a backslash (`\:`) is not a key delimiter. It is treated as literal text. Only an unescaped trailing colon makes a node keyed.

```
- foo\: bar:    ← label is "foo: bar", keyed
- foo\: bar     ← label is "foo: bar", NOT keyed
- foo: bar:     ← "foo:" is parent of "bar:"
```

### Inline Keying (Colon Chains)

When a list item or paragraph contains multiple unescaped colons, each colon-terminated segment introduces a nesting level. The first segment is the outermost parent, and the last segment is the innermost keyed node.

`````markdown
- foo: bar:
  - baz
`````

```
List
└── KeyedListItem "foo"
    └── KeyedListItem "bar"
        └── List
            └── ListItem "baz"
```

`foo:` is the parent of `bar:`, and `bar:` is the parent of `baz`.

## Tree Restructuring Rules

### Rule 1: Keyed list item with indented content

Already parsed as children by CommonMark. No transform needed.

`````markdown
- foo:
  - bar
  - baz
`````

```
List
└── KeyedListItem "foo"
    └── List
        ├── ListItem "bar"
        └── ListItem "baz"
```

### Rule 2: Keyed node with empty continuation

If the next element after a colon-suffixed node is blank (empty), the colon is not structural. The node remains a regular `ListItem` or `Paragraph` with the colon preserved as literal text.

`````markdown
- foo:

bar
`````

```
List
└── ListItem "foo:"
Paragraph "bar"
```

`bar` is not a child of `foo:`. The blank line means the colon has no effect — it's just punctuation.

This applies equally to a list item followed by a blank line *inside* its own list. A blank line between items makes the list loose; the resulting trailing blank is list layout, not content, and is never claimed as a body.

`````markdown
- foo:

- bar
`````

```
List (loose)
├── ListItem "foo:"
└── ListItem "bar"
```

`foo:` does not become a keyed node with an empty body — it is not keyed at all.

### Rule 3: Keyed list item with contiguous block content

Content that is contiguous (no blank line) after a keyed list item becomes its children, even if CommonMark would not normally nest it. The content does **not** need to be indented.

`````markdown
- foo:
```
bar
```
`````

```
List
└── KeyedListItem "foo"
    └── CodeBlock "bar"
```

In standard CommonMark, the unindented code block would not be a child of the list item. Struct overrides this: the colon claims the following contiguous content regardless of indentation.

### Rule 4: Keyed paragraph with following list

A bare keyed paragraph reparents the immediately following contiguous content as its children.

`````markdown
foo:
- bar
- baz

bee
`````

Before transform (CommonMark parse):
```
Paragraph "foo:"
List
├── ListItem "bar"
└── ListItem "baz"
Paragraph "bee"
```

After transform:
```
KeyedBlock "foo"
└── List
    ├── ListItem "bar"
    └── ListItem "baz"
Paragraph "bee"
```

`bee` is not a child of `foo:` — the blank line breaks the scope.

### Rule 5: Keyed paragraph with contiguous blocks

A keyed paragraph claims all immediately following contiguous blocks (no blank line separation) as children.

`````markdown
foo:
- bar
- baz
some text
`````

After transform:
```
KeyedBlock "foo"
├── List
│   ├── ListItem "bar"
│   └── ListItem "baz"
└── Paragraph "some text"
```

### Rule 6: Nesting

Keyed nodes can nest, forming deeper trees.

`````markdown
foo:
- bar:
  - baz
- qux
`````

```
KeyedBlock "foo"
└── List
    ├── KeyedListItem "bar"
    │   └── List
    │       └── ListItem "baz"
    └── ListItem "qux"
```

Here `qux` is both a child of `foo:` and a sibling of `bar:`.

## Scope Termination

A keyed node's scope (the content it claims as children) ends when:

1. **Blank line** — a blank line after the keyed node terminates its scope
2. **End of parent block** — the enclosing block's boundary terminates scope
3. **Empty next element** — if the immediately next element is empty/blank, no children are claimed (Rule 2)

## Constraints

- A keyed node's label **cannot contain a hard break**. The colon must be on the same inline span as the rest of the label.

## Interaction with Other Extensions

### Wikilinks (separate layer)

Struct operates at the tree structure level only. Cross-referencing nodes via wikilinks (`[[foo]]`) is a separate layer that operates after struct transformation. It expresses graph relationships (identity, equivalence) on top of the tree that struct produces.

```markdown
- foo: ^node-foo
  - bar

- elsewhere:
  - references [[foo]]
```

Struct builds the tree; links build the graph.

### Block Identifiers

A block identifier (`^id`) is a terminal suffix of a paragraph or list item. Its interaction with keying is governed by a single rule:

> A value segment whose entire content is a block-id marker is an **empty value**.

The marker is consumed as the keyed node's identifier rather than becoming its value. The node then behaves in every respect like a bare `foo:` — in particular, it claims following contiguous content as children. The identifier names the node *and* its subtree, in the manner of a YAML anchor.

`````markdown
foo: ^x
- bar
- baz
`````

```
KeyedBlock "foo" (id = x)
└── List
    ├── ListItem "bar"
    └── ListItem "baz"
```

Without this rule `^x` would be `foo`'s value, and — a value being present — the list would remain a sibling rather than a child.

#### Non-empty values

A marker terminating a non-empty value is an ordinary block identifier. It identifies the node, but the value remains non-empty, so no content is claimed. The marker stays part of the value's content, as it does in an ordinary paragraph.

`````markdown
foo: v ^x
- bar
`````

```
KeyedBlock "foo" (id = x)
└── Paragraph "v ^x"
List
└── ListItem "bar"
```

#### Markers that are not identifiers

The conditions on block identifiers still apply in full. A marker that is escaped, or not a terminal suffix, is literal text and yields no identifier — and therefore does not empty the value.

```
foo: \^x        ← value is the literal "^x", no identifier
foo: ^x extra   ← value is the literal "^x extra", no identifier
```

#### Chains

A chain is written as a single paragraph (or list item), and a block identifier names the block it terminates. The block that paragraph becomes is the outermost keyed node, so the identifier attaches to the **outermost** node. This holds whether or not the value is empty.

`````markdown
foo: bar: ^x
- baz
`````

```
KeyedBlock "foo" (id = x)
└── KeyedBlock "bar"
    └── List
        └── ListItem "baz"
```

Note that the marker's two effects land on different nodes: it is consumed from the *innermost* value — which is what empties that value and makes `baz` a child of `bar` — while the identifier it yields names the *outermost* node. Consequently an interior node of a chain cannot be named directly; to name one, break the chain so that the intended node is the outermost of its own paragraph or item.

`````markdown
foo:
- bar: ^x
  - baz
`````

```
KeyedBlock "foo"
└── List
    └── KeyedListItem "bar" (id = x)
        └── List
            └── ListItem "baz"
```

#### Empty continuation

Rule 2 is unaffected. An id-only value with no content to claim is not structural: the node is not keyed, and the colon and the marker both remain literal text. The identifier is still attached, exactly as it would be for any paragraph.

`````markdown
foo: ^x

bar
`````

```
Paragraph "foo: ^x" (id = x)
Paragraph "bar"
```

The same holds at end of input: a document consisting of `foo: ^x` alone is a plain paragraph carrying the identifier `x`.

## Implementation

Struct is implemented as a post-parse `Cmarkit.Doc` transformation:

1. Parse the document normally with cmarkit (+ existing oystermark extensions)
2. Walk the AST, identify colon-suffixed paragraphs and list items
3. Rewrite the tree: reparent following contiguous blocks as children of keyed nodes
4. The result is a valid `Cmarkit.Doc` with restructured parent-child relationships
