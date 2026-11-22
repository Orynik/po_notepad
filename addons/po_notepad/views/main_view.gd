@tool
extends Control

const I18n := preload("../utilities/i18n.gd")

## The editor screen: which catalog is open, list or raw text, and the
## dialogs around save, reload, and POT merge. The document is catalog/.
## Drafts, accepted checks, and "go to source" live in utilities/.

const PoEntryView := preload("../components/entry_view.gd")
const PoTemplate := preload("../catalog/po_template.gd")
const PoCatalog := preload("../catalog/po_catalog.gd")
const SourceLocator := preload("../utilities/source_locator.gd")
const LocalStore := preload("../utilities/local_store.gd")
const EditorTheme := preload("../utilities/editor_theme.gd")
const MergeReport := preload("../utilities/merge_report.gd")

signal saved(path: String)

var current_path: String:
	get:
		return _path

var _path := ""
var _text := ""
var _saved_text := ""
var _recovered_text := ""
var _pending_path := ""
var _resume_path := ""
var _acks: Dictionary = {}
var _dirty := false
var _loading := false
var _recovery_waiting := false
var _applying_theme := false
var _store := LocalStore.new()

var _box: VBoxContainer
var _code: CodeEdit
var _empty: Label
const LANGUAGE_CHOICES: Array[String] = ["auto", "ru", "en"]

var _stats_cache: Dictionary = {}
var _language_box: OptionButton
var _cursor_label: Label
var _count_label: Label
var _status_label: Label
var _find_edit: LineEdit
var _save_button: Button
var _reload_button: Button
var _merge_button: Button
var _report: AcceptDialog
var _report_body: TextEdit
var _save_check: ConfirmationDialog
var _save_check_body: TextEdit
var _wrap: CheckButton
var _list_button: Button
var _text_button: Button
var _dirty_label: Label
var _find_prev_button: Button
var _find_next_button: Button
var _status_timer: Timer
var _locale_list: ItemList
var _entry_view: PoEntryView
var _list_mode := true
var _highlighter: CodeHighlighter
var _recovery_timer: Timer
var _open_dialog: EditorFileDialog
var _confirm: ConfirmationDialog
var _reload_confirm: ConfirmationDialog
var _recover: ConfirmationDialog


func _ready() -> void:
	_build()


