@tool
extends RefCounted

const I18n := preload("i18n.gd")

## Text of the dialog shown after a POT merge. The merge itself stays in the catalog.

const PoTemplate := preload("../catalog/po_template.gd")
const PoCatalog := preload("../catalog/po_catalog.gd")


static func format(collected: PoTemplate.CollectResult, result: PoCatalog.MergeResult, dirty: bool) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(I18n.t("Template files: %d") % collected.file_count)
	lines.append(I18n.t("Unchanged: %d") % result.kept)
	lines.append(I18n.t("New: %d") % result.added.size())
	lines.append(I18n.t("Marked for review: %d") % result.reviewed.size())
	lines.append(I18n.t("Removed: %d") % result.removed.size())
	if result.skipped_dialogue > 0:
		lines.append(I18n.t("Dialogue lines not added: %d. The English catalog keeps keys only; English text stays in .dialogue.") % result.skipped_dialogue)
	for warning: String in collected.warnings:
		lines.append(warning)
	if not result.filter_label.is_empty():
		lines.append(I18n.t("List switched to \"%s\".") % result.filter_label)
	if dirty:
		lines.append(I18n.t("Not written to disk yet. Save keeps the merge, Reload restores the file."))
	_append_section(lines, I18n.t("New entries"), result.added)
	_append_section(lines, I18n.t("Needs review: the old translation is kept, Godot ignores it while fuzzy is set"), result.reviewed)
	_append_section(lines, I18n.t("Removed because they are no longer in the template"), result.removed)
	if result.unseen.size() > 0:
		lines.append("")
		lines.append(I18n.t("POT does not see these keys, they were kept in the catalog:"))
		for index in result.unseen.size():
			var msgid := result.unseen[index]
			var origin := ""
			if index < result.unseen_from.size():
				origin = result.unseen_from[index]
			var reason := _unseen_reason(msgid)
			if not origin.is_empty():
				reason = I18n.t("no longer in %s, but it is a key — kept, it may be built in code") % origin
			lines.append("• %s — %s" % [msgid, reason])
	return "\n".join(lines)


static func _append_section(lines: PackedStringArray, title: String, items: PackedStringArray) -> void:
	if items.is_empty():
		return
	lines.append("")
	lines.append(title + ":")
	for item: String in items:
		lines.append("• " + item)


static func _unseen_reason(msgid: String) -> String:
	if msgid.begins_with("actor."):
		return I18n.t("the name is built in code as actor. + name")
	if msgid.begins_with("ui.interact.") or msgid == "ui.hud.examine":
		return I18n.t("tr() receives a variable, not a literal string")
	return I18n.t("no tr() literal with this text in the POT files")
