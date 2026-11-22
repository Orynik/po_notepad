@tool
extends EditorPlugin

const I18n := preload("utilities/i18n.gd")

## Registers the PO screen and keeps the open catalog in sync with the
## filesystem. The screen itself is views/main_view.gd.

const PoNotepadView := preload("views/main_view.gd")
const PoContextMenu := preload("components/context_menu.gd")
const EditorTheme := preload("utilities/editor_theme.gd")
const SCREEN_NAME := "PO"

var _view: PoNotepadView
var _menu: PoContextMenu
var _icon: Texture2D
var _ignore_edit := false
var _editing := false
var _reimport_path := ""


func _enter_tree() -> void:
	I18n.reset()
	_view = PoNotepadView.new()
	_view.name = "PoNotepad"
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var saved_err := _view.saved.connect(_on_saved)
	if saved_err != OK:
		push_error("po_notepad: could not connect save signal (%s)" % error_string(saved_err))
	EditorInterface.get_editor_main_screen().add_child(_view)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_make_visible(false)

	_menu = PoContextMenu.new()
	_menu.opener = _on_context_open
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _menu)

	var dock := EditorInterface.get_file_system_dock()
	var moved_err := dock.files_moved.connect(_on_files_moved)
	if moved_err != OK:
		push_error("po_notepad: files_moved (%s)" % error_string(moved_err))
	var removed_err := dock.file_removed.connect(_on_file_removed)
	if removed_err != OK:
		push_error("po_notepad: file_removed (%s)" % error_string(removed_err))
	var selected_err := dock.selection_changed.connect(_on_selection_changed)
	if selected_err != OK:
		push_error("po_notepad: selection_changed (%s)" % error_string(selected_err))


func _exit_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_flush_reimport):
		fs.filesystem_changed.disconnect(_flush_reimport)

	var dock := EditorInterface.get_file_system_dock()
	if dock.files_moved.is_connected(_on_files_moved):
		dock.files_moved.disconnect(_on_files_moved)
	if dock.file_removed.is_connected(_on_file_removed):
		dock.file_removed.disconnect(_on_file_removed)
	if dock.selection_changed.is_connected(_on_selection_changed):
		dock.selection_changed.disconnect(_on_selection_changed)

	if _menu != null:
		remove_context_menu_plugin(_menu)
		_menu = null
	if is_instance_valid(_view):
		_view.queue_free()
		_view = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_view):
		return
	_view.visible = visible
	if visible:
		_view.fit_layout()
		_open_selected_po()


func _get_plugin_name() -> String:
	return SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	var theme_icon := EditorTheme.icon("Translation")
	if theme_icon != null:
		return theme_icon
	if _icon == null:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.45, 0.7, 0.55))
		_icon = ImageTexture.create_from_image(image)
	return _icon


func _handles(object: Object) -> bool:
	var translation := object as Translation
	if translation == null:
		return false
	return _po_path_from(translation).get_extension().to_lower() == "po"


func _edit(object: Object) -> void:
	if _ignore_edit or _editing or not is_instance_valid(_view):
		return
	var translation := object as Translation
	if translation == null:
		return
	var path := _po_path_from(translation)
	if path.get_extension().to_lower() != "po":
		return
	_editing = true
	_show_editor()
	_view.request_open(path)
	_editing = false


func _po_path_from(translation: Translation) -> String:
	var path := translation.resource_path
	if path.get_extension().to_lower() == "po":
		return path
	var current := EditorInterface.get_current_path()
	if current.get_extension().to_lower() == "po":
		return current
	return path


func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not is_instance_valid(_view) or not _view.is_dirty():
		return ""
	return I18n.t("PO file has unsaved changes: %s") % _view.current_path.get_file()


func _save_external_data() -> void:
	if not is_instance_valid(_view):
		return
	var wrote := _view.save_if_dirty()
	if not wrote and _view.is_dirty():
		push_warning("po_notepad: unsaved changes could not be written.")


func _get_window_layout(configuration: ConfigFile) -> void:
	if not is_instance_valid(_view):
		return
	configuration.set_value("po_notepad", "path", _view.current_path)


func _set_window_layout(configuration: ConfigFile) -> void:
	if not is_instance_valid(_view):
		return
	var path := str(configuration.get_value("po_notepad", "path", ""))
	if path.get_extension().to_lower() != "po" or not FileAccess.file_exists(path):
		return
	if not _view.load_path(path, false, true):
		push_warning("po_notepad: could not restore %s" % path)


func _on_context_open(paths: PackedStringArray) -> void:
	if not is_instance_valid(_view):
		return
	var chosen := ""
	for path: String in paths:
		if path.get_extension().to_lower() == "po":
			chosen = path
			break
	if chosen.is_empty():
		return
	_show_editor()
	_view.request_open(chosen)


func _on_saved(path: String) -> void:
	_reimport_path = path
	_flush_reimport()


func _flush_reimport() -> void:
	if _reimport_path.is_empty():
		return
	var fs := EditorInterface.get_resource_filesystem()
	if fs.is_scanning():
		if not fs.filesystem_changed.is_connected(_flush_reimport):
			var err := fs.filesystem_changed.connect(_flush_reimport)
			if err != OK:
				push_warning("po_notepad: could not wait for the filesystem scan (%s)" % error_string(err))
		return
	var path := _reimport_path
	_reimport_path = ""
	_ignore_edit = true
	fs.update_file(path)
	_clear_ignore_edit.call_deferred()


func _clear_ignore_edit() -> void:
	_ignore_edit = false


func _show_editor() -> void:
	EditorInterface.set_main_screen_editor(SCREEN_NAME)


func _on_selection_changed() -> void:
	if not is_instance_valid(_view) or not _view.visible:
		return
	_open_selected_po()


func _open_selected_po() -> void:
	if not is_instance_valid(_view) or not _view.visible:
		return
	var chosen := ""
	var paths := EditorInterface.get_selected_paths()
	for path: String in paths:
		if path.get_extension().to_lower() == "po":
			chosen = path
			break
	if chosen.is_empty():
		var current := EditorInterface.get_current_path()
		if current.get_extension().to_lower() == "po":
			chosen = current
	if chosen.is_empty() or chosen == _view.current_path:
		return
	_view.request_open(chosen)


func _on_files_moved(old_file: String, new_file: String) -> void:
	if is_instance_valid(_view):
		_view.note_moved(old_file, new_file)


func _on_file_removed(file: String) -> void:
	if is_instance_valid(_view):
		_view.note_removed(file)
