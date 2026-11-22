@tool
extends RefCounted

const I18n := preload("../utilities/i18n.gd")

## Reads the files listed in Project Settings → Localization → POT Generation.
## Dialogue files go through Dialogue Manager's parser. Scripts contribute
## literal tr/atr calls. Scenes contribute text, placeholder_text, and tooltip_text.

const _PARSER_PATH := "res://addons/dialogue_manager/editor_translation_parser_plugin.gd"
const _CALLS: PackedStringArray = ["atr_n", "tr_n", "atr", "tr"]
const _SCENE_PROPS: PackedStringArray = ["tooltip_text", "placeholder_text", "text"]


class CollectResult extends RefCounted:
	var ok := true
	var error := ""
	var messages: Array[Dictionary] = []
	var files: PackedStringArray = PackedStringArray()
	var file_count := 0
	var warnings: PackedStringArray = PackedStringArray()


static func collect() -> CollectResult:
	var result := CollectResult.new()
	var files := _pot_files()
	if files.is_empty():
		result.ok = false
		result.error = I18n.t("No files in Project Settings → Localization → POT Generation.")
		return result
	var seen := {}
	for path: String in files:
		if not FileAccess.file_exists(path):
			result.ok = false
			result.error = I18n.t("File not found: %s") % path
			return result
		var extension := path.get_extension().to_lower()
		var before := result.messages.size()
		if extension == "dialogue":
			if not _read_dialogue(path, result):
				return result
			if result.messages.size() == before:
				result.ok = false
				result.error = I18n.t("Could not read dialogue lines from %s. Catalog unchanged.") % path.get_file()
				return result
		elif extension == "gd":
			if not _read_script(path, result):
				return result
		elif extension == "tscn":
			if not _read_scene(path, result):
				return result
		else:
			result.warnings.append(I18n.t("Skipped %s: only .dialogue, .gd and .tscn are read.") % path.get_file())
			continue
		result.files.append(path)
		result.file_count += 1
	var unique: Array[Dictionary] = []
	for message: Dictionary in result.messages:
		var key := "%s\n%s" % [str(message.get("context", "")), str(message.get("msgid", ""))]
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(message)
	result.messages = unique
	return result


static func _pot_files() -> PackedStringArray:
	var raw: Variant = ProjectSettings.get_setting("internationalization/locale/translations_pot_files", PackedStringArray())
	var files := PackedStringArray()
	if raw is PackedStringArray:
		files = raw
	elif raw is Array:
		var items := raw as Array
		for item: Variant in items:
			files.append(str(item))
	return files


static func _read_dialogue(path: String, result: CollectResult) -> bool:
	var loaded: Resource = load(_PARSER_PATH)
	var parser_script := loaded as Script
	if parser_script == null:
		result.ok = false
		result.error = I18n.t("Dialogue Manager parser not found.")
		return false
	var parser := parser_script.new() as Object
	if parser == null or not parser.has_method("_parse_file"):
		result.ok = false
		result.error = I18n.t("Dialogue Manager parser cannot be opened.")
		return false
	var parsed: Variant = parser.call("_parse_file", path)
	if not (parsed is Array):
		result.ok = false
		result.error = I18n.t("Dialogue Manager parser returned no list for %s.") % path.get_file()
		return false
	var rows := parsed as Array
	var note := path.get_file()
	for row: Variant in rows:
		var msgid := _row_field(row, 0)
		var context := _row_field(row, 1)
		var plural := _row_field(row, 2)
		if msgid.is_empty():
			continue
		result.messages.append({
			"msgid": msgid,
			"context": context,
			"plural": plural,
			"note": note,
		})
	return true


static func _read_script(path: String, result: CollectResult) -> bool:
	var source := _read_text(path, result)
	if source.is_empty() and not result.ok:
		return false
	_scan_script(source, path.get_file(), result.messages)
	return true


static func _read_scene(path: String, result: CollectResult) -> bool:
	var source := _read_text(path, result)
	if source.is_empty() and not result.ok:
		return false
	var note := path.get_file()
	for line: String in source.split("\n", false):
		var stripped := line.strip_edges()
		for prop: String in _SCENE_PROPS:
			var prefix := prop + " = \""
			if not stripped.begins_with(prefix):
				continue
			var quoted := _read_quoted(stripped, prop.length() + 3)
			if not bool(quoted.get("ok", false)):
				continue
			var msgid := str(quoted.get("text", ""))
			if msgid.is_empty():
				continue
			result.messages.append({
				"msgid": msgid,
				"context": "",
				"plural": "",
				"note": note,
			})
	return true


static func _read_text(path: String, result: CollectResult) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.ok = false
		result.error = I18n.t("Cannot open %s") % path
		return ""
	return file.get_as_text()