func _build() -> void:
	# The editor would run our strings through its own translation (a Russian
	# editor turns "Open" into "Открыть" even when this view is set to English),
	# which is how the two languages got mixed. Our texts come from I18n only.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# The editor main screen is a VBoxContainer: Fill+Expand gives this root
	# the leftover viewport. The margin inside uses full-rect anchors, which
	# a plain Control parent honors.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.size_flags_vertical = SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 4)
	margin.add_child(_box)
	var box := _box

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	box.add_child(toolbar)

	# File actions are icon-only: folder, floppy and reload read faster than
	# words and match the editor's own toolbars. The name stays in the tooltip.
	toolbar.add_child(EditorTheme.icon_button("Load", I18n.t("Open"), I18n.t("Open a .po file"), _on_open_pressed))
	_save_button = EditorTheme.icon_button("Save", I18n.t("Save"), I18n.t("Save (Ctrl+S)"), save_if_dirty)
	toolbar.add_child(_save_button)
	_reload_button = EditorTheme.icon_button("Reload", I18n.t("Reload"), I18n.t("Reload the file from disk"), _on_reload_pressed)
	toolbar.add_child(_reload_button)
	toolbar.add_child(VSeparator.new())
	# No icon says "merge with a template", so this one keeps its words.
	_merge_button = _tool_button(I18n.t("Merge POT"), "MoveDown", I18n.t("Read the files from Localization → POT Generation and merge them into the open catalog."), _on_merge_pressed)
	toolbar.add_child(_merge_button)
	toolbar.add_child(VSeparator.new())

	_dirty_label = Label.new()
	_dirty_label.text = I18n.t("● unsaved")
	_dirty_label.add_theme_color_override(&"font_color", EditorTheme.theme_color(&"warning_color", Color(0.95, 0.78, 0.35)))
	_dirty_label.visible = false
	toolbar.add_child(_dirty_label)

	# The open file is shown by the locale list on the left, so the toolbar
	# keeps only a spacer that pushes search and mode buttons to the right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_find_edit = LineEdit.new()
	_find_edit.placeholder_text = I18n.t("Search (Ctrl+F)")
	_find_edit.custom_minimum_size = EditorTheme.scaled_vec(180, 0)
	_find_edit.clear_button_enabled = true
	_find_edit.tooltip_text = I18n.t("In List mode filters entries by original, translation and context. In Text mode searches the file (Enter — next, Shift+Enter — previous).")
	EditorTheme.bind(_find_edit.text_changed, _on_find_text_changed)
	EditorTheme.bind(_find_edit.gui_input, _on_find_gui_input)
	toolbar.add_child(_find_edit)
	_find_prev_button = EditorTheme.icon_button("ArrowLeft", I18n.t("Previous match"), I18n.t("Previous match"), _on_find_prev)
	toolbar.add_child(_find_prev_button)
	_find_next_button = EditorTheme.icon_button("ArrowRight", I18n.t("Next match"), I18n.t("Next match"), _on_find_next)
	toolbar.add_child(_find_next_button)

	toolbar.add_child(VSeparator.new())

	var mode_group := ButtonGroup.new()
	_list_button = Button.new()
	_list_button.text = I18n.t("List")
	_list_button.toggle_mode = true
	_list_button.button_group = mode_group
	_list_button.tooltip_text = I18n.t("Edit one entry at a time.")
	EditorTheme.bind(_list_button.toggled, _on_list_toggled)
	_list_button.set_pressed_no_signal(true)
	toolbar.add_child(_list_button)
	_text_button = Button.new()
	_text_button.text = I18n.t("Text")
	_text_button.toggle_mode = true
	_text_button.button_group = mode_group
	_text_button.tooltip_text = I18n.t("Edit the .po file as plain text.")
	toolbar.add_child(_text_button)

	var work := HSplitContainer.new()
	work.size_flags_horizontal = SIZE_EXPAND_FILL
	work.size_flags_vertical = SIZE_EXPAND_FILL
	work.split_offset = int(EditorTheme.scaled(180))
	box.add_child(work)

	var locales := VBoxContainer.new()
	locales.custom_minimum_size = EditorTheme.scaled_vec(160, 0)
	locales.size_flags_vertical = SIZE_EXPAND_FILL
	locales.add_theme_constant_override("separation", 4)
	work.add_child(locales)

	var locale_title := Label.new()
	locale_title.text = I18n.t("Locales")
	locales.add_child(locale_title)

	_locale_list = ItemList.new()
	_locale_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_locale_list.size_flags_vertical = SIZE_EXPAND_FILL
	_locale_list.fixed_icon_size = Vector2i(16, 16)
	_locale_list.tooltip_text = I18n.t("Catalogs from Project Settings → Localization → Translations. Any other .po opens with the folder button on the toolbar.")
	EditorTheme.bind(_locale_list.item_selected, _on_locale_selected)
	locales.add_child(_locale_list)

	var editor := VBoxContainer.new()
	editor.size_flags_horizontal = SIZE_EXPAND_FILL
	editor.size_flags_vertical = SIZE_EXPAND_FILL
	work.add_child(editor)

	_code = CodeEdit.new()
	_code.size_flags_horizontal = SIZE_EXPAND_FILL
	_code.size_flags_vertical = SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.highlight_current_line = true
	_code.draw_tabs = true
	_code.deselect_on_focus_loss_enabled = false
	_code.auto_brace_completion_enabled = false
	_code.indent_automatic = false
	_code.minimap_draw = false
	_code.scroll_smooth = true
	_code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_code.custom_minimum_size = EditorTheme.scaled_vec(0, 160)
	_code.editable = false
	EditorTheme.bind(_code.text_changed, _on_text_changed)
	EditorTheme.bind(_code.caret_changed, _update_cursor)
	editor.add_child(_code)

	_entry_view = PoEntryView.new()
	_entry_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_entry_view.size_flags_vertical = SIZE_EXPAND_FILL
	EditorTheme.bind(_entry_view.translation_edited, _on_entries_edited)
	EditorTheme.bind(_entry_view.entry_selected, _update_cursor)
	EditorTheme.bind(_entry_view.notice, _set_status)
	EditorTheme.bind(_entry_view.search_cleared, _on_search_cleared)
	EditorTheme.bind(_entry_view.issues_accepted, _on_issues_accepted)
	EditorTheme.bind(_entry_view.locate_requested, _on_locate_requested)
	editor.add_child(_entry_view)

	_empty = Label.new()
	_empty.text = I18n.t("No file open.\nPick a locale on the left or open a .po with the folder button on the toolbar.\nIf the list is empty, add a .po in Project Settings → Localization → Translations.")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_horizontal = SIZE_EXPAND_FILL
	_empty.size_flags_vertical = SIZE_EXPAND_FILL
	editor.add_child(_empty)

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 12)
	box.add_child(status)
	_cursor_label = Label.new()
	status.add_child(_cursor_label)
	_count_label = Label.new()
	status.add_child(_count_label)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(_status_label)

	# Rarely used view and interface settings live in the status bar so the
	# toolbar keeps only what the work needs.
	_wrap = CheckButton.new()
	_wrap.text = I18n.t("Wrap lines")
	_wrap.tooltip_text = I18n.t("Wrap long lines (Text mode only)")
	EditorTheme.bind(_wrap.toggled, _on_wrap_toggled)
	status.add_child(_wrap)
	status.add_child(VSeparator.new())

	_language_box = OptionButton.new()
	_language_box.add_item(I18n.t("Auto"))
	_language_box.add_item("Русский")
	_language_box.add_item("English")
	_language_box.tooltip_text = I18n.t("Interface language")
	_language_box.select(LANGUAGE_CHOICES.find(I18n.preference()))
	EditorTheme.bind(_language_box.item_selected, _on_language_selected)
	status.add_child(_language_box)

	_recovery_timer = Timer.new()
	_recovery_timer.one_shot = true
	_recovery_timer.wait_time = 0.5
	EditorTheme.bind(_recovery_timer.timeout, _write_recovery)
	add_child(_recovery_timer)

	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.wait_time = 5.0
	EditorTheme.bind(_status_timer.timeout, _clear_status)
	add_child(_status_timer)

	_open_dialog = EditorFileDialog.new()
	_open_dialog.title = I18n.t("Open a .po catalog")
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.po", "Gettext PO")
	EditorTheme.bind(_open_dialog.file_selected, _on_file_selected)
	_mount_dialog(_open_dialog)

	_confirm = ConfirmationDialog.new()
	_confirm.title = I18n.t("Unsaved changes")
	_confirm.ok_button_text = I18n.t("Save")
	_confirm.cancel_button_text = I18n.t("Cancel")
	var discard := _confirm.add_button(I18n.t("Don't save"), false, "discard")
	discard.focus_mode = Control.FOCUS_ALL
	EditorTheme.bind(_confirm.confirmed, _on_confirm_save)
	EditorTheme.bind(_confirm.custom_action, _on_confirm_discard)
	EditorTheme.bind(_confirm.canceled, _on_confirm_canceled)
	_mount_dialog(_confirm)

	_reload_confirm = ConfirmationDialog.new()
	_reload_confirm.title = I18n.t("Reload file")
	_reload_confirm.ok_button_text = I18n.t("Discard and reload")
	_reload_confirm.cancel_button_text = I18n.t("Cancel")
	EditorTheme.bind(_reload_confirm.confirmed, _on_reload_confirmed)
	_mount_dialog(_reload_confirm)

	_recover = ConfirmationDialog.new()
	_recover.title = I18n.t("Unsaved edits found")
	_recover.ok_button_text = I18n.t("Restore")
	_recover.cancel_button_text = I18n.t("Discard")
	EditorTheme.bind(_recover.confirmed, _on_restore)
	EditorTheme.bind(_recover.canceled, _on_discard_recovery)
	_mount_dialog(_recover)

	_report = AcceptDialog.new()
	_report.title = I18n.t("POT merge")
	_report.ok_button_text = I18n.t("Close")
	_report_body = TextEdit.new()
	_report_body.editable = false
	_report_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_report_body.custom_minimum_size = EditorTheme.scaled_vec(560, 320)
	_report_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.add_child(_report_body)
	_mount_dialog(_report)

	_save_check = ConfirmationDialog.new()
	_save_check.title = I18n.t("Check before saving")
	_save_check.ok_button_text = I18n.t("Save anyway")
	_save_check.cancel_button_text = I18n.t("Back to editing")
	_save_check_body = TextEdit.new()
	_save_check_body.editable = false
	_save_check_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_save_check_body.custom_minimum_size = EditorTheme.scaled_vec(560, 240)
	_save_check_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_check_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_check.add_child(_save_check_body)
	EditorTheme.bind(_save_check.confirmed, _on_save_despite_issues)
	EditorTheme.bind(_save_check.canceled, _on_save_issues_canceled)
	_mount_dialog(_save_check)

	_cursor_label.custom_minimum_size = EditorTheme.scaled_vec(150, 0)
	_apply_theme()
	_refresh()
	_reload_locales()
	_sync_editor_min_width.call_deferred()


