@tool
extends RefCounted

const I18n := preload("../utilities/i18n.gd")

## Parses and writes gettext PO text.
## Comments, order, and multiline strings are kept so an unchanged file
## round-trips, and a translation edit rewrites only that msgstr.

const _KEYS: PackedStringArray = ["msgid_plural", "msgctxt", "msgid", "msgstr"]


class Quote extends RefCounted:
	var ok := false
	var text := ""


class Entry extends RefCounted:
	var prefix: PackedStringArray = PackedStringArray()
	var has_context := false
	var msgctxt := ""
	var msgid := ""
	var has_plural := false
	var msgid_plural := ""
	var indexed := false
	var form_indexes: PackedInt32Array = PackedInt32Array()
	var forms: PackedStringArray = PackedStringArray()
	var field := ""
	var form_cursor := -1
	var is_header := false


class MergeResult extends RefCounted:
	var ok := false
	var error := ""
	var added := PackedStringArray()
	var reviewed := PackedStringArray()
	var removed := PackedStringArray()
	var unseen := PackedStringArray()
	var unseen_from := PackedStringArray()
	var kept := 0
	var skipped_dialogue := 0
	var filter_label := ""


const _FUZZY_THRESHOLD := 0.8


var error := ""

var _brace_pattern: RegEx
var _entries: Array[Entry] = []
var _trailing: PackedStringArray = PackedStringArray()
var _visible: PackedInt32Array = PackedInt32Array()


func parse(text: String) -> bool:
	_entries.clear()
	_trailing = PackedStringArray()
	_visible = PackedInt32Array()
	error = ""
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	var lines := normalized.split("\n", true)
	if not lines.is_empty() and lines[lines.size() - 1].is_empty():
		lines = lines.slice(0, lines.size() - 1)
	var pending := PackedStringArray()
	var current: Entry = null
	for line: String in lines:
		var stripped := line.strip_edges()
		var blank := stripped.is_empty()
		var comment := stripped.begins_with("#")
		var key := ""
		if not blank and not comment:
			key = _keyword(line)
		var cont := not blank and not comment and key.is_empty() and stripped.begins_with("\"")
		if current == null:
			if blank or comment:
				pending.append(line)
				continue
			if key.is_empty():
				error = "Unexpected line: %s" % stripped
				return false
			current = Entry.new()
			current.prefix = pending.duplicate()
			pending = PackedStringArray()
		else:
			if blank:
				_finish(current)
				current = null
				continue
			if comment:
				_finish(current)
				current = null
				pending = PackedStringArray()
				pending.append(line)
				continue
			if key.is_empty() and not cont:
				error = "Unexpected line: %s" % stripped
				return false
		if not key.is_empty():
			var quote := _read_quote(line)
			if not quote.ok:
				error = "Bad quotes: %s" % stripped
				return false
			_set_field(current, key, line, quote.text)
		elif cont:
			var quote := _read_quote(stripped)
			if not quote.ok or current == null:
				error = "Bad continuation: %s" % stripped
				return false
			_append_field(current, quote.text)
	if current != null:
		_finish(current)
	_trailing = pending
	_rebuild_visible()
	return true


func to_text() -> String:
	var out := ""
	for index in _entries.size():
		if index > 0:
			out += "\n"
		var entry := _entries[index]
		for line: String in entry.prefix:
			out += line + "\n"
		if entry.has_context:
			out += _format_field("msgctxt", entry.msgctxt)
		out += _format_field("msgid", entry.msgid)
		if entry.has_plural:
			out += _format_field("msgid_plural", entry.msgid_plural)
		if entry.forms.is_empty():
			out += "msgstr \"\"\n"
		elif not entry.indexed:
			out += _format_field("msgstr", entry.forms[0])
		else:
			for slot in entry.forms.size():
				out += _format_field("msgstr[%d]" % entry.form_indexes[slot], entry.forms[slot])
	var has_trailing := false
	for line: String in _trailing:
		if not line.strip_edges().is_empty():
			has_trailing = true
			break
	if has_trailing:
		if not out.is_empty() and not out.ends_with("\n\n"):
			out += "\n"
		for line: String in _trailing:
			out += line + "\n"
	return out


