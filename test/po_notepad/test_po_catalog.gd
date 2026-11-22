extends GdUnitTestSuite
## Public behavior of the PO catalog: parse/write, save checks, and POT merge.
## Editor widgets are not covered. The POT file reader needs the editor, so it is not run here.

const PoCatalog := preload("res://addons/po_notepad/catalog/po_catalog.gd")


func test_round_trip_keeps_notes_order_and_escapes() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("say \"hi\"", "скажи", "dialogue.note", "note.dialogue"))
	catalog.set_source(0, "say \"hi\"\n\tnext")
	catalog.set_form(0, 0, "скажи \"привет\"")
	var again := _open(catalog.to_text())
	assert_int(again.visible_count()).is_equal(1)
	assert_str(again.source_text(0)).is_equal("say \"hi\"\n\tnext")
	assert_str(again.form_text(0, 0)).is_equal("скажи \"привет\"")
	assert_str(again.context_text(0)).is_equal("dialogue.note")
	assert_str(again.comment_text(0)).is_equal("note.dialogue")
	assert_str(again.to_text()).is_equal(catalog.to_text())


func test_header_is_hidden_and_a_later_empty_msgid_stays() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("", ""))
	assert_str(catalog.language()).is_equal("ru")
	assert_int(catalog.header_plural_count()).is_equal(3)
	assert_int(catalog.visible_count()).is_equal(1)
	assert_str(catalog.source_preview(0)).is_equal("(new)")
	var english := _open(_header("en_US", 2))
	assert_str(english.language()).is_equal("en_US")
	assert_int(english.header_plural_count()).is_equal(2)


func test_broken_po_is_rejected_and_a_later_parse_replaces_it() -> void:
	var catalog: PoCatalog = PoCatalog.new()
	assert_bool(catalog.parse("this is not a catalog")).is_false()
	assert_str(catalog.error).is_not_empty()
	assert_bool(catalog.parse("msgid \"unterminated\nmsgstr \"\"\n")).is_false()
	assert_bool(catalog.parse(_ru_header() + "\n" + _entry("a", "б"))).is_true()
	assert_str(catalog.error).is_empty()
	assert_str(catalog.form_text(0, 0)).is_equal("б")


func test_comments_stick_to_the_next_entry_and_a_trailing_comment_survives() -> void:
	var text := _ru_header()
	text += "\n" + _entry("first", "первый")
	text += "\n#. second note\n" + _entry("second", "второй")
	text += "\n# kept at the end\n"
	var catalog := _open(text)
	assert_str(catalog.comment_text(0)).is_empty()
	assert_str(catalog.comment_text(1)).is_equal("second note")
	assert_str(catalog.to_text()).contains("# kept at the end")


func test_plural_slots_follow_nplurals_and_copy_source_fills_them() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("one item", "один"))
	catalog.set_plural_enabled(0, true)
	assert_int(catalog.form_count(0)).is_equal(3)
	assert_str(catalog.form_label(0, 2)).is_equal("msgstr[2]")
	catalog.set_plural_source(0, "many items")
	catalog.set_form(0, 1, "уже есть")
	catalog.set_plural_enabled(0, true)
	assert_str(catalog.form_text(0, 1)).is_equal("уже есть")
	catalog.copy_source(0)
	assert_str(catalog.form_text(0, 0)).is_equal("one item")
	assert_str(catalog.form_text(0, 1)).is_equal("many items")
	assert_str(catalog.form_text(0, 2)).is_equal("many items")
	catalog.set_plural_enabled(0, false)
	assert_bool(catalog.has_plural(0)).is_false()
	assert_str(catalog.form_text(0, 0)).is_equal("one item")
	assert_int(catalog.form_count(0)).is_equal(1)


func test_plural_indexes_survive_a_round_trip() -> void:
	var text := _ru_header()
	text += "\nmsgid \"one\"\nmsgid_plural \"many\"\nmsgstr[0] \"раз\"\nmsgstr[1] \"раза\"\nmsgstr[2] \"раз\"\n"
	var catalog := _open(text)
	assert_str(catalog.form_text(0, 0)).is_equal("раз")
	assert_str(catalog.form_text(0, 1)).is_equal("раза")
	assert_str(catalog.form_text(0, 2)).is_equal("раз")
	assert_str(catalog.form_label(0, 2)).is_equal("msgstr[2]")
	var again := _open(catalog.to_text())
	assert_str(again.form_text(0, 2)).is_equal("раз")