func _exit_tree() -> void:
	if _recovery_timer != null:
		_recovery_timer.stop()
	if _dirty and _code != null:
		_write_recovery()
	_release_dialog(_open_dialog)
	_release_dialog(_confirm)
	_release_dialog(_reload_confirm)
	_release_dialog(_recover)
	_release_dialog(_report)
	_release_dialog(_save_check)


func fit_layout() -> void:
	_reload_locales()
	_sync_editor_min_width()


## The list view needs more width than the raw text. Giving the text view the
## same minimum keeps the splitter, and the locale list beside it, from
## jumping when the mode changes.
func _sync_editor_min_width() -> void:
	if _code == null or _entry_view == null:
		return
	_code.custom_minimum_size.x = _entry_view.get_combined_minimum_size().x


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _code != null and not _applying_theme:
		_apply_theme()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _recovery_waiting and is_visible_in_tree():
		_offer_recovery()


func _mount_dialog(dialog: Window) -> void:
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(dialog)


func _on_language_selected(index: int) -> void:
	I18n.set_preference(LANGUAGE_CHOICES[index])
	_rebuild_ui()


## Builds the screen again in the chosen language. The open file, unsaved
## text, and accepted checks live in members, so they survive the rebuild.
func _rebuild_ui() -> void:
	var was_list := _list_mode
	var selected := _entry_view.selected_index() if _entry_view != null else -1
	var query := _find_edit.text if _find_edit != null else ""
	_recovery_timer.stop()
	_status_timer.stop()
	_release_dialog(_open_dialog)
	_release_dialog(_confirm)
	_release_dialog(_reload_confirm)
	_release_dialog(_recover)
	_release_dialog(_report)
	_release_dialog(_save_check)
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_highlighter = null
	_build()
	if not _path.is_empty():
		_loading = true
		_code.text = _text
		_loading = false
		_list_mode = was_list
		if _list_mode and not _entry_view.parse_text(_text):
			_list_mode = false
		_set_mode_buttons(_list_mode)
		_entry_view.set_accepted(_acks)
		_find_edit.text = query
		_entry_view.set_query(query)
		if selected >= 0:
			_entry_view.select_visible(selected)
		_refresh()


