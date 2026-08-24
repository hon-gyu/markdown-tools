---
title: Vault attachments and media
tags: [features, media]
date: 2026-08-03
---

# Vault attachments and media

Vault attachments are resolved by their vault path and copied only when a
routed note references them. Generated URLs use a separate `oyster-assets`
namespace rather than the vault's deliberately public `.oyster/public` folder.

## Obsidian image embed

The numeric alias controls the rendered width:

![[diagram with spaces.svg|300]]

## Markdown image

Ordinary relative Markdown paths use the same indexed attachment:

![The vault media pipeline](./media/diagram%20with%20spaces.svg)

## Missing attachment

Missing files are marked separately from unresolved note links:

![[missing-image.png]]
