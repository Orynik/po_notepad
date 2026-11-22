@tool
extends HSplitContainer

const I18n := preload("../utilities/i18n.gd")

## The row list and the form for the selected entry.
## Edits the open catalog and emits the new PO text. Does not save or open files.

const Catalog := preload("../catalog/po_catalog.gd")
const EditorTheme := preload("../utilities/editor_theme.gd")

signal translation_edited(full_text: String)
signal entry_selected
signal notice(message: String)
signal search_cleared
signal issues_accepted(accepted: Dictionary)
signal locate_requested

const FILTER_ALL := 0
const FILTER_EMPTY := 1
const FILTER_FUZZY := 2
const FILTER_DIALOGUE := 3
const FILTER_KEYS := 4

var _catalog: Catalog
var _error := ""
var _selected := -1
var _filling := false
var _filter_mode := FILTER_ALL
var _query := ""

var _tree: Tree
var _filter_box: OptionButton
var _hint: Label
var _context_title: Label
var _context: LineEdit
var _advanced_toggle: Button
var _advanced: VBoxContainer
var _advanced_open := false
var _source_unlock: CheckButton
var _remove_confirm: ConfirmationDialog
var _note_title: Label
var _note: LineEdit
var _source_title: Label
var _source: TextEdit
var _plural: CheckButton
var _plural_source: TextEdit
var _issue: Label
var _clear_fuzzy: Button
var _copy_source: Button
var _accept_issue: Button
var _accepted: Dictionary = {}
var _forms: VBoxContainer
var _form_edits: Array[TextEdit] = []


