---
title: In-note link directions
tags: [features, links]
---

# In-note link directions

Links to a place in the current note show where their target is relative to
the link. The annotation is generated while rendering and is not part of the
Markdown source.

This wikilink points to [[#Further down]], and this Markdown link points to
[the block below](#direction-block).

An inline attribute can sit on the same line: [this target]{#inline-target} is to the left of [[#inline-target]].

## Further down

The first link points here. This paragraph is the other target. ^direction-block

From down here, [[#In-note link directions]] points back to the top.