func test_missing_nplurals_falls_back_to_two_forms() -> void:
	var catalog := _open("msgid \"\"\nmsgstr \"\"\n\"Language: ru\\n\"\n\n" + _entry("item", ""))
	assert_int(catalog.header_plural_count()).is_equal(2)
	catalog.set_plural_enabled(0, true)
	assert_int(catalog.form_count(0)).is_equal(2)


func test_placeholder_and_plural_problems_are_what_blocks_save() -> void:
	var text := _ru_header() + "\n" + _entry("Take {actor.desk}", "Возьми", "dialogue.item")
	text += "\n" + _entry("ui.inventory.stack", "{count} предмет")
	text += "\n" + _entry("Hello {{item_name}}", "Привет {{item_name}}")
	text += "\n" + _entry("Use {a} and {a}", "Нужно {a}")
	var catalog := _open(text)
	assert_str(catalog.issue_summary(0)).contains("нет {actor.desk}")
	assert_str(catalog.issue_summary(1)).is_empty()
	assert_str(catalog.issue_summary(2)).is_empty()
	assert_str(catalog.issue_summary(3)).contains("нет {a}")
	catalog.set_form(0, 0, "")
	assert_str(catalog.issue_summary(0)).is_empty()
	assert_bool(catalog.is_untranslated(0)).is_true()
	catalog.set_form(0, 0, "Возьми {actor.desk} {лишнее}")
	assert_str(catalog.issue_summary(0)).contains("лишнее {лишнее}")
	var signature := catalog.issue_signature(0)
	assert_str(signature).contains("dialogue.item")
	assert_int(catalog.issue_lines_except({signature: true}).size()).is_equal(1)
	catalog.set_form(0, 0, "совсем другое")
	assert_int(catalog.issue_lines_except({signature: true}).size()).is_equal(2)


func test_short_plural_is_reported_even_when_the_forms_are_empty() -> void:
	var text := _ru_header()
	text += "\nmsgid \"one\"\nmsgid_plural \"many\"\nmsgstr[0] \"\"\nmsgstr[1] \"\"\n"
	var catalog := _open(text)
	assert_str(catalog.issue_summary(0)).contains("nplurals=3")
	assert_bool(catalog.is_untranslated(0)).is_true()
	assert_int(catalog.issue_count()).is_equal(1)


func test_fuzzy_is_its_own_state_until_it_is_cleared() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Hello", "   ", "", "", true))
	var only_review := catalog.stats()
	assert_int(only_review.x).is_equal(0)
	assert_int(only_review.y).is_equal(0)
	assert_int(only_review.z).is_equal(1)
	catalog.set_form(0, 0, "Привет")
	assert_bool(catalog.is_fuzzy(0)).is_true()
	assert_int(catalog.stats().z).is_equal(1)
	assert_int(catalog.issue_count()).is_equal(0)
	assert_str(catalog.check_notice(0)).contains("На проверке")
	catalog.clear_fuzzy(0)
	assert_bool(catalog.is_fuzzy(0)).is_false()
	assert_int(catalog.stats().x).is_equal(1)


func test_clear_fuzzy_keeps_other_flags_and_drops_previous_fields() -> void:
	var text := "#. note.dialogue\n#, python-format, fuzzy\n#| msgid \"old\"\n" + _entry("Hello", "Привет")
	var catalog := _open(_ru_header() + "\n" + text)
	catalog.clear_fuzzy(0)
	assert_bool(catalog.is_fuzzy(0)).is_false()
	assert_str(catalog.comment_text(0)).is_equal("note.dialogue")
	assert_str(catalog.to_text()).contains("#, python-format")
	assert_bool(catalog.to_text().contains("#|")).is_false()