func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size = EditorTheme.scaled_vec(0, 160)
	split_offset = int(EditorTheme.scaled(420))

	var list_side := VBoxContainer.new()
	list_side.size_flags_horizontal = SIZE_EXPAND_FILL
	list_side.size_flags_vertical = SIZE_EXPAND_FILL
	list_side.add_theme_constant_override("separation", 4)
	add_child(list_side)

	# One row above the list: what to show and how to move through it, then
	# adding and deleting rows. Plus and trash are the editor's usual list
	# icons, so they need no caption. Delete sits last, away from the filter.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	list_side.add_child(tools)

	_filter_box = OptionButton.new()
	_filter_box.add_item(I18n.t("All"))
	_filter_box.add_item(I18n.t("Empty"))
	_filter_box.add_item(I18n.t("Needs review"))
	_filter_box.add_item(I18n.t("Dialogue lines"))
	_filter_box.add_item(I18n.t("Keys (not dialogue)"))
	_filter_box.tooltip_text = I18n.t("Which entries to show")
	EditorTheme.bind(_filter_box.item_selected, _on_filter_selected)
	tools.add_child(_filter_box)

	var previous_empty := Button.new()
	previous_empty.text = I18n.t("Empty ↑")
	previous_empty.tooltip_text = I18n.t("Previous empty (Shift+F3)")
	EditorTheme.bind(previous_empty.pressed, _on_previous_empty)
	tools.add_child(previous_empty)

	var next_empty := Button.new()
	next_empty.text = I18n.t("Empty ↓")
	next_empty.tooltip_text = I18n.t("Next empty (F3)")
	EditorTheme.bind(next_empty.pressed, _on_next_empty)
	tools.add_child(next_empty)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(spacer)

	tools.add_child(EditorTheme.icon_button("Add", I18n.t("Add"), I18n.t("Insert a new entry after the selected one"), _on_add_pressed))
	tools.add_child(EditorTheme.icon_button("Remove", I18n.t("Delete"), I18n.t("Delete the selected entry"), _on_remove_pressed))

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.custom_minimum_size = EditorTheme.scaled_vec(280, 0)
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.set_column_title(0, I18n.t("Original"))
	_tree.set_column_title(1, I18n.t("Translation"))
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, true)
	_tree.set_column_clip_content(0, true)
	_tree.set_column_clip_content(1, true)
	_tree.set_column_custom_minimum_width(0, 140)
	_tree.set_column_custom_minimum_width(1, 140)
	_tree.hide_root = true
	_tree.hide_folding = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.tooltip_text = I18n.t("Double-click opens the .dialogue or script where the string is defined.")
	EditorTheme.bind(_tree.item_selected, _on_item_selected)
	EditorTheme.bind(_tree.item_activated, _on_item_activated)
	list_side.add_child(_tree)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	margin.custom_minimum_size = EditorTheme.scaled_vec(260, 0)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 2)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	add_child(margin)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	detail.size_flags_vertical = SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(detail)
	margin.add_child(scroll)

	_hint = Label.new()
	_hint.text = I18n.t("Select an entry.")
	_hint.size_flags_vertical = SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail.add_child(_hint)

	# Reading order: the original, then the translation (the main job), then
	# problems with it, then rarely used fields folded under "Advanced".
	_source_title = Label.new()
	_source_title.text = I18n.t("Original")
	_source_title.visible = false
	detail.add_child(_source_title)

	_source = TextEdit.new()
	_source.editable = false
	_source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_source.highlight_current_line = false
	_source.scroll_fit_content_height = true
	_source.custom_minimum_size = EditorTheme.scaled_vec(0, 48)
	_source.size_flags_horizontal = SIZE_EXPAND_FILL
	_source.size_flags_vertical = SIZE_FILL
	_source.placeholder_text = "msgid"
	_source.visible = false
	EditorTheme.bind(_source.text_changed, _on_source_changed)
	detail.add_child(_source)
	_style_editor(_source)

	_plural_source = TextEdit.new()
	_plural_source.editable = false
	_plural_source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_plural_source.highlight_current_line = false
	_plural_source.scroll_fit_content_height = true
	_plural_source.custom_minimum_size = EditorTheme.scaled_vec(0, 48)
	_plural_source.size_flags_horizontal = SIZE_EXPAND_FILL
	_plural_source.placeholder_text = "msgid_plural"
	_plural_source.visible = false
	EditorTheme.bind(_plural_source.text_changed, _on_plural_source_changed)
	detail.add_child(_plural_source)
	_style_editor(_plural_source)

	_forms = VBoxContainer.new()
	_forms.size_flags_horizontal = SIZE_EXPAND_FILL
	_forms.size_flags_vertical = SIZE_EXPAND_FILL
	_forms.add_theme_constant_override("separation", 4)
	detail.add_child(_forms)

	_issue = Label.new()
	_issue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_issue.visible = false
	detail.add_child(_issue)

	# Actions on the selected entry sit under its translation, not above the
	# list: copying the original and fixing flags change this entry only.
	var fix_row := HFlowContainer.new()
	fix_row.add_theme_constant_override("h_separation", 6)
	fix_row.add_theme_constant_override("v_separation", 4)
	detail.add_child(fix_row)

	_copy_source = Button.new()
	_copy_source.text = I18n.t("Copy original")
	_copy_source.icon = EditorTheme.icon("ActionCopy")
	_copy_source.tooltip_text = I18n.t("Write the original into the translation")
	_copy_source.visible = false
	EditorTheme.bind(_copy_source.pressed, _on_copy_source)
	fix_row.add_child(_copy_source)

	_clear_fuzzy = Button.new()
	_clear_fuzzy.text = I18n.t("Clear fuzzy flag")
	_clear_fuzzy.tooltip_text = I18n.t("Remove #, fuzzy. Godot ignores the entry while the flag is set.")
	_clear_fuzzy.visible = false
	EditorTheme.bind(_clear_fuzzy.pressed, _on_clear_fuzzy)
	fix_row.add_child(_clear_fuzzy)

	_accept_issue = Button.new()
	_accept_issue.text = I18n.t("Accept mismatch")
	_accept_issue.tooltip_text = I18n.t("The mismatch is intentional. The highlight turns yellow and saving will no longer ask.")
	_accept_issue.visible = false
	EditorTheme.bind(_accept_issue.pressed, _on_accept_issue)
	fix_row.add_child(_accept_issue)

	_advanced_toggle = Button.new()
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.flat = true
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advanced_toggle.tooltip_text = I18n.t("Context, note, plural forms, editing the original.")
	_advanced_toggle.visible = false
	EditorTheme.bind(_advanced_toggle.toggled, _on_advanced_toggled)
	detail.add_child(_advanced_toggle)

	_advanced = VBoxContainer.new()
	_advanced.add_theme_constant_override("separation", 4)
	_advanced.visible = false
	detail.add_child(_advanced)

	_source_unlock = CheckButton.new()
	_source_unlock.text = I18n.t("Edit original")
	_source_unlock.tooltip_text = I18n.t("The original is the entry key. If you change it, translations elsewhere will stop matching.")
	EditorTheme.bind(_source_unlock.toggled, _on_source_unlock_toggled)
	_advanced.add_child(_source_unlock)

	_plural = CheckButton.new()
	_plural.text = I18n.t("Plural forms")
	EditorTheme.bind(_plural.toggled, _on_plural_toggled)
	_advanced.add_child(_plural)

	_context_title = Label.new()
	_context_title.text = I18n.t("Context (msgctxt)")
	_context_title.tooltip_text = I18n.t("For a dialogue line this is the [ID:…] from the .dialogue file, so identical English text differs between places. Only with the Dialogue Manager plugin.")
	_advanced.add_child(_context_title)

	_context = LineEdit.new()
	_context.placeholder_text = "msgctxt"
	_context.tooltip_text = _context_title.tooltip_text
	EditorTheme.bind(_context.text_changed, _on_context_changed)
	_advanced.add_child(_context)

	_note_title = Label.new()
	_note_title.text = I18n.t("Note (#.)")
	_note_title.tooltip_text = I18n.t("The #. comment from the file. Usually the .dialogue name the string came from.")
	_advanced.add_child(_note_title)

	_note = LineEdit.new()
	_note.placeholder_text = "#."
	_note.tooltip_text = _note_title.tooltip_text
	EditorTheme.bind(_note.text_changed, _on_note_changed)
	_advanced.add_child(_note)

	_remove_confirm = ConfirmationDialog.new()
	_remove_confirm.title = I18n.t("Delete entry")
	_remove_confirm.ok_button_text = I18n.t("Delete entry")
	_remove_confirm.cancel_button_text = I18n.t("Keep")
	EditorTheme.bind(_remove_confirm.confirmed, _on_remove_confirmed)
	add_child(_remove_confirm)
	_update_advanced_toggle()


