@tool
extends RefCounted

const I18n := preload("i18n.gd")

## Opens the .dialogue file, script, or scene a catalog row came from.
## Returns the status line the screen should show.

## Dialogue Manager is optional. Its scripts are loaded when needed, not
## preloaded: a preload of a missing file would stop this whole plugin from
## compiling in a project without Dialogue Manager.
const _DM_PLUGIN_PATH := "res://addons/dialogue_manager/plugin.gd"
const _DM_CACHE_PATH := "res://addons/dialogue_manager/utilities/dialogue_cache.gd"


static func _dm_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


static func open_entry(context: String, source: String, note: String) -> String:
	if not context.is_empty():
		var dialogue := _dialogue_file(note)
		if dialogue.is_empty():
			return I18n.t("The .dialogue file for this line was not found")
		var line := _line_containing(dialogue, "[ID:%s]" % context)
		if line < 0:
			return I18n.t("%s has no [ID:%s]") % [dialogue.get_file(), context]
		return _open_dialogue(dialogue, line)
	if _looks_like_key(source):
		return _open_key(source)
	return I18n.t("This entry has no file to jump to")


static func _dialogue_file(note: String) -> String:
	var base := ""
	for line: String in note.split("\n", false):
		var token := line.strip_edges().get_file()
		if token.get_extension().to_lower() == "dialogue":
			base = token
			break
	if base.is_empty():
		return ""
	var cache := _dm_script(_DM_CACHE_PATH)
	if cache != null:
		var files: Variant = cache.call("get_files")
		if files is PackedStringArray:
			for path: String in files as PackedStringArray:
				if path.get_file() == base:
					return path
	return _find_named(base)


static func _open_dialogue(path: String, line: int) -> String:
	var plugin := _dm_script(_DM_PLUGIN_PATH)
	if plugin == null or not EditorInterface.is_plugin_enabled("dialogue_manager"):
		return I18n.t("Dialogue Manager is not enabled")
	plugin.call("open_file_at_line", path, line)
	return I18n.t("%s, line %d") % [path.get_file(), line + 1]


static func _open_key(key: String) -> String:
	var hit := _find_literal(key)
	if not hit.is_empty():
		return _open_hit(hit, key)
	if key.begins_with("actor."):
		var built := _find_literal("actor.%s")
		if not built.is_empty():
			_open_hit(built, key)
			return I18n.t("Name %s is built in code: %s, line %d") % [key, str(built.get("path", "")).get_file(), int(built.get("line", 0)) + 1]
	return I18n.t("No literal %s in scripts or scenes") % key


static func _open_hit(hit: Dictionary, key: String) -> String:
	var path := str(hit.get("path", ""))
	var line := int(hit.get("line", 0))
	if path.get_extension().to_lower() == "gd":
		var script := load(path) as Script
		if script == null:
			return I18n.t("Cannot open %s") % path.get_file()
		EditorInterface.edit_script(script, line + 1, 0, true)
		EditorInterface.set_main_screen_editor.call_deferred("Script")
	else:
		EditorInterface.select_file(path)
		EditorInterface.open_scene_from_path(path)
	return I18n.t("%s — %s, line %d") % [key, path.get_file(), line + 1]


static func _find_literal(literal: String) -> Dictionary:
	var needles := PackedStringArray(["\"%s\"" % literal, "&\"%s\"" % literal])
	var files := PackedStringArray()
	_collect_sources("res://", files)
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for index in lines.size():
			for needle: String in needles:
				if lines[index].contains(needle):
					return {"path": path, "line": index}
	return {}


static func _line_containing(path: String, needle: String) -> int:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for index in lines.size():
		if lines[index].contains(needle):
			return index
	return -1


static func _find_named(file_name: String) -> String:
	var found := PackedStringArray()
	_collect_named("res://", file_name, found)
	if found.is_empty():
		return ""
	return found[0]


static func _collect_named(dir: String, file_name: String, found: PackedStringArray) -> void:
	if not found.is_empty():
		return
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect_named(dir.path_join(sub), file_name, found)
		if not found.is_empty():
			return
	for file: String in DirAccess.get_files_at(dir):
		if file == file_name:
			found.append(dir.path_join(file))
			return


static func _collect_sources(dir: String, found: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect_sources(dir.path_join(sub), found)
	for file_name: String in DirAccess.get_files_at(dir):
		var extension := file_name.get_extension().to_lower()
		if extension == "gd" or extension == "tscn":
			found.append(dir.path_join(file_name))


static func _looks_like_key(msgid: String) -> bool:
	if msgid.is_empty() or msgid.contains(" ") or msgid.contains("\t"):
		return false
	var parts := msgid.split(".", false)
	if parts.size() < 2:
		return false
	for part: String in parts:
		if part.is_empty():
			return false
		for index in part.length():
			var code := part.unicode_at(index)
			var digit := code >= 48 and code <= 57
			var upper := code >= 65 and code <= 90
			var lower := code >= 97 and code <= 122
			if index == 0 and digit:
				return false
			if not digit and not upper and not lower and code != 95:
				return false
	return true