func test_search_add_and_remove_follow_the_visible_list() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Alpha", "альфа") + "\n" + _entry("Beta", "бета", "dialogue.beta"))
	assert_bool(catalog.matches(0, "АЛЬФА")).is_true()
	assert_bool(catalog.matches(1, "dialogue.beta")).is_true()
	assert_bool(catalog.matches(0, "")).is_true()
	assert_int(catalog.find_visible("Beta", 1, true)).is_equal(1)
	assert_int(catalog.find_visible("", 0, true)).is_equal(-1)
	var inserted := catalog.add_entry(0)
	assert_int(inserted).is_equal(1)
	assert_str(catalog.source_preview(1)).is_equal("(new)")
	assert_str(catalog.source_text(2)).is_equal("Beta")
	assert_int(catalog.remove_entry(1)).is_equal(1)
	assert_str(catalog.source_text(1)).is_equal("Beta")
	assert_int(catalog.remove_entry(1)).is_equal(0)
	assert_int(catalog.remove_entry(5)).is_equal(-1)
	assert_int(catalog.visible_count()).is_equal(1)


func test_editing_the_note_keeps_the_file_reference() -> void:
	var text := "#: room.tscn\n#. room.tscn\n" + _entry("A sign", "табличка")
	var catalog := _open(_ru_header() + "\n" + text)
	catalog.set_note(0, "своя\nпометка")
	assert_str(catalog.comment_text(0)).is_equal("своя пометка")
	assert_str(catalog.to_text()).contains("#: room.tscn")


func test_copy_source_overwrites_a_key_with_the_key() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("ui.hud.examine", "Осмотреть"))
	catalog.copy_source(0)
	assert_str(catalog.form_text(0, 0)).is_equal("ui.hud.examine")


func test_same_context_keeps_the_translation_when_the_english_diverges() -> void:
	var short := "Hello"
	var long := short + " " + "x".repeat(40)
	var catalog := _open(_ru_header() + "\n" + _entry(long, "Привет", "dialogue.note", "note.dialogue"))
	var messages: Array[Dictionary] = [_message(short, "dialogue.note", "", "note.dialogue")]
	var result := catalog.merge_template(messages, false, _sources("note.dialogue"))
	assert_bool(result.ok).is_true()
	assert_int(result.added.size()).is_equal(0)
	assert_int(result.removed.size()).is_equal(0)
	assert_int(result.reviewed.size()).is_equal(1)
	assert_str(catalog.source_text(0)).is_equal(short)
	assert_str(catalog.form_text(0, 0)).is_equal("Привет")
	assert_bool(catalog.is_fuzzy(0)).is_true()
	assert_str(catalog.context_text(0)).is_equal("dialogue.note")


func test_exact_match_does_not_touch_fuzzy_or_the_note() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Hello", "Привет", "dialogue.note", "note.dialogue", true))
	var text_before := catalog.to_text()
	var messages: Array[Dictionary] = [_message("Hello", "dialogue.note", "", "other.dialogue")]
	var result := catalog.merge_template(messages, false, _sources("note.dialogue"))
	assert_bool(result.ok).is_true()
	assert_int(result.kept).is_equal(1)
	assert_int(result.reviewed.size()).is_equal(0)
	assert_str(catalog.to_text()).is_equal(text_before)


func test_close_english_without_the_same_context_is_reused() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Open the door now", "Открой", "dialogue.old"))
	var messages: Array[Dictionary] = [_message("Open the door now!", "dialogue.new")]
	var result := catalog.merge_template(messages, false, PackedStringArray())
	assert_int(result.reviewed.size()).is_equal(1)
	assert_int(result.added.size()).is_equal(0)
	assert_str(catalog.context_text(0)).is_equal("dialogue.new")
	assert_str(catalog.form_text(0, 0)).is_equal("Открой")
	assert_bool(catalog.is_fuzzy(0)).is_true()


