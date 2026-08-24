---
ai-disclosure: ai-generated
provider/model: openai/gpt-5.6-sol(default)
date: 2026-08-03
---
# Oyster Publish and Obsidian Publish feature comparison

Last reviewed: 2026-08-03

This document compares the current Oyster Publish implementation with the
features advertised and documented for Obsidian Publish. It is both an
inventory of what already exists and a roadmap for closing meaningful gaps.

Status legend:

- ✅ Present
- 🟡 Partial or meaningfully different
- ❌ Missing
- ➕ Oyster-specific enhancement
- N/A Service capability outside a static generator's direct scope

The comparison is grounded in the current repository and these official
Obsidian sources:

- [Obsidian Publish overview](https://obsidian.md/publish)
- [Manage sites and site options](https://obsidian.md/help/Obsidian%2BPublish/Manage%2Bsites)
- [Customize your site](https://obsidian.md/help/Obsidian%2BPublish/Customize%2Byour%2Bsite)
- [Permalinks](https://obsidian.md/help/Obsidian%2BPublish/Permalinks)
- [Publish your content](https://raw.githubusercontent.com/obsidianmd/obsidian-help/master/en/Obsidian%20Publish/Publish%20your%20content.md)

## Summary

Oyster Publish already has a strong static reader: hierarchical navigation,
full-text search, local and global graphs, backlinks, a table of contents,
rich Markdown rendering, and several features beyond Obsidian Publish.

The largest gaps are:

1. Hover previews and stacked pages.
2. Vault attachments and note/section transclusion.
3. SEO and social metadata.
4. Permalinks and redirects.
5. Per-vault presentation and navigation settings.
6. Mobile navigation and a verified accessibility baseline.
7. Publishing filters, dependency closure, and deployment workflow.
8. Analytics, access control, and other hosting integrations.

## Reader experience

| Capability | Status | Oyster Publish today | Remaining gap |
|---|---:|---|---|
| File explorer | ✅ | Hierarchical, collapsible tree with active-page expansion | Core feature is present |
| Search | ✅ | Searches titles, headings, and body text with snippets, highlighting, and keyboard navigation | No advanced query syntax, tag filters, or dedicated search page |
| Local graph | ✅ | Per-note graph in the right rail | Present |
| Global graph | ✅ | Homepage graph and dedicated `/graph`; zoom, drag, scope switching, and expansion | At least comparable to the advertised feature |
| Backlinks | ✅ | Linked-mentions list on each note | No contextual excerpt, occurrence count, or per-reference position |
| Table of contents | ✅ | H2-H4 outline with scroll-spy | Not configurable; H5-H6 are omitted |
| Hover page previews | ❌ | Internal links have no preview | Major reader gap |
| Stacked pages | ❌ | Links replace the current page normally | Major reader gap |
| Breadcrumbs | ➕ | Folder and page breadcrumb trail | Oyster-specific enhancement |
| In-note direction hints | ➕ | `↑N`, `↓N`, `←`, or `→` on links within the current note | Oyster-specific enhancement |
| Heading permalinks | ✅ | Rendered headings link to their anchors | Present |
| Deep-link landing cue | ➕ | A target heading briefly flashes | Oyster-specific enhancement |
| Custom 404 page | ✅ | Keeps navigation and search available | Present |
| User-resizable panels | ➕ | Pointer- and keyboard-resizable, persisted locally | Oyster-specific enhancement |
| Hide/show navigation | ❌ | Navigation is always rendered | No site setting |
| Hide/show search | ❌ | Search is always rendered | No site setting |
| Hide/show graph | ❌ | The per-note graph is always rendered | No site setting |
| Hide/show TOC | ❌ | The TOC is rendered whenever relevant headings exist | No site setting |
| Hide/show backlinks | ❌ | Backlinks are rendered whenever they exist | No site setting |
| Hide page title | 🟡 | Oyster does not synthesize an inline page title; the authored H1 controls it indirectly | No explicit setting |
| Readable line length | 🟡 | Fixed at `48rem` | No full-width or per-site option |
| Strict line breaks | ❌ | Determined by the parser | No site setting |
| Light/dark mode | 🟡 | Automatically follows the system using `light-dark()` | No user toggle or forced light/dark setting |
| Mobile reader | 🟡 | The right rail is hidden below `60rem` | Sidebar needs an explicit drawer/collapse design and mobile visual tests |
| Accessibility | 🟡 | Semantic landmarks, keyboard search, reduced-motion support, and accessible resize handles | No automated Lighthouse or axe target |

Obsidian prominently advertises hover previews, graph view, stacked pages, and
backlinks as its connected-reading features. Oyster has both graph modes and a
basic backlink view, but lacks hover previews and stacked pages.

## Navigation and information architecture

| Capability | Status | Notes |
|---|---:|---|
| Folder-derived navigation | ✅ | Filesystem structure is the taxonomy |
| Custom navigation order | ❌ | Oyster sorts alphabetically |
| Published but hidden page | ❌ | A page cannot be omitted from navigation without being omitted from the site |
| Hidden navigation folder | ❌ | Not supported |
| Arbitrary homepage file | ❌ | The homepage is fixed to root `index.md` |
| Folder index pages | ✅ | `folder/index.md` becomes `/folder` |
| Frontmatter display title | ✅ | Used consistently in navigation, search, graph, backlinks, and browser tabs |
| Tags | 🟡 | Tags reach graph data, but there are no tag pages, visible page tags, tag search, or tag navigation |
| Navigation icons and custom labels | 🟡 | Folder icons and frontmatter titles exist; presentation is otherwise fixed |
| Multiple navigation roots or sections | ❌ | Not configurable |
| Previous/next page navigation | ❌ | Not present |
| Recent or updated pages | ❌ | Not present |

Obsidian supports manual ordering and hiding published items from navigation
without unpublishing them.

## Markdown and Obsidian compatibility

| Capability | Status | Notes |
|---|---:|---|
| Standard Markdown | ✅ | Parsed through oymarkit |
| Wikilinks and display aliases | ✅ | Vault-aware resolution |
| Links to headings | ✅ | Wikilink and Markdown forms |
| Block IDs and block links | ✅ | Rendered and addressable |
| Attribute IDs | ✅ | Rendered and addressable |
| Broken-link styling | ✅ | Unresolved wikilinks remain visible |
| Callouts | ✅ | Includes foldable callout behavior |
| Tables and task lists | ✅ | Supported |
| Footnotes | ✅ | Supported |
| Math and KaTeX | ✅ | Supported |
| Djot attributes, divs, and inline containers | ➕ | Beyond normal Obsidian Publish compatibility |
| MDX files | ➕ | Astro MDX integration is enabled |
| Embedded or transcluded notes | ❌ | `![[note]]` is not rendered as note content |
| Embedded sections and blocks | ❌ | No transclusion |
| Vault images and attachments | ❌ | Only `.md` and `.mdx` enter the collection; linked vault media is not copied or resolved |
| Image sizing syntax | ❌ | No verified Obsidian-style `![[image.png\|300]]` behavior |
| Audio, video, and PDF embeds | ❌ | No attachment pipeline or media viewer |
| Canvas files | ❌ | Only Markdown and MDX become pages |
| Bases | ❌ | No renderer |
| Mermaid diagrams | ❌ | No Mermaid integration |
| Syntax highlighting | 🟡 | Standard code rendering exists, but there is no explicit compatibility fixture or theme setting |
| Obsidian comments | 🟡 | Not covered by a focused fixture or behavior contract |
| External embeds and iframes | 🟡 | No explicit compatibility fixture or security policy |
| Properties display | ❌ | Frontmatter influences the build but is not rendered as a page component |

Attachments are the largest content-fidelity gap. Obsidian's publishing flow
can automatically include linked media and linked notes. Oyster currently
expects manually managed public assets under `.oyster/public`.

## URLs and link durability

| Capability | Status | Notes |
|---|---:|---|
| Stable path-derived routes | ✅ | Slug derivation is centralized |
| Spaces, punctuation, and Unicode filenames | ✅ | Covered by tests |
| Obsidian-like filename resolution | ✅ | Case-insensitive suffix matching with proximity tie-breaking |
| Frontmatter permalink | ❌ | Explicitly ignored |
| Custom page slug | ❌ | The path is the only route source |
| Redirect original path to permalink | ❌ | Not supported |
| Redirect renamed or moved notes | ❌ | No alias-driven redirect generation |
| Multiple historical aliases | ❌ | No redirect manifest |
| Canonical URL | ❌ | No canonical link metadata |
| Explicit trailing-slash policy | 🟡 | Determined by Astro and the static host rather than a documented Oyster policy |

Obsidian supports a `permalink` property and redirects from old full-path
aliases. Oyster deliberately treats paths as the single source of truth, so
permalinks should be introduced as an explicit routing policy rather than
folded into the current slug function invisibly.

## Branding and customization

| Capability | Status | Notes |
|---|---:|---|
| Site name | ✅ | CLI or `.oyster/config.json` |
| Favicon | ✅ | Explicit setting or automatic discovery |
| Site logo or banner | ❌ | No setting or component |
| Custom static assets | ✅ | `.oyster/public/` |
| Per-vault custom CSS | ❌ | A CSS file can be served but is not automatically loaded |
| Per-vault custom JavaScript | ❌ | A JS file can be served but is not automatically loaded |
| Community Publish themes | ❌ | No compatibility layer |
| Theme selection | ❌ | One neutral Astryx shell |
| Typography and color configuration | ❌ | Requires changing engine CSS |
| Custom domain | 🟡 | Static output can be hosted on any domain, but Oyster has no domain configuration or validation |
| Redirect to custom domain | ❌ | Host-specific and not generated |
| Configurable document language | ❌ | `<html lang="en">` is hard-coded |
| Site footer | ❌ | No configuration |
| Custom header or navigation links | ❌ | No configuration |

Obsidian automatically recognizes `publish.css`, `publish.js`, and several
favicon naming conventions. Oyster exposes a general public asset directory
but does not automatically load site-owned CSS or JavaScript.

## SEO and sharing

| Capability | Status | Notes |
|---|---:|---|
| Unique HTML titles | ✅ | Note and site title |
| Meta description | ❌ | No site or per-note description |
| Open Graph metadata | ❌ | No `og:title`, `og:description`, `og:image`, or `og:url` |
| Twitter/X card metadata | ❌ | Not present |
| Per-page social image | ❌ | No schema or rendering |
| Canonical URL | ❌ | Not present |
| Sitemap | ❌ | No sitemap integration |
| `robots.txt` | ❌ | No generated file or no-index setting |
| Per-page `noindex` | ❌ | Not supported |
| Structured data or JSON-LD | ❌ | Not present |
| RSS or Atom feed | ❌ | Not present |
| Search-engine-friendly static HTML | ✅ | Main note content is server-rendered |
| Performance budget | ❌ | No bundle-size or Lighthouse gate |
| Accessibility audit | ❌ | No automated audit |

Obsidian advertises automatic SEO and social cards, with page-level
descriptions, slugs, and images. It also exposes a site-level switch to
discourage search-engine indexing. This is currently Oyster's weakest
public-web category.

## Privacy, analytics, and access

| Capability | Status | Notes |
|---|---:|---|
| Password-protected site | ❌ | Not present |
| Multiple passwords | ❌ | Not present |
| Page-level access policies | ❌ | Not present |
| Google Analytics setting | ❌ | Not present |
| Plausible, Fathom, or generic analytics hook | ❌ | Requires changing the engine |
| Cookie and consent support | ❌ | Not present |
| Privacy-first default | ✅ | No analytics or third-party tracking by default |
| Security headers and CSP | N/A | Left to the static host |
| Private preview deployment | N/A | Left to the static host |

Password protection cannot be implemented securely as a client-side static
site feature alone. It requires supported hosting or authenticated edge/server
integration.

## Authoring and publishing workflow

| Capability | Status | Notes |
|---|---:|---|
| Local development preview | ✅ | `oyster-publish dev` |
| Static production build | ✅ | `oyster-publish build` |
| Alternate vault and output directory | ✅ | CLI flags |
| Publish only `publish: true` notes | ✅ | `--published-only` |
| Treat `publish: false` as exclusion in normal mode | ❌ | Normal mode publishes every note |
| Included-folder rules | ❌ | Not present |
| Excluded-folder rules | ❌ | Not present |
| Per-file publish selection UI | ❌ | Not present |
| New, changed, and unchanged diff | ❌ | Not present |
| Add linked notes automatically | ❌ | Not present |
| Add linked media automatically | ❌ | Not present |
| Safe unpublish and deletion workflow | ❌ | Build output simply reflects current input |
| Publish from Obsidian | ❌ | No Obsidian plugin or integration |
| Publish from mobile | ❌ | No mobile authoring workflow |
| One-click deployment and hosting | N/A | Produces static files; deployment is external |
| Incremental upload | ❌ | Full static build |
| Multiple-site management | 🟡 | The CLI can build any number of vaults, but there is no registry or switcher |
| Team collaboration | N/A | Git or shared storage can be used, but Oyster provides no collaboration service |
| Hosted storage and CDN | N/A | Delegated to the chosen static host |
| Managed support | N/A | Oyster is tooling rather than a hosted SaaS product |

Obsidian's publishing workflow distinguishes new, changed, unchanged, and
removed content; supports included and excluded folders; honors
`publish: true` and `publish: false`; and can select linked notes and media.

## Prioritized roadmap

### 1. Hover previews

High reader value, explicitly advertised by Obsidian, and compatible with the
existing vault index. Preview data should be generated at build time and shown
without fetching and reparsing a whole page.

### 2. Vault attachment pipeline

Copy published or referenced attachments, resolve image paths, preserve safe
relative URLs, and then add Obsidian image-sizing behavior. This is
foundational for publishing real-world vaults.

### 3. Note and section transclusion

Reuse oystermark's embed and vault-resolution behavior for whole notes,
headings, and blocks. Define recursion, cycle, and maximum-depth policies
explicitly.

### 4. SEO and social metadata

Add a site URL, language, site and per-page descriptions, social images,
canonical URLs, Open Graph and Twitter metadata, sitemap generation, and robots
controls.

### 5. Permalinks and redirects

Add an explicit route and redirect layer while preserving filesystem paths as
the internal note identity. Generate redirect pages or a host-neutral redirect
manifest from permalinks and full-path aliases.

### 6. Per-vault presentation settings

Add logo, theme mode, a reader light/dark toggle, readable width, component
visibility, custom CSS, and optional custom JavaScript. Custom JavaScript
should be an explicit opt-in because it changes the site's security model.

### 7. Navigation policy

Support explicit sibling order and pages or folders that remain published but
hidden from the explorer.

### 8. Mobile shell and accessibility verification

Add a collapsible navigation drawer, a mobile route to graph and TOC features,
mobile end-to-end tests, axe checks, and a Lighthouse accessibility target.

### 9. Publishing filters and dependency closure

Honor explicit `publish: false`, add included and excluded folder policies,
and optionally close the selected set over linked notes and attachments.

### 10. Stacked pages

Implement link-driven horizontal panes with usable history, keyboard behavior,
deep-linking, mobile fallback, and a clear interaction with ordinary browser
navigation.

### 11. Analytics and deployment hooks

Prefer generic, documented head and script hooks plus deployment adapters over
hard-wiring one analytics provider.

### 12. Access control

Design password protection only alongside supported deployment targets. Do
not present client-side encrypted or JavaScript-only gates as secure access
control.

## Milestones

Two useful parity milestones emerge from the inventory:

### Reader parity

- Hover previews
- Stacked pages
- Complete attachment handling
- Note, heading, and block transclusion
- Verified mobile navigation

### Publishing parity

- SEO and social metadata
- Permalinks and redirects
- Site appearance and component settings
- Navigation ordering and hiding
- Publishing filters and linked-content closure
- Documented deployment, analytics, and access-control integrations

Oyster already has enough of the reader shell that this is not a ground-up
parity effort. Most missing work is concentrated in content closure, site
policy, and public-web metadata rather than basic navigation.