func parse_text(text: String, keep_selection: bool = false) -> bool:
	var keep := _selected if keep_selection else 0
	var catalog := Catalog.new()
	if not catalog.parse(text):
		_error = catalog.error
		_catalog = null
		_selected = -1
		if _tree != null:
			_tree.clear()
		_show_visible(-1)
		return false
	_catalog = catalog
	_error = ""
	_rebuild(keep)
	return true


func error_text() -> String:
	return _error


func catalog_language() -> String:
	if _catalog == null:
		return ""
	return _catalog.language()


func merge_messages(messages: Array[Dictionary], skip_new_context: bool, sources: PackedStringArray) -> Catalog.MergeResult:
	if _catalog == null:
		var missing := Catalog.MergeResult.new()
		missing.error = I18n.t("No file open")
		return missing
	var result := _catalog.merge_template(messages, skip_new_context, sources)
	if not result.ok:
		return result
	var switched := false
	if result.reviewed.size() > 0:
		_filter_mode = FILTER_FUZZY
		result.filter_label = I18n.t("Needs review")
		switched = true
	elif result.added.size() > 0:
		_filter_mode = FILTER_EMPTY
		result.filter_label = I18n.t("Empty")
		switched = true
	if switched:
		_query = ""
		if _filter_box != null:
			_filter_box.set_block_signals(true)
			_filter_box.select(_filter_mode)
			_filter_box.set_block_signals(false)
		search_cleared.emit()
	_rebuild(_selected)
	translation_edited.emit(_catalog.to_text())
	return result


func selected_index() -> int:
	return _selected


func selected_source() -> String:
	if _catalog == null or _selected < 0:
		return ""
	return _catalog.source_text(_selected)


func selected_context() -> String:
	if _catalog == null or _selected < 0:
		return ""
	return _catalog.context_text(_selected)