static func _scan_script(source: String, note: String, messages: Array[Dictionary]) -> void:
	var index := 0
	var count := source.length()
	while index < count:
		var ch := source[index]
		if ch == "#":
			var newline := source.find("\n", index)
			index = count if newline < 0 else newline + 1
			continue
		if ch == "\"" or ch == "'":
			var quoted := _read_quoted(source, index)
			index = int(quoted.get("next", index + 1))
			continue
		var call := _call_at(source, index)
		if call.is_empty():
			index += 1
			continue
		var paren := source.find("(", index)
		if paren < 0:
			break
		var cursor := paren + 1
		var first := _read_call_string(source, cursor)
		if not bool(first.get("ok", false)):
			index = paren + 1
			continue
		var msgid := str(first.get("text", ""))
		cursor = int(first.get("next", paren + 1))
		var plural := ""
		var context := ""
		if call == "tr_n" or call == "atr_n":
			var second := _read_call_string(source, cursor)
			if bool(second.get("ok", false)):
				plural = str(second.get("text", ""))
				cursor = int(second.get("next", cursor))
				cursor = _skip_one_argument(source, cursor)
				var fourth := _read_call_string(source, cursor)
				if bool(fourth.get("ok", false)):
					context = str(fourth.get("text", ""))
		else:
			var second_call := _read_call_string(source, cursor)
			if bool(second_call.get("ok", false)):
				context = str(second_call.get("text", ""))
		if not msgid.is_empty():
			messages.append({
				"msgid": msgid,
				"context": context,
				"plural": plural,
				"note": note,
			})
		index = paren + 1


static func _call_at(source: String, index: int) -> String:
	if index > 0 and _is_id(source[index - 1]):
		return ""
	for name: String in _CALLS:
		if source.substr(index, name.length()) != name:
			continue
		var after := index + name.length()
		if after < source.length() and _is_id(source[after]):
			continue
		var cursor := after
		while cursor < source.length() and (source[cursor] == " " or source[cursor] == "\t" or source[cursor] == "\n"):
			cursor += 1
		if cursor < source.length() and source[cursor] == "(":
			return name
	return ""


static func _read_call_string(source: String, index: int) -> Dictionary:
	var cursor := index
	while cursor < source.length() and (source[cursor] == " " or source[cursor] == "\t" or source[cursor] == "\n" or source[cursor] == ","):
		cursor += 1
	if cursor < source.length() and source[cursor] == "&":
		cursor += 1
		while cursor < source.length() and (source[cursor] == " " or source[cursor] == "\t"):
			cursor += 1
	if cursor >= source.length() or (source[cursor] != "\"" and source[cursor] != "'"):
		return {"ok": false, "next": index}
	return _read_quoted(source, cursor)


static func _skip_one_argument(source: String, index: int) -> int:
	var cursor := index
	while cursor < source.length() and (source[cursor] == " " or source[cursor] == "\t" or source[cursor] == "\n" or source[cursor] == ","):
		cursor += 1
	var depth := 0
	while cursor < source.length():
		var ch := source[cursor]
		if ch == "\"" or ch == "'":
			var quoted := _read_quoted(source, cursor)
			cursor = int(quoted.get("next", cursor + 1))
			continue
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			if depth == 0:
				break
			depth -= 1
		elif ch == "," and depth == 0:
			return cursor + 1
		cursor += 1
	return cursor


static func _read_quoted(source: String, index: int) -> Dictionary:
	if index >= source.length():
		return {"ok": false, "next": index}
	var quote := source[index]
	if quote != "\"" and quote != "'":
		return {"ok": false, "next": index}
	var text := ""
	var cursor := index + 1
	while cursor < source.length():
		var ch := source[cursor]
		if ch == "\\":
			if cursor + 1 >= source.length():
				return {"ok": false, "next": cursor}
			var nxt := source[cursor + 1]
			match nxt:
				"n":
					text += "\n"
				"t":
					text += "\t"
				"r":
					text += "\r"
				"\\":
					text += "\\"
				"\"":
					text += "\""
				"'":
					text += "'"
				_:
					text += nxt
			cursor += 2
			continue
		if ch == quote:
			return {"ok": true, "text": text, "next": cursor + 1}
		text += ch
		cursor += 1
	return {"ok": false, "next": cursor}


static func _row_field(row: Variant, index: int) -> String:
	if row is PackedStringArray:
		var packed := row as PackedStringArray
		if index < 0 or index >= packed.size():
			return ""
		return packed[index]
	if row is Array:
		var items := row as Array
		if index < 0 or index >= items.size():
			return ""
		return str(items[index])
	return ""


static func _is_id(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
