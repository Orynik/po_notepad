extends GdUnitTestSuite

const I18n := preload("res://addons/po_notepad/utilities/i18n.gd")


func after_test() -> void:
	I18n.reset()


func test_english_returns_source_text() -> void:
	I18n.set_language("en")
	assert_str(I18n.t("Save")).is_equal("Save")


func test_russian_translates_known_key() -> void:
	I18n.set_language("ru")
	assert_str(I18n.t("Save")).is_equal("Сохранить")


func test_unknown_key_passes_through() -> void:
	I18n.set_language("ru")
	assert_str(I18n.t("No such key")).is_equal("No such key")


func test_format_placeholders_match_in_both_languages() -> void:
	var table := I18n.ru_table()
	for key: String in table:
		var ru := str(table[key])
		assert_int(_placeholders(ru)).is_equal(_placeholders(key))


func test_no_cyrillic_in_english_keys() -> void:
	var table := I18n.ru_table()
	var cyrillic := RegEx.create_from_string("[Ѐ-ӿ]")
	for key: String in table:
		assert_bool(cyrillic.search(key) == null).is_true()


func _placeholders(text: String) -> int:
	var found := RegEx.create_from_string("%[sd]").search_all(text)
	return found.size()