func selected_note() -> String:
	if _catalog == null or _selected < 0:
		return ""
	return _catalog.comment_text(_selected)


func _on_item_activated() -> void:
	locate_requested.emit()


func cursor_text() -> String:
	if _catalog == null or _selected < 0:
		return ""
	var shown := _shown_indexes()
	for index in shown.size():
		if shown[index] == _selected:
			return I18n.t("Entry %d / %d") % [index + 1, shown.size()]
	return I18n.t("Entry — / %d") % shown.size()


func stats_text() -> String:
	if _catalog == null:
		return ""
	var counts := _catalog.stats()
	var text := I18n.t("translated %d, empty %d, needs review %d") % [counts.x, counts.y, counts.z]
	var problems := _open_issue_count()
	if problems > 0:
		text += I18n.t(", errors %d") % problems
	return text


func has_catalog() -> bool:
	return _catalog != null


## Translated, empty, needs-review counts of the open catalog.
func stats_counts() -> Vector3i:
	if _catalog == null:
		return Vector3i.ZERO
	return _catalog.stats()


func set_accepted(accepted: Dictionary) -> void:
	_accepted = accepted.duplicate()
	if _catalog != null and _tree != null:
		_rebuild(_selected)


func set_query(query: String) -> void:
	if query == _query:
		return
	_query = query
	if _catalog != null and _tree != null:
		_rebuild(_selected)


func focus_list() -> void:
	if _tree != null:
		_tree.grab_focus()


func focus_editor() -> void:
	if not _form_edits.is_empty():
		_form_edits[0].grab_focus()
	elif _tree != null:
		_tree.grab_focus()


func find_from(query: String, start: int, forward: bool) -> int:
	if _catalog == null:
		return -1
	return _catalog.find_visible(query, start, forward)


func select_visible(index: int) -> void:
	if _tree == null or _tree.get_root() == null:
		return
	var item := _tree.get_root().get_first_child()
	while item != null:
		if int(item.get_metadata(0)) == index:
			item.select(0)
			_tree.scroll_to_item(item)
			return
		item = item.get_next()


func select_empty(forward: bool) -> bool:
	var shown := _shown_indexes()
	if shown.is_empty() or _catalog == null:
		return false
	var start := -1
	for index in shown.size():
		if shown[index] == _selected:
			start = index
			break
	var count := shown.size()
	var pos := 0
	if forward:
		pos = 0 if start < 0 else start + 1
		if pos >= count:
			pos = 0
	else:
		pos = count - 1 if start < 0 else start - 1
		if pos < 0:
			pos = count - 1
	for _step in count:
		var visible := shown[pos]
		if _catalog.is_untranslated(visible):
			select_visible(visible)
			return true
		if forward:
			pos += 1
			if pos >= count:
				pos = 0
		else:
			pos -= 1
			if pos < 0:
				pos = count - 1
	return false


func select_neighbor(forward: bool) -> bool:
	var shown := _shown_indexes()
	if shown.is_empty():
		return false
	var start := -1
	for index in shown.size():
		if shown[index] == _selected:
			start = index
			break
	var count := shown.size()
	var pos := 0
	if forward:
		pos = 0 if start < 0 else start + 1
		if pos >= count:
			pos = 0
	else:
		pos = count - 1 if start < 0 else start - 1
		if pos < 0:
			pos = count - 1
	select_visible(shown[pos])
	return true


func _rebuild(select_index: int) -> void:
	if _tree == null or _catalog == null:
		return
	_tree.clear()
	_update_filter_labels()
	var root := _tree.create_item()
	var shown := _shown_indexes()
	var chosen: TreeItem = null
	for index in shown.size():
		var visible := shown[index]
		var item := _tree.create_item(root)
		item.set_metadata(0, visible)
		_paint_row(item, visible)
		if visible == select_index:
			chosen = item
	if shown.is_empty():
		_selected = -1
		_hint.text = I18n.t("Nothing matches the current filter and search.") if _catalog.visible_count() > 0 else I18n.t("The catalog has no entries. Add the first one with the + button above the list.")
		_show_visible(-1)
		return
	if chosen == null:
		chosen = root.get_first_child()
	if chosen == null:
		_selected = -1
		_show_visible(-1)
		return
	if int(chosen.get_metadata(0)) != select_index:
		select_index = int(chosen.get_metadata(0))
	_tree.set_block_signals(true)
	chosen.select(0)
	_tree.set_block_signals(false)
	_tree.scroll_to_item(chosen)
	_show_visible(select_index)