func test_distant_english_without_the_same_context_is_replaced() -> void:
	var long := "Hello" + " " + "x".repeat(40)
	var catalog := _open(_ru_header() + "\n" + _entry(long, "Привет", "dialogue.old"))
	var messages: Array[Dictionary] = [_message("Hello", "dialogue.new")]
	var result := catalog.merge_template(messages, false, PackedStringArray())
	assert_int(result.removed.size()).is_equal(1)
	assert_int(result.added.size()).is_equal(1)
	assert_str(catalog.source_text(0)).is_equal("Hello")
	assert_str(catalog.form_text(0, 0)).is_empty()
	assert_bool(catalog.is_fuzzy(0)).is_false()


func test_orphan_scene_sentence_is_dropped_and_a_dotted_key_is_kept() -> void:
	var text := _ru_header()
	text += "\n" + _entry("E / Z — examine", "", "", "room.tscn")
	text += "\n" + _entry("ui.hud.test_hint", "Тест", "", "room.tscn")
	text += "\n" + _entry("actor.you", "Ты")
	text += "\n" + _entry("ui.1bad", "нет", "", "room.tscn")
	var catalog := _open(text)
	var messages: Array[Dictionary] = [_message("ui.hud.move_hint", "", "", "room.tscn")]
	var result := catalog.merge_template(messages, false, _sources("room.tscn"))
	assert_bool(result.ok).is_true()
	assert_str(_joined(result.removed)).contains("E / Z — examine")
	assert_str(_joined(result.removed)).contains("ui.1bad")
	assert_bool(_has_source(catalog, "E / Z — examine")).is_false()
	assert_bool(_has_source(catalog, "ui.hud.test_hint")).is_true()
	assert_str(_from(result, "ui.hud.test_hint")).is_equal("room.tscn")
	assert_str(_from(result, "actor.you")).is_empty()
	assert_str(catalog.form_text(_index_of(catalog, "ui.hud.test_hint"), 0)).is_equal("Тест")


func test_duplicate_file_names_are_not_proof_enough_to_delete() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("A loose sign", "табличка", "", "room.tscn"))
	var sources := PackedStringArray(["res://a/room.tscn", "res://b/room.tscn"])
	var messages: Array[Dictionary] = [_message("ui.hud.move_hint")]
	var result := catalog.merge_template(messages, false, sources)
	assert_int(result.removed.size()).is_equal(0)
	assert_bool(_has_source(catalog, "A loose sign")).is_true()


func test_rewritten_note_still_drops_a_sentence_via_the_file_reference() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("ui.hud.move_hint", "Идите"))
	var first: Array[Dictionary] = [
		_message("ui.hud.move_hint", "", "", "room.tscn"),
		_message("A loose sign", "", "", "room.tscn"),
	]
	var added := catalog.merge_template(first, false, _sources("room.tscn"))
	assert_int(added.added.size()).is_equal(1)
	var sign_index := _index_of(catalog, "A loose sign")
	catalog.set_note(sign_index, "своя пометка")
	var second: Array[Dictionary] = [_message("ui.hud.move_hint", "", "", "room.tscn")]
	var removed := catalog.merge_template(second, false, _sources("room.tscn"))
	assert_str(_joined(removed.removed)).contains("A loose sign")
	assert_bool(_has_source(catalog, "A loose sign")).is_false()
	assert_str(catalog.form_text(_index_of(catalog, "ui.hud.move_hint"), 0)).is_equal("Идите")


func test_english_merge_skips_new_dialogue_and_keeps_existing_lines() -> void:
	var catalog := _open(_header("en", 2) + "\n" + _entry("Old line", "Old line", "dialogue.old"))
	var messages: Array[Dictionary] = [
		_message("Old line", "dialogue.old"),
		_message("New line", "dialogue.new", "", "new.dialogue"),
		_message("ui.hud.move_hint"),
	]
	var result := catalog.merge_template(messages, true, _sources("new.dialogue"))
	assert_int(result.skipped_dialogue).is_equal(1)
	assert_int(result.removed.size()).is_equal(0)
	assert_bool(_has_source(catalog, "Old line")).is_true()
	assert_bool(_has_source(catalog, "New line")).is_false()
	assert_str(catalog.form_text(_index_of(catalog, "ui.hud.move_hint"), 0)).is_empty()