func _release_dialog(dialog: Node) -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _dialog_open() or not _owns_focus():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.alt_pressed or key.meta_pressed:
		return
	if key.ctrl_pressed and not key.shift_pressed and key.keycode == KEY_S:
		if _dirty:
			var wrote := save_if_dirty()
			if not wrote:
				return
		else:
			_set_status(I18n.t("No changes"))
		return
	if key.ctrl_pressed and not key.shift_pressed and (key.keycode == KEY_DOWN or key.keycode == KEY_UP):
		if _list_mode and _entry_view.select_neighbor(key.keycode == KEY_DOWN):
			_update_cursor()
			_entry_view.focus_editor()
			get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and not key.shift_pressed and key.keycode == KEY_F:
		_focus_find()
		get_viewport().set_input_as_handled()
	elif not key.ctrl_pressed and key.keycode == KEY_F3:
		if _list_mode:
			_goto_empty(not key.shift_pressed)
		else:
			_find(not key.shift_pressed)
		get_viewport().set_input_as_handled()


func is_dirty() -> bool:
	return _dirty


func request_open(path: String) -> void:
	if path.get_extension().to_lower() != "po":
		_set_status(I18n.t("Not a .po file"))
		return
	if path == _path:
		if _list_mode:
			_entry_view.focus_editor()
		else:
			_code.grab_focus()
		return
	if _dirty:
		_pending_path = path
		_confirm.dialog_text = I18n.t("Save changes to %s before opening another file?") % _path.get_file()
		_confirm.popup_centered()
		return
	if not load_path(path, true, true):
		return


func load_path(path: String, focus: bool, check_recovery: bool) -> bool:
	if path.get_extension().to_lower() != "po":
		_set_status(I18n.t("Not a .po file"))
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		_set_status(I18n.t("Could not open %s: %s") % [path.get_file(), error_string(err)])
		return false
	var text := file.get_as_text()
	file.close()
	_show_text(path, text, focus)
	if check_recovery:
		_offer_recovery.call_deferred()
	return true


func save_if_dirty() -> bool:
	if not _dirty:
		return true
	if _path.is_empty():
		_set_status(I18n.t("No file open"))
		_resume_path = ""
		return false
	var issues := _save_issues()
	if not issues.is_empty():
		_show_save_issues(issues)
		return false
	if not _write_disk():
		_resume_path = ""
		return false
	return true


func note_moved(old_path: String, new_path: String) -> void:
	if old_path != _path:
		return
	_recovery_timer.stop()
	_delete_recovery()
	_path = new_path
	if _dirty:
		_write_recovery()
	_refresh()
	_reload_locales()
	_set_status(I18n.t("File moved"))


func note_removed(path: String) -> void:
	if path != _path:
		return
	_reload_locales()
	if _dirty:
		_set_status(I18n.t("File was removed from disk. Save to write it again."))
	else:
		_set_status(I18n.t("File was removed from disk."))


func _show_text(path: String, text: String, focus: bool) -> void:
	_recovery_timer.stop()
	_path = path
	_text = text
	_loading = true
	_code.text = text
	_code.set_caret_line(0)
	_code.set_caret_column(0)
	_code.scroll_vertical = 0
	_code.scroll_horizontal = 0
	_loading = false
	_saved_text = _text
	_dirty = false
	_load_acks()
	if not _entry_view.parse_text(text) and _list_mode:
		_list_mode = false
		_set_mode_buttons(false)
		_refresh()
		_set_status(I18n.t("Could not read entries, showing text: %s") % _entry_view.error_text())
	else:
		_refresh()
	_entry_view.set_accepted(_acks)
	if focus:
		if _list_mode:
			_entry_view.focus_list()
		else:
			_code.grab_focus()


func _write_disk() -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		_set_status(I18n.t("Could not save: %s") % error_string(err))
		push_warning("po_notepad: could not save %s (%s)" % [_path, error_string(err)])
		return false
	var wrote := file.store_string(_text)
	file.close()
	if not wrote:
		_set_status(I18n.t("Could not save: write failed"))
		push_warning("po_notepad: write failed for %s" % _path)
		return false
	_saved_text = _text
	_dirty = false
	_recovery_timer.stop()
	_delete_recovery()
	_refresh()
	_set_status(I18n.t("Saved"))
	saved.emit(_path)
	return true


func _on_open_pressed() -> void:
	if _open_dialog == null:
		_set_status(I18n.t("Open dialog is not ready yet"))
		return
	if DirAccess.dir_exists_absolute("res://locale"):
		_open_dialog.current_dir = "res://locale"
	_open_dialog.popup_file_dialog()


func _on_file_selected(path: String) -> void:
	request_open(path)


func _on_reload_pressed() -> void:
	if _path.is_empty():
		return
	if not _dirty:
		if load_path(_path, true, false):
			_set_status(I18n.t("File reloaded"))
		return
	_reload_confirm.dialog_text = I18n.t("Unsaved edits in %s will be lost. Reload the file from disk?") % _path.get_file()
	_reload_confirm.popup_centered()