func _update_filter_labels() -> void:
	if _filter_box == null or _catalog == null:
		return
	var counts := _catalog.stats()
	_filter_box.set_item_text(FILTER_EMPTY, I18n.t("Empty (%d)") % counts.y)
	_filter_box.set_item_text(FILTER_FUZZY, I18n.t("Needs review (%d)") % counts.z)


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	_show_visible(int(item.get_metadata(0)))


func _show_visible(index: int) -> void:
	_selected = index
	_filling = true
	_clear_forms()
	var has := _catalog != null and index >= 0 and index < _catalog.visible_count()
	_hint.visible = not has
	_source_title.visible = has
	_source.visible = has
	_plural_source.visible = false
	_advanced_toggle.visible = has
	_advanced.visible = has and _advanced_open
	_source_unlock.set_pressed_no_signal(false)
	_set_source_editable(false)
	if not has:
		_filling = false
		_refresh_checks()
		entry_selected.emit()
		return
	_context.text = _catalog.context_text(index)
	_note.text = _catalog.comment_text(index)
	_source.text = _catalog.source_text(index)
	_plural.set_pressed_no_signal(_catalog.has_plural(index))
	if _catalog.has_plural(index):
		_plural_source.visible = true
		_plural_source.text = _catalog.plural_source(index)
	var count := _catalog.form_count(index)
	for slot in count:
		var label := Label.new()
		label.text = _catalog.form_label(index, slot)
		_forms.add_child(label)
		var edit := TextEdit.new()
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.highlight_current_line = true
		edit.custom_minimum_size = EditorTheme.scaled_vec(0, 64 if count > 1 else 96)
		edit.size_flags_horizontal = SIZE_EXPAND_FILL
		edit.size_flags_vertical = SIZE_EXPAND_FILL
		edit.text = _catalog.form_text(index, slot)
		edit.set_meta(&"form", slot)
		_style_editor(edit)
		EditorTheme.bind(edit.text_changed, _on_form_changed.bind(edit))
		_forms.add_child(edit)
		_form_edits.append(edit)
	_filling = false
	_refresh_checks()
	entry_selected.emit()


func _on_add_pressed() -> void:
	if _catalog == null:
		return
	var index := _catalog.add_entry(_selected)
	if index < 0:
		return
	_filter_mode = FILTER_ALL
	_query = ""
	if _filter_box != null:
		_filter_box.set_block_signals(true)
		_filter_box.select(FILTER_ALL)
		_filter_box.set_block_signals(false)
	search_cleared.emit()
	_rebuild(index)
	translation_edited.emit(_catalog.to_text())
	# A new entry has no original yet, so the key field starts unlocked.
	_advanced_open = true
	_update_advanced_toggle()
	_advanced.visible = true
	_source_unlock.set_pressed_no_signal(true)
	_set_source_editable(true)
	_source.grab_focus()


func _on_filter_selected(index: int) -> void:
	_filter_mode = index
	if _catalog != null and _tree != null:
		_rebuild(_selected)


func _on_previous_empty() -> void:
	_go_empty(false)


func _on_next_empty() -> void:
	_go_empty(true)


func _go_empty(forward: bool) -> void:
	if _catalog == null:
		return
	if not select_empty(forward):
		notice.emit(I18n.t("No empty entries"))
		return
	notice.emit(I18n.t("Empty entry"))


func _on_copy_source() -> void:
	if _catalog == null or _selected < 0:
		return
	_catalog.copy_source(_selected)
	_show_visible(_selected)
	_update_row(_selected)
	translation_edited.emit(_catalog.to_text())
	notice.emit(I18n.t("Original copied"))


func _on_advanced_toggled(open: bool) -> void:
	_advanced_open = open
	_advanced.visible = open and _selected >= 0
	_update_advanced_toggle()