func test_merge_aborts_when_the_template_loses_every_dialogue_line() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Hello", "Привет", "dialogue.note"))
	var text_before := catalog.to_text()
	var messages: Array[Dictionary] = [_message("ui.hud.move_hint")]
	var result := catalog.merge_template(messages, false, PackedStringArray())
	assert_bool(result.ok).is_false()
	assert_str(result.error).is_not_empty()
	assert_str(catalog.to_text()).is_equal(text_before)


func test_a_new_plural_keeps_the_old_translation_and_marks_it_fuzzy() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("one item", "один предмет"))
	var messages: Array[Dictionary] = [_message("one item", "", "many items")]
	var result := catalog.merge_template(messages, false, PackedStringArray())
	assert_int(result.reviewed.size()).is_equal(1)
	assert_bool(catalog.has_plural(0)).is_true()
	assert_str(catalog.plural_source(0)).is_equal("many items")
	assert_str(catalog.form_text(0, 0)).is_equal("один предмет")
	assert_int(catalog.form_count(0)).is_equal(3)
	assert_bool(catalog.is_fuzzy(0)).is_true()


func test_merge_never_drops_the_header() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("Gone", "ушло", "dialogue.gone"))
	var messages: Array[Dictionary] = [_message("Stay", "dialogue.stay")]
	var result := catalog.merge_template(messages, false, PackedStringArray())
	assert_bool(result.ok).is_true()
	assert_str(catalog.language()).is_equal("ru")
	assert_int(catalog.header_plural_count()).is_equal(3)


func test_changing_the_source_updates_a_matching_plural_source() -> void:
	var catalog := _open(_ru_header() + "\n" + _entry("item", ""))
	catalog.set_plural_enabled(0, true)
	catalog.set_source(0, "items")
	assert_str(catalog.plural_source(0)).is_equal("items")
	catalog.set_plural_source(0, "many items")
	catalog.set_source(0, "one item")
	assert_str(catalog.plural_source(0)).is_equal("many items")
	assert_bool(catalog.is_dialogue(0)).is_false()
	catalog.set_context(0, "dialogue.item")
	assert_bool(catalog.is_dialogue(0)).is_true()
	catalog.set_context(0, "")
	assert_str(catalog.context_text(0)).is_empty()


func _open(text: String) -> PoCatalog:
	var catalog: PoCatalog = PoCatalog.new()
	var parsed := catalog.parse(text)
	assert_bool(parsed).override_failure_message(catalog.error).is_true()
	return catalog


func _header(language: String, plurals: int) -> String:
	return "msgid \"\"\nmsgstr \"\"\n\"Language: %s\\n\"\n\"Plural-Forms: nplurals=%d; plural=(n != 1);\\n\"\n" % [language, plurals]


func _ru_header() -> String:
	return _header("ru", 3)


func _entry(msgid: String, msgstr: String, context: String = "", note: String = "", fuzzy: bool = false) -> String:
	var lines := PackedStringArray()
	if not note.is_empty():
		lines.append("#. " + note)
	if fuzzy:
		lines.append("#, fuzzy")
	if not context.is_empty():
		lines.append("msgctxt \"%s\"" % context)
	lines.append("msgid \"%s\"" % msgid)
	lines.append("msgstr \"%s\"" % msgstr)
	return "\n".join(lines) + "\n"


func _message(msgid: String, context: String = "", plural: String = "", note: String = "") -> Dictionary:
	return {"msgid": msgid, "context": context, "plural": plural, "note": note}


func _sources(file_name: String) -> PackedStringArray:
	return PackedStringArray(["res://levels/%s" % file_name])


func _joined(lines: PackedStringArray) -> String:
	return "\n".join(lines)


func _index_of(catalog: PoCatalog, msgid: String) -> int:
	for index in catalog.visible_count():
		if catalog.source_text(index) == msgid:
			return index
	return -1


func _has_source(catalog: PoCatalog, msgid: String) -> bool:
	return _index_of(catalog, msgid) >= 0


func _from(result: PoCatalog.MergeResult, msgid: String) -> String:
	for index in result.unseen.size():
		if result.unseen[index] == msgid:
			return result.unseen_from[index]
	return "<missing>"