func _on_reload_confirmed() -> void:
	_drop_edits()
	if load_path(_path, true, false):
		_set_status(I18n.t("File reloaded"))


func _on_merge_pressed() -> void:
	if _path.is_empty():
		_set_status(I18n.t("No file open"))
		return
	if not _entry_view.parse_text(_text, true):
		_set_status(I18n.t("Could not parse the catalog: %s") % _entry_view.error_text())
		return
	var collected := PoTemplate.collect()
	if not collected.ok:
		_show_merge_report(collected.error)
		_set_status(collected.error)
		return
	var language := _entry_view.catalog_language().to_lower()
	var result := _entry_view.merge_messages(collected.messages, language.begins_with("en"), collected.files)
	if not result.ok:
		_show_merge_report(result.error)
		_set_status(result.error)
		return
	var report := MergeReport.format(collected, result, _dirty)
	_show_merge_report(report)
	_set_status(I18n.t("Merge done"))


func _save_issues() -> PackedStringArray:
	var catalog := PoCatalog.new()
	if not catalog.parse(_text):
		return PackedStringArray()
	return catalog.issue_lines_except(_acks)


func _show_save_issues(issues: PackedStringArray) -> void:
	if _save_check == null or _save_check_body == null:
		_resume_path = ""
		_write_disk()
		return
	var lines := PackedStringArray()
	lines.append(I18n.t("In these entries placeholders or the number of forms do not match the original:"))
	lines.append("")
	for issue: String in issues:
		lines.append("• " + issue)
	_save_check_body.text = "\n".join(lines)
	_save_check.popup_centered(Vector2i(680, 460))


func _on_save_despite_issues() -> void:
	if not _write_disk():
		_resume_path = ""
		_mark_open_locale()
		return
	_accept_open_issues()
	_finish_resume()


func _on_save_issues_canceled() -> void:
	_resume_path = ""
	_mark_open_locale()


func _finish_resume() -> void:
	var path := _resume_path
	_resume_path = ""
	if path.is_empty():
		return
	if not load_path(path, true, true):
		return


func _show_merge_report(text: String) -> void:
	if _report_body == null or _report == null:
		_set_status(text)
		return
	_report_body.text = text
	_report.popup_centered(Vector2i(680, 520))


func _on_confirm_save() -> void:
	var path := _pending_path
	_pending_path = ""
	_resume_path = path
	if not save_if_dirty():
		return
	_finish_resume()


func _on_confirm_discard(action: StringName) -> void:
	if action != &"discard":
		return
	var path := _pending_path
	_pending_path = ""
	_confirm.hide()
	_drop_edits()
	if path.is_empty():
		return
	if not load_path(path, true, true):
		return


func _on_confirm_canceled() -> void:
	_pending_path = ""
	_resume_path = ""
	_mark_open_locale()


func _on_text_changed() -> void:
	if _loading:
		return
	_text = _code.text
	_dirty = _text != _saved_text
	if _dirty:
		_recovery_timer.start()
	else:
		_recovery_timer.stop()
		_delete_recovery()
	_refresh()


func _drop_edits() -> void:
	_recovery_timer.stop()
	_dirty = false
	_delete_recovery()


func _write_recovery() -> void:
	if _path.is_empty() or not _dirty or _code == null:
		return
	_store.write_recovery(_path, _text)


func _delete_recovery() -> void:
	_store.delete_recovery(_path)


func _on_locate_requested() -> void:
	_set_status(SourceLocator.open_entry(
		_entry_view.selected_context(),
		_entry_view.selected_source(),
		_entry_view.selected_note()
	))


func _on_issues_accepted(accepted: Dictionary) -> void:
	_acks = accepted.duplicate()
	_write_acks()
	_refresh()


func _accept_open_issues() -> void:
	var catalog := PoCatalog.new()
	if not catalog.parse(_text):
		return
	for index in catalog.visible_count():
		var signature := catalog.issue_signature(index)
		if signature.is_empty():
			continue
		_acks[signature] = true
	_write_acks()
	_entry_view.set_accepted(_acks)
	_refresh()


func _load_acks() -> void:
	_acks = _store.load_acks(_path)


func _write_acks() -> void:
	_store.write_acks(_path, _acks)


func _offer_recovery() -> void:
	if _path.is_empty():
		_recovery_waiting = false
		return
	if not is_visible_in_tree():
		_recovery_waiting = true
		return
	_recovery_waiting = false
	if _recover.visible:
		return
	var recovered: Variant = _store.read_recovery(_path)
	if recovered == null:
		return
	if str(recovered) == _text:
		_delete_recovery()
		return
	_recovered_text = str(recovered)
	_recover.dialog_text = I18n.t("Unsaved edits were found for %s (for example after a crash). Restore them?") % _path.get_file()
	_recover.popup_centered()


func _on_restore() -> void:
	if _recovered_text.is_empty():
		return
	_text = _recovered_text
	_loading = true
	_code.text = _text
	_loading = false
	_recovered_text = ""
	_dirty = _text != _saved_text
	if _list_mode and not _entry_view.parse_text(_text):
		_list_mode = false
		_set_mode_buttons(false)
	_refresh()
	_set_status(I18n.t("Edits restored"))
	if _list_mode:
		_entry_view.focus_editor()
	else:
		_code.grab_focus()


