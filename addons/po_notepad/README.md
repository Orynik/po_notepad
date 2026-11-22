# po_notepad

A `.po` editor inside Godot. Edit a catalog entry by entry or as plain text. The plugin does not replace the built-in Translation import: Godot still builds translations from the `.po` files itself.

Tested with **Godot 4.7.2 stable** and **Dialogue Manager 4.2.0**.

License: [MIT](LICENSE). Русская версия: [README.ru.md](README.ru.md).

The interface is available in English and Russian. By default it follows the editor language; it can be pinned in the status bar.

## AI disclosure

The editor scripts in this addon were drafted with an AI coding assistant (a large language model). A human reviewed all of the resulting code before release.

## Installation

Copy `addons/po_notepad` into your project's `addons/` folder and enable it in Project Settings → Plugins → po_notepad. After changing the plugin's scripts, disable and enable it again: Godot does not reload them on its own.

The **PO** tab appears next to 2D, 3D and Script. The locale list on the left shows the files from Project Settings → Localization → Translations that exist on disk. Any other `.po` opens with the folder button on the toolbar, from the FileSystem context menu, or by double-clicking it.

## Features

- List and text modes; context, notes, plural forms; adding and deleting entries.
- Filters (empty, needs review, dialogue lines, keys), search, jumping to the next empty entry, "Copy original".
- "Merge POT" reads the file list from Project Settings → Localization → POT Generation. A new string gets an empty translation. The same context with different English text keeps the translation and marks it "needs review". An exact match does not clear an existing review mark. A phrase that disappeared from the scenes is removed. A dotted key like `ui.hud.examine` is kept. An English catalog (`Language` starts with `en`) does not receive new dialogue lines.
- Before saving, `{placeholders}` and the number of forms are checked against `nplurals`. An empty translation does not block saving. An accepted mismatch turns yellow and is remembered locally, not in the `.po`.
- Double-click opens the `.dialogue` file or the script where the key is written literally. `actor.*` names are built in code, so the double-click leads to where they are built.
- Unsaved edits are kept in `user://po_notepad` and offered back after a crash.

A merge changes only the open buffer and does not write to disk by itself.

## Dialogue Manager (optional)

Dialogue lines from `.dialogue` files are read with the Dialogue Manager parser. Without that plugin everything else works, but a POT merge stops at the first `.dialogue` file, and double-clicking a dialogue line does not open the Dialogue tab.

The expected setup:

- `dialogue_manager/use_static_ids_as_translation_keys` is off. The original is the English phrase; the context is the static id without the `ID:` prefix.
- The entry note keeps the file name, for example `#. dlg_desk_note.dialogue`. Double-click uses it to find the `[ID:…]` and opens the line through Dialogue Manager.

Keys from `.gd` and `.tscn` do not depend on Dialogue Manager. The plugin does not open plain `.tres` files and does not merge them: Godot shows them in the Inspector, and the POT list is read only from `.dialogue`, `.gd` and `.tscn`.
