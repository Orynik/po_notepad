@tool
extends EditorContextMenuPlugin

## "Edit in po_notepad" on a .po file in the FileSystem dock.

const I18n := preload("../utilities/i18n.gd")
const EditorTheme := preload("../utilities/editor_theme.gd")

var opener: Callable


func _popup_menu(paths: PackedStringArray) -> void:
	if not opener.is_valid():
		return
	var has_po := false
	for path: String in paths:
		if path.get_extension().to_lower() == "po":
			has_po = true
			break
	if not has_po:
		return
	add_context_menu_item(I18n.t("Edit in po_notepad"), opener, EditorTheme.icon("Translation"))
