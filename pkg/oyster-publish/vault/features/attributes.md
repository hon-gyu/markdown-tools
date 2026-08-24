---
title: Attributes
tags: [features]
---

# Djot attributes

Djot attribute specifiers `{.class #id key=value}` attach classes, ids, and
arbitrary attributes to inline spans and to blocks.

## Inline attributes

An attribute block right after an inline element decorates it:

- emphasis: this is *important*{.hl} text
- strong: a **critical**{.danger} warning
- code: run `deploy`{#deploy-cmd .cmd} nightly
- a bare bracket span becomes a `<span>`: [key phrase]{.badge #kp}
- on a link, the class merges with the resolved link class:
  [the Rust hub](rust/index){.cta}

## Block attributes

An attribute line immediately *before* a block decorates that block:

{.lead}
This opening paragraph is rendered as `p.lead` — handy for a standfirst.

{#special .fancy}
### A heading with a custom id and class

The heading above gets `id="special"` and `class="fancy"`, overriding the
auto-generated slug id.