func _update_advanced_toggle() -> void:
	_advanced_toggle.set_pressed_no_signal(_advanced_open)
	_advanced_toggle.text = ("▾ " if _advanced_open else "▸ ") + I18n.t("Advanced")


func _on_source_unlock_toggled(enabled: bool) -> void:
	_set_source_editable(enabled)
	if enabled:
		_source.grab_focus()


func _set_source_editable(enabled: bool) -> void:
	_source.editable = enabled
	_plural_source.editable = enabled


func _on_remove_pressed() -> void:
	if _catalog == null or _selected < 0:
		return
	var preview := _catalog.source_preview(_selected)
	_remove_confirm.dialog_text = I18n.t("Delete entry \"%s\"?\nThis cannot be undone. While the file is unsaved you can reload it from disk.") % preview
	_remove_confirm.popup_centered()


func _on_remove_confirmed() -> void:
	if _catalog == null or _selected < 0:
		return
	var index := _catalog.remove_entry(_selected)
	_rebuild(index)
	translation_edited.emit(_catalog.to_text())


func _on_source_changed() -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	_catalog.set_source(_selected, _source.text)
	if _plural_source.visible:
		_filling = true
		_plural_source.text = _catalog.plural_source(_selected)
		_filling = false
	_update_row(_selected)
	_refresh_checks()
	translation_edited.emit(_catalog.to_text())


func _on_context_changed(value: String) -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	_catalog.set_context(_selected, value)
	translation_edited.emit(_catalog.to_text())


func _on_note_changed(value: String) -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	_catalog.set_note(_selected, value)
	translation_edited.emit(_catalog.to_text())


func _on_plural_toggled(enabled: bool) -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	_catalog.set_plural_enabled(_selected, enabled)
	var index := _selected
	_show_visible(index)
	_update_row(index)
	translation_edited.emit(_catalog.to_text())


func _on_plural_source_changed() -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	_catalog.set_plural_source(_selected, _plural_source.text)
	_update_row(_selected)
	_refresh_checks()
	translation_edited.emit(_catalog.to_text())


func _on_form_changed(edit: TextEdit) -> void:
	if _filling or _catalog == null or _selected < 0:
		return
	var slot := int(edit.get_meta(&"form"))
	_catalog.set_form(_selected, slot, edit.text)
	_update_row(_selected)
	_refresh_checks()
	translation_edited.emit(_catalog.to_text())


func _on_accept_issue() -> void:
	if _catalog == null or _selected < 0:
		return
	var signature := _catalog.issue_signature(_selected)
	if signature.is_empty():
		return
	_accepted[signature] = true
	_rebuild(_selected)
	issues_accepted.emit(_accepted.duplicate())
	notice.emit(I18n.t("Mismatch accepted"))


func _is_accepted(index: int) -> bool:
	if _catalog == null:
		return false
	var signature := _catalog.issue_signature(index)
	return not signature.is_empty() and _accepted.has(signature)


func _open_issue_count() -> int:
	if _catalog == null:
		return 0
	var count := 0
	for index in _catalog.visible_count():
		var signature := _catalog.issue_signature(index)
		if signature.is_empty() or _accepted.has(signature):
			continue
		count += 1
	return count


func _on_clear_fuzzy() -> void:
	if _catalog == null or _selected < 0:
		return
	var index := _selected
	_catalog.clear_fuzzy(index)
	_rebuild(index)
	translation_edited.emit(_catalog.to_text())
	notice.emit(I18n.t("Flag cleared"))