func _on_discard_recovery() -> void:
	_recovered_text = ""
	_delete_recovery()
	_set_status(I18n.t("Kept the version on disk"))


func _focus_find() -> void:
	if _code.has_selection():
		var selected := _code.get_selected_text()
		if not selected.is_empty() and not selected.contains("\n"):
			_find_edit.text = selected
	_find_edit.grab_focus()
	_find_edit.select_all()


func _on_find_prev() -> void:
	if _list_mode:
		if not _entry_view.select_neighbor(false):
			_set_status(I18n.t("No entries"))
		else:
			_update_cursor()
		return
	_find(false)


func _on_find_next() -> void:
	if _list_mode:
		if not _entry_view.select_neighbor(true):
			_set_status(I18n.t("No entries"))
		else:
			_update_cursor()
		return
	_find(true)


func _on_find_text_changed(value: String) -> void:
	if _entry_view == null:
		return
	_entry_view.set_query(value)
	if _list_mode:
		_update_cursor()


func _on_search_cleared() -> void:
	if _find_edit.text.is_empty():
		return
	_find_edit.text = ""


func _goto_empty(forward: bool) -> void:
	if _path.is_empty():
		_set_status(I18n.t("No file open"))
		return
	if not _entry_view.select_empty(forward):
		_set_status(I18n.t("No empty entries"))
		return
	_update_cursor()
	_set_status(I18n.t("Empty entry"))


func _on_find_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		if _list_mode:
			_entry_view.focus_editor()
		else:
			_code.grab_focus()
		_find_edit.accept_event()
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if _list_mode:
		_entry_view.focus_list()
		_find_edit.accept_event()
		return
	_find(not key.shift_pressed)
	_find_edit.accept_event()


func _find(forward: bool) -> void:
	var query := _find_edit.text
	if _path.is_empty():
		_set_status(I18n.t("No file open"))
		return
	if query.is_empty():
		_set_status(I18n.t("Enter text to search for"))
		return
	var source := _code.text
	var at := -1
	if forward:
		var start := _caret_offset()
		if _code.has_selection() and _code.get_selected_text() == query:
			start = _selection_bounds().y
		at = source.find(query, start)
		if at < 0:
			at = source.find(query)
	else:
		var start := _caret_offset() - 1
		if _code.has_selection() and _code.get_selected_text() == query:
			start = _selection_bounds().x - 1
		if start >= 0:
			at = source.rfind(query, start)
		if at < 0:
			at = source.rfind(query)
	if at < 0:
		_set_status(I18n.t("Not found"))
		return
	_select_range(at, query.length())
	_set_status(I18n.t("Found"))


func _select_range(start: int, length: int) -> void:
	var origin := _offset_to_position(start)
	var caret := _offset_to_position(start + length)
	_code.select(origin.x, origin.y, caret.x, caret.y)
	_code.center_viewport_to_caret()
	_find_edit.grab_focus()


func _selection_bounds() -> Vector2i:
	var from := _position_to_offset(_code.get_selection_from_line(), _code.get_selection_from_column())
	var to := _position_to_offset(_code.get_selection_to_line(), _code.get_selection_to_column())
	if from <= to:
		return Vector2i(from, to)
	return Vector2i(to, from)


func _caret_offset() -> int:
	return _position_to_offset(_code.get_caret_line(), _code.get_caret_column())


func _position_to_offset(line: int, column: int) -> int:
	var offset := 0
	var limit := line
	var count := _code.get_line_count()
	if limit > count:
		limit = count
	if limit < 0:
		limit = 0
	for index: int in limit:
		offset += _code.get_line(index).length() + 1
	return offset + column


func _offset_to_position(offset: int) -> Vector2i:
	var remaining := offset
	var count := _code.get_line_count()
	if count <= 0:
		return Vector2i.ZERO
	for line_index: int in count:
		var line := _code.get_line(line_index)
		if remaining <= line.length():
			return Vector2i(line_index, remaining)
		remaining -= line.length() + 1
	var last := count - 1
	return Vector2i(last, _code.get_line(last).length())


func _on_wrap_toggled(enabled: bool) -> void:
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if enabled else TextEdit.LINE_WRAPPING_NONE


func _on_list_toggled(enabled: bool) -> void:
	if enabled:
		if _path.is_empty() or not _entry_view.parse_text(_text, true):
			_list_mode = false
			_set_mode_buttons(false)
			if not _path.is_empty():
				_set_status(I18n.t("Could not read entries: %s") % _entry_view.error_text())
			_refresh()
			return
		_list_mode = true
		_entry_view.set_query(_find_edit.text)
		_refresh()
		_entry_view.focus_list()
		return
	_list_mode = false
	_refresh()
	if not _path.is_empty():
		_code.grab_focus()


func _on_entries_edited(full_text: String) -> void:
	if full_text == _text:
		_refresh()
		return
	_text = full_text
	_loading = true
	_code.text = full_text
	_loading = false
	_dirty = _text != _saved_text
	if _dirty:
		_recovery_timer.start()
	else:
		_recovery_timer.stop()
		_delete_recovery()
	_refresh()


