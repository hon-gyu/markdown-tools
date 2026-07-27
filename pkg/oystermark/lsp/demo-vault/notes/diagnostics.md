---
title: Diagnostics
---

# Diagnostics

Everything below is wrong on purpose. This is the only note in the vault that
should show squiggles.

## Unresolved link

[[nowhere]] — the code action on it creates `nowhere.md` and the link resolves.

## Unresolved fragment

[[anchors#not-a-heading]] — quiet under the default `fallback`, a diagnostic
under `strict`.

## Duplicate ids

{#twice}
Two blocks in one file claiming the same id. Resolution picks the first;
both are reported.

{#twice}
The second one.

## Unknown command

```oysterlsp
daily/today
daily/yesterdya
```

The misspelled line is reported. Without that, a typo would be inert, and
inert looks like unimplemented.
