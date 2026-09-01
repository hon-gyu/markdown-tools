---
title: Sourdough Loaf
tags: [bread, weekend]
flour: 500
created: 2026-01-15
---
# Sourdough Loaf

A long, slow bake. Build the levain from [[starter]] the night before.

## Baker's percentages

The build computes these from the block below, so the note and the table can
never drift apart.

{#hydration}
```python
import json

flour, water, salt = 500, 350, 10
print(
    json.dumps(
        {
            "hydration": {
                "flour": flour,
                "water": water,
                "salt": salt,
                "percent": round(water / flour * 100),
            }
        }
    )
)
```