func _refresh() -> void:
	var has_file := not _path.is_empty()
	var show_list := has_file and _list_mode
	_entry_view.visible = show_list
	_code.visible = has_file and not show_list
	_empty.visible = not has_file
	_code.editable = has_file
	_list_button.disabled = not has_file
	_text_button.disabled = not has_file
	_save_button.disabled = not has_file or not _dirty
	_reload_button.disabled = not has_file
	# Disabled, not hidden: hiding it shifts the mode buttons under the cursor.
	_wrap.disabled = not has_file or show_list
	_dirty_label.visible = has_file and _dirty
	_find_prev_button.tooltip_text = I18n.t("Previous entry") if show_list else I18n.t("Previous match (Shift+Enter)")
	_find_next_button.tooltip_text = I18n.t("Next entry") if show_list else I18n.t("Next match (Enter)")
	if _merge_button != null:
		_merge_button.disabled = not has_file
	if has_file:
		if _list_mode and _entry_view.stats_text() != "":
			_count_label.text = _entry_view.stats_text()
		else:
			_count_label.text = I18n.t("entries: %d") % _message_count(_text)
		if not _has_locale_item(_path):
			_reload_locales()
	else:
		_count_label.text = ""
	_mark_open_locale()
	_update_cursor()


func _has_locale_item(path: String) -> bool:
	for index in _locale_list.item_count:
		if str(_locale_list.get_item_metadata(index)) == path:
			return true
	return false


func _reload_locales() -> void:
	if _locale_list == null:
		return
	var paths := _project_locales()
	# A file opened by hand still gets a row, so the list always shows what is open.
	if not _path.is_empty() and not paths.has(_path):
		paths.append(_path)
	var icon := EditorTheme.icon("Translation")
	_locale_list.set_block_signals(true)
	_locale_list.clear()
	for path: String in paths:
		var index := _locale_list.add_item(_locale_caption(path, paths), icon)
		_locale_list.set_item_metadata(index, path)
	_locale_list.set_block_signals(false)
	_mark_open_locale()


## Translated, empty, needs-review counts for a catalog. The open catalog is
## read live from the entry list, others from disk and cached by mtime.
func _locale_counts(path: String) -> Vector3i:
	if path == _path and _list_mode and _entry_view != null and _entry_view.has_catalog():
		return _entry_view.stats_counts()
	var mtime := FileAccess.get_modified_time(path)
	var cached: Variant = _stats_cache.get(path)
	if cached is Dictionary:
		var entry := cached as Dictionary
		if int(entry["mtime"]) == mtime:
			return entry["counts"] as Vector3i
	var counts := Vector3i.ZERO
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var text := file.get_as_text()
		file.close()
		var catalog := PoCatalog.new()
		if catalog.parse(text):
			counts = catalog.stats()
	_stats_cache[path] = {"mtime": mtime, "counts": counts}
	return counts


func _locale_label(path: String, paths: PackedStringArray, counts: Vector3i) -> String:
	var label := _locale_caption(path, paths)
	var total := counts.x + counts.y + counts.z
	if total > 0:
		label += "  %d%%" % int(floor(100.0 * counts.x / total))
	if path == _path and _dirty:
		label += " *"
	return label


func _locale_tooltip(path: String, counts: Vector3i) -> String:
	var total := counts.x + counts.y + counts.z
	if total == 0:
		return path
	return "%s\n%s" % [path, I18n.t("translated %d of %d, empty %d, needs review %d") % [counts.x, total, counts.y, counts.z]]


func _mark_open_locale() -> void:
	if _locale_list == null:
		return
	var paths := PackedStringArray()
	for index in _locale_list.item_count:
		paths.append(str(_locale_list.get_item_metadata(index)))
	_locale_list.set_block_signals(true)
	var found := false
	for index in _locale_list.item_count:
		var path := str(_locale_list.get_item_metadata(index))
		var counts := _locale_counts(path)
		_locale_list.set_item_text(index, _locale_label(path, paths, counts))
		_locale_list.set_item_tooltip(index, _locale_tooltip(path, counts))
		if path == _path:
			_locale_list.select(index)
			found = true
	if not found:
		_locale_list.deselect_all()
	_locale_list.set_block_signals(false)


func _on_locale_selected(index: int) -> void:
	if _locale_list == null:
		return
	var path := str(_locale_list.get_item_metadata(index))
	if path != _path:
		request_open(path)
	_mark_open_locale()


func _project_locales() -> PackedStringArray:
	var raw: Variant = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	var listed := PackedStringArray()
	if raw is PackedStringArray:
		listed = raw
	elif raw is Array:
		var items := raw as Array
		for item: Variant in items:
			listed.append(str(item))
	var paths := PackedStringArray()
	for path: String in listed:
		if path.get_extension().to_lower() != "po":
			continue
		if not FileAccess.file_exists(path):
			continue
		if paths.has(path):
			continue
		paths.append(path)
	return paths


