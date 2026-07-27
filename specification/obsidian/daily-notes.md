# Daily Notes

Reference specification of Obsidian's **Daily notes** core plugin: its
settings, the path it computes for a given date, and the inverse — how a file
path is parsed back into a date.

Sources, all verified rather than recalled:

- Obsidian 1.13.3 application bundle
  (`~/Library/Application Support/obsidian/obsidian-1.13.3.asar`), the daily
  notes core plugin;
- the Obsidian CLI (`/Applications/Obsidian.app/Contents/MacOS/obsidian`,
  `daily*` commands), probed against a real vault;
- `.obsidian/daily-notes.json` from two live vaults.

The public plugin API (`vendor/obsidian-api/obsidian.d.ts`, 1.12.3) exposes
*nothing* about daily notes — it is an internal core plugin, reachable only via
`app.internalPlugins.getEnabledPluginById("daily-notes")`. So there is no
vendor-blessed schema; what follows is the observed behavior.

## Settings

Stored in `.obsidian/daily-notes.json`. Every key is optional, and the file is
absent entirely until a setting is changed:

| Key | Type | Default | Settings-tab label |
|---|---|---|---|
| `format` | string, a [moment.js format](https://momentjs.com/docs/#/displaying/format/) | `YYYY-MM-DD` | Date format / Custom format |
| `folder` | string, vault-relative folder path | app's "default location for new notes" | New file location |
| `template` | string, vault-relative file path | none | Template file location |

A real example (`format` only, the other keys never set):

```json
{
  "format": "YYYY/MM/YYYY-MM-DD"
}
```

`autorun` is legacy: on load the plugin migrates it to the app-level
`openBehavior: "daily"` config and deletes the key.

The settings tab shows a dropdown of preset formats plus a `custom` entry; the
choice is not itself persisted, only the resulting `format` string.

### Format validation

A format is rejected by the settings UI when any of:

1. it starts with `/`;
2. `moment().format(f)` contains characters illegal in a filename;
3. it does not round-trip: `moment(moment().format(f), f, true).isValid()` is
   false (strict parsing).

Rule 3 is the important one — the format must be *invertible*, because the
prev/next commands parse filenames back into dates with the same format.

## Path computation

`getDailyNote(date?)`, decoded from the bundle:

```
date   ← date ?? now
name   ← date.format(format)        // failure ⇒ notice, abort
name   ← name.trim()
parent ← folder is a non-empty string
           ? vault folder at normalizePath(folder)   // not a folder ⇒ notice, abort
           : fileManager.getNewFileParent("")        // app's new-note location
path   ← parent prefix + name + ".md"
existing ← vault.getAbstractFileByPathInsensitive(path)
  existing is a file      ⇒ return it
  existing is a folder    ⇒ abort
  nothing                 ⇒ create it (see below)
```

Consequences worth naming:

- **The format may contain `/`.** `YYYY/MM/YYYY-MM-DD` yields
  `2026/07/2026-07-26.md`; intermediate folders are created on demand. Verified
  by `obsidian daily:path` on a vault with that format, which returns
  `2026/07/2026-07-26.md`.
- **Lookup is case-insensitive** (`getAbstractFileByPathInsensitive`), so an
  existing `2026-07-26.md` is reused even if the format would produce different
  casing.
- **An unset `folder` does not mean vault root**; it means the app's "default
  location for new notes", which is separately configurable (and *does* default
  to the root).
- The name is trimmed, so a format with trailing whitespace is tolerated.

### Creation

- With `template` set: the path is normalized, `.md` is appended when it has no
  extension, and the file must exist (otherwise notice + abort). Its content is
  read and run through the template variable resolver with `title` bound to the
  computed note name, then written to the new note.
- Without: an empty note is created.

## Reverse: path → date

`iterateDailyNotes` walks the daily-note folder recursively and, for each `.md`
file, takes the path *relative to that folder*, strips the extension, and
parses it with `moment(rel, format, true)` — strict. Valid parses are daily
notes; everything else is ignored.

Two asymmetries with `getDailyNote`:

- it uses `getFolder()`, which falls back to the **vault root** when `folder` is
  unset — not to the app's new-note location;
- it is the only place a daily note is *recognized*, so recognition is
  round-trip-based: a file is a daily note iff its relative path strictly parses
  under the current format.

## Commands

| Command id | Name | Behavior |
|---|---|---|
| `daily-notes` | Open today's daily note | `getDailyNote()` — **creates** the note when missing, then opens it |
| `daily-notes:goto-prev` | Open previous daily note | previous **existing** daily note strictly before the current file's date |
| `daily-notes:goto-next` | Open next daily note | next **existing** daily note strictly after it |

Note what prev/next are *not*: they are not "yesterday" and "tomorrow". They
are enabled only when the currently active file itself parses as a daily note
(`getCurrentFileDateTimestamp()`), they never create anything, and they skip
gaps — with notes on the 3rd and the 10th, prev from the 10th lands on the 3rd.
When there is nothing to go to, the user gets "There's no daily note before
this one."

There is no built-in command for an arbitrary date, for yesterday, or for
tomorrow.

Beyond the command palette, the plugin also contributes: a ribbon icon, an
"Insert link into daily note" file-menu item, and a text-menu item that appends
selected text to today's note.

## CLI surface

Obsidian 1.13's CLI (enabled per-install; `"cli": true` in `obsidian.json`)
exposes:

| Command | Effect |
|---|---|
| `daily` | Open the daily note (creating it — same `getDailyNote` path) |
| `daily:path` | Print the vault-relative path of today's daily note |
| `daily:read` | Print its contents |
| `daily:append` / `daily:prepend` | Add content, optionally opening it |

All of them are today-only; none takes a date argument. `daily:path` is the
useful probe: it is read-only and shows exactly how the settings resolve.

```console
$ obsidian daily:path vault=Oyster
2026/07/2026-07-26.md
```

## Notes for an Oystermark implementation

- The moment.js format is the whole interoperability contract. To read a vault
  that Obsidian also opens, the same `format` string must produce the same path,
  which means supporting at least the tokens people actually use: `YYYY`, `YY`,
  `MM`, `M`, `MMM`, `MMMM`, `DD`, `D`, `Do`, `ddd`, `dddd`, `ww`, `W`, `gggg`,
  and literal text in `[...]`.
- Reading `.obsidian/daily-notes.json` directly is the cheapest way to stay in
  sync with a vault that is also used from Obsidian; a native Oystermark
  setting can override it.
- Obsidian's prev/next semantics (existing notes, not calendar days) and a
  yesterday/tomorrow semantics (calendar days, create on demand) are different
  features. Both are defensible; they should not be conflated under one name.