func _refresh_checks() -> void:
	var has := _catalog != null and _selected >= 0 and _selected < _catalog.visible_count()
	var notice_text := ""
	var fuzzy := false
	var broken := false
	var accepted := false
	if has:
		notice_text = _catalog.check_notice(_selected)
		fuzzy = _catalog.is_fuzzy(_selected)
		broken = not _catalog.issue_summary(_selected).is_empty()
		accepted = _is_accepted(_selected)
		if accepted:
			notice_text = I18n.t("Accepted when saving.\n") + notice_text
	if _issue != null:
		_issue.text = notice_text
		_issue.visible = has and not notice_text.is_empty()
		var marked := broken and not accepted
		var bad := EditorTheme.theme_color(&"error_color", Color(0.95, 0.45, 0.4))
		var warn := EditorTheme.theme_color(&"warning_color", Color(0.95, 0.78, 0.35))
		_issue.add_theme_color_override(&"font_color", bad if marked else warn)
	if _copy_source != null:
		_copy_source.visible = has
	if _clear_fuzzy != null:
		_clear_fuzzy.visible = has and fuzzy
	if _accept_issue != null:
		_accept_issue.visible = has and broken and not accepted


func _paint_row(item: TreeItem, index: int) -> void:
	var translation := _catalog.translation_preview(index)
	var empty := _catalog.is_untranslated(index)
	if empty:
		translation = I18n.t("(empty)")
	item.set_text(0, _catalog.source_preview(index))
	item.set_text(1, translation)
	item.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_TRIM_ELLIPSIS)
	var problem := _catalog.issue_summary(index)
	var fuzzy := _catalog.is_fuzzy(index)
	var accepted := not problem.is_empty() and _is_accepted(index)
	if not problem.is_empty() and not accepted:
		item.set_custom_color(1, EditorTheme.theme_color(&"error_color", Color(0.95, 0.45, 0.4)))
		item.set_icon(1, EditorTheme.icon("StatusError"))
		item.set_tooltip_text(1, problem)
	elif not problem.is_empty():
		item.set_custom_color(1, EditorTheme.theme_color(&"warning_color", Color(0.95, 0.78, 0.35)))
		item.set_icon(1, EditorTheme.icon("StatusWarning"))
		item.set_tooltip_text(1, I18n.t("Accepted when saving.") + problem)
	elif fuzzy:
		item.set_custom_color(1, EditorTheme.theme_color(&"warning_color", Color(0.95, 0.78, 0.35)))
		item.set_icon(1, EditorTheme.icon("StatusWarning"))
		item.set_tooltip_text(1, I18n.t("Needs review. Godot ignores the entry until the flag is cleared."))
	elif empty:
		item.set_custom_color(1, EditorTheme.theme_color(&"font_disabled_color", Color(0.65, 0.65, 0.65)))
		item.set_icon(1, null)
		item.set_tooltip_text(1, I18n.t("Empty translation"))
	else:
		item.clear_custom_color(1)
		item.set_icon(1, null)
		item.set_tooltip_text(1, "")


func _update_row(index: int) -> void:
	if _tree == null or _tree.get_root() == null or _catalog == null:
		return
	var item := _tree.get_root().get_first_child()
	while item != null:
		if int(item.get_metadata(0)) == index:
			_paint_row(item, index)
			return
		item = item.get_next()


func _shown_indexes() -> PackedInt32Array:
	var shown := PackedInt32Array()
	if _catalog == null:
		return shown
	for index in _catalog.visible_count():
		if _passes(index):
			shown.append(index)
	return shown


func _passes(index: int) -> bool:
	match _filter_mode:
		FILTER_EMPTY:
			if not _catalog.is_untranslated(index):
				return false
		FILTER_FUZZY:
			if not _catalog.is_fuzzy(index):
				return false
		FILTER_DIALOGUE:
			if not _catalog.is_dialogue(index):
				return false
		FILTER_KEYS:
			if _catalog.is_dialogue(index):
				return false
	return _catalog.matches(index, _query.strip_edges())


func _clear_forms() -> void:
	if _forms == null:
		return
	for child: Node in _forms.get_children():
		_forms.remove_child(child)
		child.queue_free()
	_form_edits.clear()


func _style_editor(edit: TextEdit) -> void:
	if edit == null or not Engine.is_editor_hint():
		return
	var theme := EditorInterface.get_editor_theme()
	if theme == null:
		return
	var font := theme.get_font(&"source", &"EditorFonts")
	if font != null:
		edit.add_theme_font_override(&"font", font)
	var font_size := theme.get_font_size(&"source_size", &"EditorFonts")
	if font_size > 0:
		edit.add_theme_font_size_override(&"font_size", font_size)