func _locale_caption(path: String, paths: PackedStringArray) -> String:
	var base := path.get_file().get_basename()
	var copies := 0
	for other: String in paths:
		if other.get_file().get_basename() == base:
			copies += 1
	if copies > 1:
		return "%s/%s" % [path.get_base_dir().get_file(), base]
	return base


func _update_cursor() -> void:
	if _path.is_empty():
		_cursor_label.text = ""
		return
	if _list_mode:
		_cursor_label.text = _entry_view.cursor_text()
		return
	_cursor_label.text = I18n.t("Line %d, column %d") % [_code.get_caret_line() + 1, _code.get_caret_column() + 1]


func _message_count(text: String) -> int:
	var count := 0
	var skipped_header := false
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("msgid "):
			continue
		if not skipped_header and line == "msgid \"\"":
			skipped_header = true
			continue
		count += 1
	return count


func _set_status(message: String) -> void:
	_status_label.text = message
	if _status_timer != null:
		_status_timer.start()


func _clear_status() -> void:
	_status_label.text = ""


func _set_mode_buttons(list: bool) -> void:
	_list_button.set_pressed_no_signal(list)
	_text_button.set_pressed_no_signal(not list)


func _dialog_open() -> bool:
	return (_confirm != null and _confirm.visible) or (_reload_confirm != null and _reload_confirm.visible) or (_recover != null and _recover.visible) or (_open_dialog != null and _open_dialog.visible) or (_report != null and _report.visible) or (_save_check != null and _save_check.visible)


func _owns_focus() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner != null and (owner == self or is_ancestor_of(owner))


func _apply_theme() -> void:
	if _code == null or _applying_theme:
		return
	_applying_theme = true
	var theme := EditorInterface.get_editor_theme()
	if theme != null:
		var font := theme.get_font(&"source", &"EditorFonts")
		if font != null:
			_code.add_theme_font_override(&"font", font)
		var font_size := theme.get_font_size(&"source_size", &"EditorFonts")
		if font_size > 0:
			_code.add_theme_font_size_override(&"font_size", font_size)
	_code.add_theme_color_override(&"background_color", EditorTheme.setting_color("text_editor/theme/highlighting/background_color", Color(0.12, 0.12, 0.14)))
	_code.add_theme_color_override(&"font_color", EditorTheme.setting_color("text_editor/theme/highlighting/text_color", Color(0.9, 0.9, 0.9)))
	_code.add_theme_color_override(&"font_readonly_color", EditorTheme.setting_color("text_editor/theme/highlighting/text_color", Color(0.9, 0.9, 0.9)))
	_code.add_theme_color_override(&"current_line_color", EditorTheme.setting_color("text_editor/theme/highlighting/current_line_color", Color(1, 1, 1, 0.06)))
	_code.add_theme_color_override(&"line_number_color", EditorTheme.setting_color("text_editor/theme/highlighting/line_number_color", Color(0.6, 0.6, 0.65)))
	_code.add_theme_color_override(&"caret_color", EditorTheme.setting_color("text_editor/theme/highlighting/caret_color", Color(1, 1, 1)))
	_code.add_theme_color_override(&"selection_color", EditorTheme.setting_color("text_editor/theme/highlighting/selection_color", Color(0.3, 0.45, 0.7, 0.6)))

	if _highlighter == null:
		_highlighter = CodeHighlighter.new()
		_code.syntax_highlighter = _highlighter
	_highlighter.clear_keyword_colors()
	_highlighter.clear_color_regions()
	var keyword := EditorTheme.setting_color("text_editor/theme/highlighting/keyword_color", Color(1, 0.44, 0.52))
	var type_color := EditorTheme.setting_color("text_editor/theme/highlighting/base_type_color", Color(0.26, 1, 0.76))
	var string_color := EditorTheme.setting_color("text_editor/theme/highlighting/string_color", Color(1, 0.84, 0.6))
	var comment := EditorTheme.setting_color("text_editor/theme/highlighting/comment_color", Color(0.55, 0.6, 0.55, 0.85))
	_highlighter.number_color = EditorTheme.setting_color("text_editor/theme/highlighting/number_color", Color(0.63, 1, 0.88))
	_highlighter.symbol_color = EditorTheme.setting_color("text_editor/theme/highlighting/symbol_color", Color(0.67, 0.79, 1))
	_highlighter.add_keyword_color("msgid", keyword)
	_highlighter.add_keyword_color("msgid_plural", keyword)
	_highlighter.add_keyword_color("msgctxt", keyword)
	_highlighter.add_keyword_color("msgstr", type_color)
	_highlighter.add_color_region("#", "", comment, true)
	_highlighter.add_color_region("\"", "\"", string_color)
	if _locale_list != null:
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme != null and editor_theme.has_stylebox(&"panel", &"Panel"):
			_locale_list.add_theme_stylebox_override(&"panel", editor_theme.get_stylebox(&"panel", &"Panel"))
		_reload_locales()
	_applying_theme = false


## A toolbar button with an icon and a caption, for actions no icon explains.
func _tool_button(label: String, icon_name: String, tip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tip
	var icon := EditorTheme.icon(icon_name)
	if icon != null:
		button.icon = icon
	EditorTheme.bind(button.pressed, callback)
	return button
