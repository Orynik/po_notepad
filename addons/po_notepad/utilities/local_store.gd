@tool
extends RefCounted

## Drafts and accepted save-checks for an open catalog.
## Files live under user:// and are never written into the .po.

const DIR := "user://po_notepad"

var _recovery_failed := false


func write_recovery(catalog_path: String, text: String) -> void:
	if catalog_path.is_empty():
		return
	var mk := DirAccess.make_dir_recursive_absolute(DIR)
	if mk != OK and not DirAccess.dir_exists_absolute(DIR):
		if not _recovery_failed:
			_recovery_failed = true
			push_warning("po_notepad: could not create recovery folder (%s)" % error_string(mk))
		return
	var file := FileAccess.open(recovery_file(catalog_path), FileAccess.WRITE)
	if file == null:
		return
	if not file.store_string(text):
		push_warning("po_notepad: could not write recovery for %s" % catalog_path)


func delete_recovery(catalog_path: String) -> void:
	if catalog_path.is_empty():
		return
	var recovery := recovery_file(catalog_path)
	if not FileAccess.file_exists(recovery):
		return
	var err := DirAccess.remove_absolute(recovery)
	if err != OK:
		push_warning("po_notepad: could not remove recovery for %s (%s)" % [catalog_path, error_string(err)])


## Null when the draft is missing or cannot be read. An empty string is a real draft.
func read_recovery(catalog_path: String) -> Variant:
	if catalog_path.is_empty():
		return null
	var recovery := recovery_file(catalog_path)
	if not FileAccess.file_exists(recovery):
		return null
	var file := FileAccess.open(recovery, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return text


func load_acks(catalog_path: String) -> Dictionary:
	if catalog_path.is_empty():
		return {}
	var ack_path := ack_file(catalog_path)
	if not FileAccess.file_exists(ack_path):
		return {}
	var file := FileAccess.open(ack_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}


func write_acks(catalog_path: String, acks: Dictionary) -> void:
	if catalog_path.is_empty():
		return
	var mk := DirAccess.make_dir_recursive_absolute(DIR)
	if mk != OK and not DirAccess.dir_exists_absolute(DIR):
		push_warning("po_notepad: could not store accepted checks (%s)" % error_string(mk))
		return
	var file := FileAccess.open(ack_file(catalog_path), FileAccess.WRITE)
	if file == null:
		push_warning("po_notepad: could not store accepted checks")
		return
	if not file.store_string(JSON.stringify(acks)):
		push_warning("po_notepad: could not store accepted checks")


func recovery_file(catalog_path: String) -> String:
	return DIR.path_join(catalog_path.md5_text() + ".txt")


func ack_file(catalog_path: String) -> String:
	return DIR.path_join("ack_%s.json" % catalog_path.md5_text())