func visible_count() -> int:
	return _visible.size()


func source_text(index: int) -> String:
	return _entry(index).msgid


func source_preview(index: int) -> String:
	var text := source_text(index)
	if text.is_empty():
		return "(new)"
	return _one_line(text)


func context_text(index: int) -> String:
	var entry := _entry(index)
	if not entry.has_context:
		return ""
	return entry.msgctxt


func comment_text(index: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for line: String in _entry(index).prefix:
		var stripped := line.strip_edges()
		if stripped.begins_with("#."):
			parts.append(stripped.substr(2).strip_edges())
	return "\n".join(parts)


func has_plural(index: int) -> bool:
	return _entry(index).has_plural


func plural_source(index: int) -> String:
	var entry := _entry(index)
	if not entry.has_plural:
		return ""
	return entry.msgid_plural


func form_count(index: int) -> int:
	return _entry(index).forms.size()


func form_label(index: int, slot: int) -> String:
	var entry := _entry(index)
	if not entry.indexed:
		return I18n.t("Translation")
	return "msgstr[%d]" % entry.form_indexes[slot]


func form_text(index: int, slot: int) -> String:
	return _entry(index).forms[slot]


func set_form(index: int, slot: int, value: String) -> void:
	var entry := _entry(index)
	if slot < 0 or slot >= entry.forms.size():
		return
	entry.forms[slot] = value


func set_source(index: int, value: String) -> void:
	var entry := _entry(index)
	if entry.has_plural and (entry.msgid_plural.is_empty() or entry.msgid_plural == entry.msgid):
		entry.msgid_plural = value
	entry.msgid = value


func set_context(index: int, value: String) -> void:
	var entry := _entry(index)
	if value.is_empty():
		entry.has_context = false
		entry.msgctxt = ""
		return
	entry.has_context = true
	entry.msgctxt = value


func set_note(index: int, value: String) -> void:
	var entry := _entry(index)
	var kept := PackedStringArray()
	for line: String in entry.prefix:
		if not line.strip_edges().begins_with("#."):
			kept.append(line)
	var cleaned := value.replace("\n", " ").strip_edges()
	if not cleaned.is_empty():
		kept.append("#. " + cleaned)
	entry.prefix = kept


func set_plural_source(index: int, value: String) -> void:
	var entry := _entry(index)
	entry.has_plural = true
	entry.msgid_plural = value


func set_plural_enabled(index: int, enabled: bool) -> void:
	var entry := _entry(index)
	if not enabled:
		var first := ""
		if not entry.forms.is_empty():
			first = entry.forms[0]
		entry.has_plural = false
		entry.msgid_plural = ""
		entry.indexed = false
		entry.forms = PackedStringArray()
		entry.form_indexes = PackedInt32Array()
		entry.forms.append(first)
		entry.form_indexes.append(-1)
		return
	if entry.has_plural and entry.indexed:
		return
	var count := header_plural_count()
	var existing := entry.forms.duplicate()
	entry.has_plural = true
	if entry.msgid_plural.is_empty():
		entry.msgid_plural = entry.msgid
	entry.indexed = true
	entry.forms = PackedStringArray()
	entry.form_indexes = PackedInt32Array()
	for slot in count:
		entry.form_indexes.append(slot)
		if slot < existing.size():
			entry.forms.append(existing[slot])
		else:
			entry.forms.append("")


func header_plural_count() -> int:
	for entry: Entry in _entries:
		if not entry.is_header or entry.forms.is_empty():
			continue
		var pattern := RegEx.new()
		if pattern.compile("nplurals\\s*=\\s*(\\d+)") != OK:
			return 2
		var found := pattern.search(entry.forms[0])
		if found == null:
			return 2
		var number := found.get_string(1).to_int()
		if number < 1:
			return 2
		return number
	return 2


func add_entry(after_visible: int) -> int:
	var entry := Entry.new()
	entry.forms.append("")
	entry.form_indexes.append(-1)
	var at := _entries.size()
	if after_visible >= 0 and after_visible < _visible.size():
		at = _visible[after_visible] + 1
	_entries.insert(at, entry)
	_rebuild_visible()
	for index in _visible.size():
		if _visible[index] == at:
			return index
	return -1


func remove_entry(visible_index: int) -> int:
	if visible_index < 0 or visible_index >= _visible.size():
		return -1
	_entries.remove_at(_visible[visible_index])
	_rebuild_visible()
	if _visible.is_empty():
		return -1
	if visible_index >= _visible.size():
		return _visible.size() - 1
	return visible_index


func _rebuild_visible() -> void:
	_visible = PackedInt32Array()
	for index in _entries.size():
		if not _entries[index].is_header:
			_visible.append(index)


func translation_preview(index: int) -> String:
	var entry := _entry(index)
	if entry.forms.is_empty():
		return ""
	if entry.forms.size() == 1:
		return _one_line(entry.forms[0])
	var parts: PackedStringArray = PackedStringArray()
	for form: String in entry.forms:
		parts.append(_one_line(form))
	return " | ".join(parts)


func is_untranslated(index: int) -> bool:
	var entry := _entry(index)
	if entry.forms.is_empty():
		return true
	for form: String in entry.forms:
		if not form.strip_edges().is_empty():
			return false
	return true


func is_fuzzy(index: int) -> bool:
	for line: String in _entry(index).prefix:
		var stripped := line.strip_edges()
		if not stripped.begins_with("#,"):
			continue
		for flag: String in stripped.substr(2).split(",", false):
			if flag.strip_edges() == "fuzzy":
				return true
	return false


func clear_fuzzy(index: int) -> void:
	var entry := _entry(index)
	var kept := PackedStringArray()
	for line: String in entry.prefix:
		var stripped := line.strip_edges()
		if stripped.begins_with("#|"):
			continue
		if stripped.begins_with("#,"):
			var flags := _flags_without_fuzzy(stripped.substr(2))
			if flags.is_empty():
				continue
			kept.append("#, " + flags)
			continue
		kept.append(line)
	entry.prefix = kept


func issue_summary(index: int) -> String:
	var entry := _entry(index)
	var parts := PackedStringArray()
	var plural := _plural_count_issue(entry)
	if not plural.is_empty():
		parts.append(plural)
	for slot in entry.forms.size():
		var form_issue := _form_token_issue(entry, slot)
		if not form_issue.is_empty():
			parts.append(form_issue)
	return "; ".join(parts)


func issue_signature(index: int) -> String:
	var problem := issue_summary(index)
	if problem.is_empty():
		return ""
	var entry := _entry(index)
	return "%s\n%s\n%s" % [entry.msgctxt, entry.msgid, problem]


func issue_lines() -> PackedStringArray:
	return issue_lines_except({})


func issue_lines_except(skip: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for index in visible_count():
		var signature := issue_signature(index)
		if signature.is_empty() or skip.has(signature):
			continue
		var entry := _entry(index)
		var problem := issue_summary(index)
		lines.append("%s — %s" % [_message_label(entry.msgid, entry.msgctxt), problem])
	return lines


func issue_count() -> int:
	var count := 0
	for index in visible_count():
		if not issue_summary(index).is_empty():
			count += 1
	return count


func check_notice(index: int) -> String:
	var parts := PackedStringArray()
	if is_fuzzy(index):
		parts.append(I18n.t("Needs review. Godot ignores this entry until the flag is cleared."))
	var problem := issue_summary(index)
	if not problem.is_empty():
		parts.append(problem)
	return "\n".join(parts)


func is_dialogue(index: int) -> bool:
	return _entry(index).has_context


func matches(index: int, query: String) -> bool:
	if query.is_empty():
		return true
	var entry := _entry(index)
	if entry.msgid.findn(query) >= 0 or entry.msgctxt.findn(query) >= 0 or entry.msgid_plural.findn(query) >= 0:
		return true
	for form: String in entry.forms:
		if form.findn(query) >= 0:
			return true
	return false


func stats() -> Vector3i:
	var translated := 0
	var empty := 0
	var review := 0
	for index in visible_count():
		if is_fuzzy(index):
			review += 1
		elif is_untranslated(index):
			empty += 1
		else:
			translated += 1
	return Vector3i(translated, empty, review)


func copy_source(index: int) -> void:
	var entry := _entry(index)
	if entry.forms.is_empty():
		entry.forms.append("")
		entry.form_indexes.append(-1 if not entry.indexed else 0)
	if entry.has_plural:
		for slot in entry.forms.size():
			if slot == 0:
				entry.forms[slot] = entry.msgid
			else:
				entry.forms[slot] = entry.msgid_plural if not entry.msgid_plural.is_empty() else entry.msgid
		return
	entry.forms[0] = entry.msgid


func language() -> String:
	if _entries.is_empty() or not _entries[0].is_header or _entries[0].forms.is_empty():
		return ""
	for line: String in _entries[0].forms[0].split("\n", false):
		var stripped := line.strip_edges()
		if not stripped.begins_with("Language:"):
			continue
		var value := stripped.substr("Language:".length()).strip_edges()
		var space := value.find(" ")
		if space >= 0:
			value = value.substr(0, space)
		return value
	return ""


func has_context_entries() -> bool:
	for entry: Entry in _entries:
		if entry.has_context:
			return true
	return false


func context_message_count(messages: Array[Dictionary]) -> int:
	var count := 0
	for message: Dictionary in messages:
		if not str(message.get("context", "")).is_empty():
			count += 1
	return count


## Merges template messages into this catalog.
## Same msgid and context keep the translation. The same context with a
## different msgid keeps the translation and gains the fuzzy flag. A close
## msgid (msgmerge's 0.8 cutoff) does the same across entries. Dialogue
## lines that left the template are removed. A plain sentence we previously
## took from a scanned file is removed once that file no longer has it.
## A dotted key is kept: code can still build it where the scanner cannot look.
func merge_template(messages: Array[Dictionary], skip_new_context: bool, sources: PackedStringArray) -> MergeResult:
	var result := MergeResult.new()
	if has_context_entries() and context_message_count(messages) == 0 and not skip_new_context:
		result.error = I18n.t("The template has no dialogue lines, but the catalog does. Merge cancelled, catalog unchanged.")
		return result
	var source_names := _unique_source_names(sources)
	var limit := _entries.size()
	var used := PackedByteArray()
	if used.resize(limit) != OK:
		result.error = I18n.t("Could not prepare the merge.")
		return result
	var pending: Array[Dictionary] = []
	for message: Dictionary in messages:
		var msgid := str(message.get("msgid", ""))
		if msgid.is_empty():
			continue
		var context := str(message.get("context", ""))
		var found := _exact_index(msgid, context, used, limit)
		if found >= 0:
			used[found] = 1
			if _plural_differs(_entries[found], message):
				var previous := _entries[found].msgid
				_apply_message(_entries[found], message)
				_mark_fuzzy(_entries[found], previous, context)
				result.reviewed.append(_message_label(previous, context) + " → " + _message_label(msgid, context))
			else:
				result.kept += 1
			continue
		pending.append(message)
	var pending_used := PackedByteArray()
	if pending_used.resize(pending.size()) != OK:
		result.error = I18n.t("Could not prepare the merge.")
		return result
	for message_index in pending.size():
		var message: Dictionary = pending[message_index]
		var context := str(message.get("context", ""))
		if context.is_empty() or (skip_new_context and not context.is_empty()):
			continue
		var same := _context_index(context, used, limit)
		if same < 0:
			continue
		var previous_msgid := _entries[same].msgid
		var previous_context := _entries[same].msgctxt
		_apply_message(_entries[same], message)
		_mark_fuzzy(_entries[same], previous_msgid, previous_context)
		used[same] = 1
		pending_used[message_index] = 1
		result.reviewed.append(_message_label(previous_msgid, previous_context) + " → " + _message_label(str(message.get("msgid", "")), context))
	var guard := pending.size()
	while guard > 0:
		guard -= 1
		var best_message := -1
		var best_entry := -1
		var best_score := 0.0
		for message_index in pending.size():
			if pending_used[message_index] != 0:
				continue
			var message: Dictionary = pending[message_index]
			var context := str(message.get("context", ""))
			if skip_new_context and not context.is_empty():
				continue
			for entry_index in limit:
				if used[entry_index] != 0 or _entries[entry_index].is_header:
					continue
				if not _same_family(_entries[entry_index], context):
					continue
				var score := _similarity(_entries[entry_index].msgid, str(message.get("msgid", "")))
				if score > best_score:
					best_score = score
					best_message = message_index
					best_entry = entry_index
		if best_entry < 0 or best_score < _FUZZY_THRESHOLD:
			break
		var chosen: Dictionary = pending[best_message]
		var previous_msgid := _entries[best_entry].msgid
		var previous_context := _entries[best_entry].msgctxt
		_apply_message(_entries[best_entry], chosen)
		_mark_fuzzy(_entries[best_entry], previous_msgid, previous_context)
		used[best_entry] = 1
		pending_used[best_message] = 1
		result.reviewed.append(_message_label(previous_msgid, previous_context) + " → " + _message_label(str(chosen.get("msgid", "")), str(chosen.get("context", ""))))
	for message_index in pending.size():
		if pending_used[message_index] != 0:
			continue
		var message: Dictionary = pending[message_index]
		var context := str(message.get("context", ""))
		if skip_new_context and not context.is_empty():
			result.skipped_dialogue += 1
			continue
		_entries.append(_new_entry(message))
		var added_label := _message_label(str(message.get("msgid", "")), context)
		var note := str(message.get("note", "")).strip_edges()
		if not note.is_empty():
			added_label += " (%s)" % note
		result.added.append(added_label)
	for entry_index in range(limit - 1, -1, -1):
		if used[entry_index] != 0 or _entries[entry_index].is_header:
			continue
		var entry := _entries[entry_index]
		if entry.has_context and not skip_new_context:
			result.removed.append(_message_label(entry.msgid, entry.msgctxt))
			_entries.remove_at(entry_index)
			continue
		var origin := ""
		if not entry.has_context:
			origin = _extracted_basename(entry, source_names)
		if not origin.is_empty() and not _is_stable_key(entry.msgid):
			result.removed.append(_message_label(entry.msgid, "") + " (" + origin + ")")
			_entries.remove_at(entry_index)
			continue
		if not entry.has_context:
			result.unseen.append(entry.msgid)
			result.unseen_from.append(origin)
	_rebuild_visible()
	result.ok = true
	return result


func find_visible(query: String, start: int, forward: bool) -> int:
	var count := visible_count()
	if count == 0 or query.is_empty():
		return -1
	var index := 0
	if forward:
		index = 0 if start < 0 else start + 1
		if index >= count:
			index = 0
	else:
		index = count - 1 if start < 0 else start - 1
		if index < 0:
			index = count - 1
	for _step in count:
		if _haystack(index).find(query) >= 0:
			return index
		if forward:
			index += 1
			if index >= count:
				index = 0
		else:
			index -= 1
			if index < 0:
				index = count - 1
	return -1


func _entry(index: int) -> Entry:
	return _entries[_visible[index]]


func _haystack(index: int) -> String:
	var entry := _entry(index)
	var text := entry.msgid + "\n" + entry.msgctxt + "\n" + entry.msgid_plural + "\n" + comment_text(index)
	for form: String in entry.forms:
		text += "\n" + form
	return text


func _finish(entry: Entry) -> void:
	entry.is_header = entry.msgid.is_empty() and not entry.has_context and not entry.has_plural and _entries.is_empty()
	_entries.append(entry)


func _set_field(entry: Entry, key: String, line: String, value: String) -> void:
	entry.field = key
	if key == "msgctxt":
		entry.has_context = true
		entry.msgctxt = value
	elif key == "msgid":
		entry.msgid = value
	elif key == "msgid_plural":
		entry.has_plural = true
		entry.msgid_plural = value
	else:
		var form_index := _form_index(line)
		if form_index >= 0:
			entry.indexed = true
		entry.form_indexes.append(form_index)
		entry.forms.append(value)
		entry.form_cursor = entry.forms.size() - 1


func _append_field(entry: Entry, value: String) -> void:
	match entry.field:
		"msgctxt":
			entry.msgctxt += value
		"msgid":
			entry.msgid += value
		"msgid_plural":
			entry.msgid_plural += value
		"msgstr":
			if entry.form_cursor >= 0:
				entry.forms[entry.form_cursor] = entry.forms[entry.form_cursor] + value


func _keyword(line: String) -> String:
	var stripped := line.strip_edges()
	for key: String in _KEYS:
		if stripped == key or stripped.begins_with(key + " ") or stripped.begins_with(key + "["):
			return key
	return ""


func _form_index(line: String) -> int:
	var stripped := line.strip_edges()
	var marker := "msgstr["
	if not stripped.begins_with(marker):
		return -1
	var end := stripped.find("]")
	if end < marker.length():
		return -1
	var number := stripped.substr(marker.length(), end - marker.length())
	if not number.is_valid_int():
		return -1
	return number.to_int()


func _read_quote(line: String) -> Quote:
	var result := Quote.new()
	var start := line.find("\"")
	if start < 0:
		return result
	var raw := ""
	var index := start + 1
	while index < line.length():
		var ch := line[index]
		if ch == "\\":
			if index + 1 >= line.length():
				return result
			var nxt := line[index + 1]
			match nxt:
				"n":
					raw += "\n"
				"t":
					raw += "\t"
				"r":
					raw += "\r"
				"\\":
					raw += "\\"
				"\"":
					raw += "\""
				_:
					raw += nxt
			index += 2
			continue
		if ch == "\"":
			result.ok = true
			result.text = raw
			return result
		raw += ch
		index += 1
	return result


func _format_field(key: String, text: String) -> String:
	if not text.contains("\n"):
		return "%s \"%s\"\n" % [key, _escape(text)]
	var parts := text.split("\n", true)
	var out := "%s \"\"\n" % key
	for index in parts.size():
		var last := index == parts.size() - 1
		var part := parts[index]
		if last and part.is_empty():
			break
		var piece := part if last else part + "\n"
		out += "\"%s\"\n" % _escape(piece)
	return out


func _escape(text: String) -> String:
	return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")


func _one_line(text: String) -> String:
	var flat := text.replace("\n", " ")
	if flat.length() > 160:
		return flat.substr(0, 160) + "..."
	return flat


func _context_index(context: String, used: PackedByteArray, limit: int) -> int:
	for index in limit:
		if used[index] != 0:
			continue
		var entry := _entries[index]
		if entry.is_header or not entry.has_context:
			continue
		if entry.msgctxt == context:
			return index
	return -1


func _exact_index(msgid: String, context: String, used: PackedByteArray, limit: int) -> int:
	var wants_context := not context.is_empty()
	for index in limit:
		if used[index] != 0:
			continue
		var entry := _entries[index]
		if entry.is_header or entry.msgid != msgid:
			continue
		if entry.has_context == wants_context and entry.msgctxt == context:
			return index
	return -1


func _plural_differs(entry: Entry, message: Dictionary) -> bool:
	var plural := str(message.get("plural", ""))
	var message_plural := not plural.is_empty()
	if entry.has_plural != message_plural:
		return true
	return entry.has_plural and entry.msgid_plural != plural


func _same_family(entry: Entry, context: String) -> bool:
	return entry.has_context == (not context.is_empty())


func _apply_message(entry: Entry, message: Dictionary) -> void:
	entry.msgid = str(message.get("msgid", ""))
	var context := str(message.get("context", ""))
	if context.is_empty():
		entry.has_context = false
		entry.msgctxt = ""
	else:
		entry.has_context = true
		entry.msgctxt = context
	var plural := str(message.get("plural", ""))
	if plural.is_empty():
		if entry.has_plural:
			var first := ""
			if not entry.forms.is_empty():
				first = entry.forms[0]
			entry.has_plural = false
			entry.msgid_plural = ""
			entry.indexed = false
			entry.forms = PackedStringArray()
			entry.form_indexes = PackedInt32Array()
			entry.forms.append(first)
			entry.form_indexes.append(-1)
		elif entry.forms.is_empty():
			entry.forms.append("")
			entry.form_indexes.append(-1)
		return
	var existing := entry.forms.duplicate()
	entry.has_plural = true
	entry.msgid_plural = plural
	entry.indexed = true
	entry.forms = PackedStringArray()
	entry.form_indexes = PackedInt32Array()
	var count := header_plural_count()
	for slot in count:
		entry.form_indexes.append(slot)
		if slot < existing.size():
			entry.forms.append(existing[slot])
		else:
			entry.forms.append("")


func _new_entry(message: Dictionary) -> Entry:
	var entry := Entry.new()
	var note := str(message.get("note", "")).strip_edges()
	if not note.is_empty():
		entry.prefix.append("#: " + note)
		entry.prefix.append("#. " + note)
	_apply_message(entry, message)
	for slot in entry.forms.size():
		entry.forms[slot] = ""
	return entry


func _mark_fuzzy(entry: Entry, previous_msgid: String, previous_context: String) -> void:
	var kept := PackedStringArray()
	var flags := ""
	for line: String in entry.prefix:
		var stripped := line.strip_edges()
		if stripped.begins_with("#|"):
			continue
		if stripped.begins_with("#,"):
			flags = stripped.substr(2).strip_edges()
			continue
		kept.append(line)
	if flags.is_empty():
		flags = "fuzzy"
	elif not _flag_list_has_fuzzy(flags):
		flags += ", fuzzy"
	kept.append("#, " + flags)
	if not previous_context.is_empty() and previous_context != entry.msgctxt:
		for line: String in _previous_field("msgctxt", previous_context):
			kept.append(line)
	if previous_msgid != entry.msgid:
		for line: String in _previous_field("msgid", previous_msgid):
			kept.append(line)
	entry.prefix = kept


func _flag_list_has_fuzzy(flags: String) -> bool:
	for flag: String in flags.split(",", false):
		if flag.strip_edges() == "fuzzy":
			return true
	return false


func _flags_without_fuzzy(flags: String) -> String:
	var kept := PackedStringArray()
	for flag: String in flags.split(",", false):
		var name := flag.strip_edges()
		if name.is_empty() or name == "fuzzy":
			continue
		kept.append(name)
	return ", ".join(kept)


func _plural_count_issue(entry: Entry) -> String:
	if not entry.has_plural:
		return ""
	var expected := header_plural_count()
	var present := {}
	for slot in entry.form_indexes.size():
		var number := entry.form_indexes[slot]
		if number < 0:
			continue
		present[number] = true
	var complete := entry.forms.size() == expected
	if complete:
		for number in expected:
			if not present.has(number):
				complete = false
				break
	if complete:
		return ""
	return I18n.t("%d forms, header says nplurals=%d") % [entry.forms.size(), expected]


func _form_token_issue(entry: Entry, slot: int) -> String:
	if slot < 0 or slot >= entry.forms.size():
		return ""
	var translation := entry.forms[slot]
	if translation.strip_edges().is_empty():
		return ""
	var source := entry.msgid
	var number := _form_number(entry, slot)
	if entry.has_plural and number != 0:
		source = entry.msgid_plural if not entry.msgid_plural.is_empty() else entry.msgid
	var diff := _token_diff(source, translation)
	if diff.is_empty():
		return ""
	if not entry.has_plural:
		return diff
	var name := "msgstr" if number < 0 else "msgstr[%d]" % number
	return "%s: %s" % [name, diff]


func _form_number(entry: Entry, slot: int) -> int:
	if slot < 0 or slot >= entry.form_indexes.size():
		return slot
	var number := entry.form_indexes[slot]
	if number < 0:
		return slot
	return number


func _token_diff(source: String, translation: String) -> String:
	var left := _token_counts(source)
	if left.is_empty():
		return ""
	var right := _token_counts(translation)
	var missing := _missing_tokens(left, right)
	var extra := _missing_tokens(right, left)
	var parts := PackedStringArray()
	if not missing.is_empty():
		parts.append(I18n.t("missing %s") % ", ".join(missing))
	if not extra.is_empty():
		parts.append(I18n.t("extra %s") % ", ".join(extra))
	return "; ".join(parts)


func _missing_tokens(needed: Dictionary, present: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var tokens: Array = needed.keys()
	for token_value: Variant in tokens:
		var token := str(token_value)
		var need := int(needed[token])
		var have := int(present.get(token, 0))
		if need <= have:
			continue
		for _repeat in need - have:
			missing.append(token)
	return missing


func _token_counts(text: String) -> Dictionary:
	var counts := {}
	var pattern := _braces()
	if pattern == null:
		return counts
	var matches: Array = pattern.search_all(text)
	for match_value: Variant in matches:
		var match := match_value as RegExMatch
		if match == null:
			continue
		var token := match.get_string(0)
		counts[token] = int(counts.get(token, 0)) + 1
	return counts


func _braces() -> RegEx:
	if _brace_pattern == null:
		var pattern := RegEx.new()
		if pattern.compile("\\{[^{}]+\\}") != OK:
			return null
		_brace_pattern = pattern
	return _brace_pattern


func _previous_field(key: String, text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for line: String in _format_field(key, text).split("\n", false):
		lines.append("#| " + line)
	return lines


func _unique_source_names(sources: PackedStringArray) -> Dictionary:
	var counts := {}
	for path: String in sources:
		var base := path.get_file()
		if base.is_empty():
			continue
		var previous := 0
		if counts.has(base):
			previous = int(counts[base])
		counts[base] = previous + 1
	var unique := {}
	var bases: Array = counts.keys()
	for base_value: Variant in bases:
		var base := str(base_value)
		if int(counts[base]) == 1:
			unique[base] = true
	return unique


func _extracted_basename(entry: Entry, source_names: Dictionary) -> String:
	for line: String in entry.prefix:
		var stripped := line.strip_edges()
		var payload := ""
		if stripped.begins_with("#:"):
			payload = stripped.substr(2).strip_edges()
		elif stripped.begins_with("#."):
			payload = stripped.substr(2).strip_edges()
		else:
			continue
		var base := _reference_basename(payload)
		if not base.is_empty() and source_names.has(base):
			return base
	return ""


func _reference_basename(payload: String) -> String:
	if payload.is_empty() or payload.contains(" ") or payload.contains("\t"):
		return ""
	var base := payload.get_file()
	var colon := base.rfind(":")
	if colon > 0 and base.substr(colon + 1).is_valid_int():
		base = base.substr(0, colon).get_file()
	if base.contains(":") or base.contains("/") or base.contains("\\"):
		return ""
	return base


func _is_stable_key(msgid: String) -> bool:
	if msgid.is_empty():
		return false
	var parts := msgid.split(".", false)
	if parts.size() < 2:
		return false
	for part: String in parts:
		if part.is_empty() or not _is_key_segment(part):
			return false
	return true


func _is_key_segment(part: String) -> bool:
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


func _message_label(msgid: String, context: String) -> String:
	var text := _one_line(msgid)
	if context.is_empty():
		return text
	return "%s: %s" % [context, text]


func _similarity(left: String, right: String) -> float:
	if left == right:
		return 1.0
	var left_len := left.length()
	var right_len := right.length()
	if left_len == 0 or right_len == 0:
		return 0.0
	var longest := left_len if left_len > right_len else right_len
	var shortest := right_len if left_len > right_len else left_len
	if float(shortest) / float(longest) < _FUZZY_THRESHOLD:
		return 0.0
	if longest > 500:
		return 0.0
	var prev := PackedInt32Array()
	var width := right_len + 1
	if prev.resize(width) != OK:
		return 0.0
	for column in right_len + 1:
		prev[column] = column
	for row in left_len:
		var cur := PackedInt32Array()
		if cur.resize(width) != OK:
			return 0.0
		cur[0] = row + 1
		for column in right_len:
			var cost := 0 if left[row] == right[column] else 1
			cur[column + 1] = mini(prev[column + 1] + 1, mini(cur[column] + 1, prev[column] + cost))
		prev = cur
	return 1.0 - float(prev[right_len]) / float(longest)
