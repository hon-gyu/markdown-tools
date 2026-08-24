---
title: Math and Footnotes
tags: [features]
---

# Math, footnotes, and block references

## Math

Inline math renders with KaTeX: the Pythagorean theorem is $a^2 + b^2 = c^2$.
Display math sits on its own line:

$$
\int_0^1 x \, dx = \frac{1}{2}
$$

Euler's identity is a personal favourite. ^euler

The block above carries the id `euler`, so [[features/index]] can link straight
to it with `[[math-and-footnotes#^euler]]`.

## Footnotes

Footnotes collect at the bottom of the page with backreferences.[^why] You can
reference the same note more than once,[^why] and a footnote body may itself
contain formatting and links.[^rich]

[^why]: Because a footnote keeps an aside out of the main flow.
[^rich]: Footnote bodies support **markdown**, `code`, and links like
    [[async]].
