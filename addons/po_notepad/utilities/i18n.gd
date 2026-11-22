@tool
extends RefCounted

## UI strings. Source text is English; Russian lives in the table below.
## "Auto" follows the editor's language; Russian or English can be pinned
## from the toolbar. Outside the editor (tests, headless tools) Russian is used.

static var _lang := ""

static var _ru: Dictionary = {
	"Auto": "Авто",
	"Interface language": "Язык интерфейса",
	"translated %d of %d, empty %d, needs review %d": "переведено %d из %d, пусто %d, на проверке %d",
	"Translation": "Перевод",
	"Needs review. Godot ignores this entry until the flag is cleared.": "На проверке. Godot не читает эту строку, пока флаг не снят.",
	"The template has no dialogue lines, but the catalog does. Merge cancelled, catalog unchanged.": "Шаблон не содержит реплик, хотя в каталоге они есть. Слияние отменено, каталог не изменён.",
	"Could not prepare the merge.": "Не удалось подготовить слияние.",
	"%d forms, header says nplurals=%d": "форм %d, в заголовке nplurals=%d",
	"missing %s": "нет %s",
	"extra %s": "лишнее %s",
	"No files in Project Settings → Localization → POT Generation.": "В Project Settings → Localization → POT Generation нет файлов.",
	"File not found: %s": "Нет файла %s",
	"Could not read dialogue lines from %s. Catalog unchanged.": "Не удалось прочитать реплики из %s. Каталог не изменён.",
	"Skipped %s: only .dialogue, .gd and .tscn are read.": "Пропущен %s: читаются только .dialogue, .gd и .tscn.",
	"Dialogue Manager parser not found.": "Не найден разборщик Dialogue Manager.",
	"Dialogue Manager parser cannot be opened.": "Разборщик Dialogue Manager не открывается.",
	"Dialogue Manager parser returned no list for %s.": "Разборщик Dialogue Manager вернул не список для %s.",
	"Cannot open %s": "Не открыть %s",
	"Edit in po_notepad": "Править в po_notepad",
	"Add": "Добавить",
	"Insert a new entry after the selected one": "Вставить новую запись после выбранной",
	"Delete": "Удалить",
	"Delete the selected entry": "Удалить выбранную запись",
	"All": "Все",
	"Empty": "Пустые",
	"Needs review": "На проверке",
	"Dialogue lines": "Реплики (Dialogue)",
	"Keys (not dialogue)": "Ключи (не реплики)",
	"Which entries to show": "Какие записи показывать",
	"Empty ↑": "Пустая ↑",
	"Previous empty (Shift+F3)": "Предыдущая пустая (Shift+F3)",
	"Empty ↓": "Пустая ↓",
	"Next empty (F3)": "Следующая пустая (F3)",
	"Copy original": "Подставить оригинал",
	"Write the original into the translation": "Записать оригинал в перевод",
	"Original": "Оригинал",
	"Double-click opens the .dialogue or script where the string is defined.": "Двойной щелчок открывает .dialogue или скрипт, где записана строка.",
	"Select an entry.": "Выберите запись.",
	"Advanced": "Дополнительно",
	"Clear fuzzy flag": "Снять пометку fuzzy",
	"Remove #, fuzzy. Godot ignores the entry while the flag is set.": "Убрать #, fuzzy. Пока флаг стоит, Godot эту строку не читает.",
	"Accept mismatch": "Принять расхождение",
	"The mismatch is intentional. The highlight turns yellow and saving will no longer ask.": "Это расхождение осознанное. Подсветка станет жёлтой и при сохранении больше не спросит.",
	"Context, note, plural forms, editing the original.": "Контекст, пометка, множественное число, правка оригинала.",
	"Edit original": "Изменить оригинал",
	"The original is the entry key. If you change it, translations elsewhere will stop matching.": "Оригинал — это ключ записи. Если его изменить, перевод в других местах перестанет находиться.",
	"Plural forms": "Множественное число",
	"Context (msgctxt)": "Контекст (msgctxt)",
	"For a dialogue line this is the [ID:…] from the .dialogue file, so identical English text differs between places. Only with the Dialogue Manager plugin.": "Для реплики это [ID:…] из файла .dialogue: так одинаковый английский текст различается в разных местах. Только вместе с плагином Dialogue Manager.",
	"Note (#.)": "Пометка (#.)",
	"The #. comment from the file. Usually the .dialogue name the string came from.": "Комментарий #. из файла. Обычно это имя .dialogue, откуда взята строка.",
	"Delete entry": "Удалить запись",
	"Keep": "Оставить",
	"Entry %d / %d": "Запись %d / %d",
	"Entry — / %d": "Запись — / %d",
	"translated %d, empty %d, needs review %d": "переведено %d, пусто %d, на проверке %d",
	", errors %d": ", ошибок %d",
	"Nothing matches the current filter and search.": "Под текущий фильтр и поиск ничего не подошло.",
	"The catalog has no entries. Add the first one with the + button above the list.": "В каталоге нет записей. Добавьте первую кнопкой + над списком.",
	"Empty (%d)": "Пустые (%d)",
	"Needs review (%d)": "На проверке (%d)",
	"No empty entries": "Пустых нет",
	"Empty entry": "Пустая строка",
	"Original copied": "Оригинал подставлен",
	"Delete entry \"%s\"?\nThis cannot be undone. While the file is unsaved you can reload it from disk.": "Удалить запись «%s»?\nОтменить удаление нельзя. Пока файл не сохранён, его можно перечитать с диска.",
	"Mismatch accepted": "Расхождение оставлено",
	"Flag cleared": "Проверка снята",
	"Accepted when saving.\n": "Подтверждено при сохранении.\n",
	"(empty)": "(пусто)",
	"Accepted when saving.": "Подтверждено при сохранении. ",
	"Needs review. Godot ignores the entry until the flag is cleared.": "На проверке. Godot не читает строку, пока флаг не снят.",
	"Empty translation": "Пустой перевод",
	"PO file has unsaved changes: %s": "Файл .po не сохранён: %s",
	"Template files: %d": "Файлов шаблона: %d",
	"Unchanged: %d": "Без изменений: %d",
	"New: %d": "Новых: %d",
	"Marked for review: %d": "Поставлено на проверку: %d",
	"Removed: %d": "Удалено: %d",
	"Dialogue lines not added: %d. The English catalog keeps keys only; English text stays in .dialogue.": "Реплики не добавлены: %d. Английский каталог хранит только ключи, английский текст остаётся в .dialogue.",
	"List switched to \"%s\".": "Список переключён на «%s».",
	"Not written to disk yet. Save keeps the merge, Reload restores the file.": "На диск ещё не записано. Сохранить — оставить слияние, Перезагрузить — вернуть файл.",
	"New entries": "Новые строки",
	"Needs review: the old translation is kept, Godot ignores it while fuzzy is set": "На проверке: прежний перевод сохранён, Godot его не читает, пока стоит fuzzy",
	"Removed because they are no longer in the template": "Удалены, потому что их больше нет в шаблоне",
	"POT does not see these keys, they were kept in the catalog:": "POT не видит эти ключи, они оставлены в каталоге:",
	"no longer in %s, but it is a key — kept, it may be built in code": "в %s этой строки уже нет, но это ключ — оставлен, его могли собрать в коде",
	"the name is built in code as actor. + name": "имя собирается в коде как actor. + имя",
	"tr() receives a variable, not a literal string": "в tr() передаётся переменная, не готовая строка",
	"no tr() literal with this text in the POT files": "в файлах POT нет литерала tr() с этим текстом",
	"The .dialogue file for this line was not found": "Файл .dialogue для этой реплики не найден",
	"%s has no [ID:%s]": "В %s нет [ID:%s]",
	"This entry has no file to jump to": "У этой строки нет файла, куда перейти",
	"Dialogue Manager is not enabled": "Dialogue Manager не включён",
	"%s, line %d": "%s, строка %d",
	"Name %s is built in code: %s, line %d": "Имя %s собирается в коде: %s, строка %d",
	"No literal %s in scripts or scenes": "В скриптах и сценах нет литерала %s",
	"%s — %s, line %d": "%s — %s, строка %d",
	"Open": "Открыть",
	"Open a .po file": "Открыть файл .po",
	"Save": "Сохранить",
	"Save (Ctrl+S)": "Сохранить (Ctrl+S)",
	"Reload": "Перечитать",
	"Reload the file from disk": "Перечитать файл с диска",
	"Merge POT": "Слить с POT",
	"Read the files from Localization → POT Generation and merge them into the open catalog.": "Прочитать файлы из Localization → POT Generation и слить их в открытый каталог.",
	"● unsaved": "● не сохранено",
	"Search (Ctrl+F)": "Поиск (Ctrl+F)",
	"In List mode filters entries by original, translation and context. In Text mode searches the file (Enter — next, Shift+Enter — previous).": "В режиме «Список» фильтрует записи по оригиналу, переводу и контексту. В режиме «Текст» ищет по файлу (Enter — дальше, Shift+Enter — назад).",
	"Previous match": "Предыдущее совпадение",
	"Next match": "Следующее совпадение",
	"Wrap lines": "Перенос строк",
	"Wrap long lines (Text mode only)": "Переносить длинные строки (только в режиме «Текст»)",
	"List": "Список",
	"Edit one entry at a time.": "Править по одной записи.",
	"Text": "Текст",
	"Edit the .po file as plain text.": "Править файл .po как обычный текст.",
	"Locales": "Локали",
	"Catalogs from Project Settings → Localization → Translations. Any other .po opens with the folder button on the toolbar.": "Каталоги из Project Settings → Localization → Translations. Любой другой .po открывается кнопкой с папкой на панели.",
	"No file open.\nPick a locale on the left or open a .po with the folder button on the toolbar.\nIf the list is empty, add a .po in Project Settings → Localization → Translations.": "Файл не открыт.\nВыберите локаль слева или откройте .po кнопкой с папкой на панели.\nЕсли список локалей пуст, добавьте .po в Project Settings → Localization → Translations.",
	"Open a .po catalog": "Открыть каталог .po",
	"Unsaved changes": "Несохранённые изменения",
	"Cancel": "Отмена",
	"Don't save": "Не сохранять",
	"Reload file": "Перечитать файл",
	"Discard and reload": "Отбросить и перечитать",
	"Unsaved edits found": "Найдены несохранённые правки",
	"Restore": "Восстановить",
	"Discard": "Отбросить",
	"POT merge": "Слияние с POT",
	"Close": "Закрыть",
	"Check before saving": "Проверка перед сохранением",
	"Save anyway": "Сохранить всё равно",
	"Back to editing": "Вернуться к правке",
	"No changes": "Изменений нет",
	"Not a .po file": "Это не файл .po",
	"Save changes to %s before opening another file?": "Сохранить изменения в %s перед открытием другого файла?",
	"Could not open %s: %s": "Не удалось открыть %s: %s",
	"No file open": "Файл не открыт",
	"File moved": "Файл перемещён",
	"File was removed from disk. Save to write it again.": "Файл удалён с диска. Сохраните, чтобы записать его заново.",
	"File was removed from disk.": "Файл удалён с диска.",
	"Could not read entries, showing text: %s": "Не удалось разобрать записи, показан текст: %s",
	"Could not save: %s": "Не удалось сохранить: %s",
	"Could not save: write failed": "Не удалось сохранить: ошибка записи",
	"Saved": "Сохранено",
	"Open dialog is not ready yet": "Диалог открытия ещё не готов",
	"File reloaded": "Файл перечитан",
	"Unsaved edits in %s will be lost. Reload the file from disk?": "Несохранённые правки в %s будут потеряны. Перечитать файл с диска?",
	"Could not parse the catalog: %s": "Не разобрать каталог: %s",
	"Merge done": "Слияние готово",
	"In these entries placeholders or the number of forms do not match the original:": "В этих записях плейсхолдеры или число форм не совпадают с оригиналом:",
	"Unsaved edits were found for %s (for example after a crash). Restore them?": "Для %s найдены несохранённые правки (например, после сбоя). Восстановить их?",
	"Edits restored": "Правки восстановлены",
	"Kept the version on disk": "Оставлена версия с диска",
	"No entries": "Нет записей",
	"Enter text to search for": "Введите текст для поиска",
	"Not found": "Не найдено",
	"Found": "Найдено",
	"Could not read entries: %s": "Не удалось разобрать записи: %s",
	"Previous entry": "Предыдущая запись",
	"Previous match (Shift+Enter)": "Предыдущее совпадение (Shift+Enter)",
	"Next entry": "Следующая запись",
	"Next match (Enter)": "Следующее совпадение (Enter)",
	"entries: %d": "записей: %d",
	"Line %d, column %d": "Строка %d, столбец %d",
}


static func reset() -> void:
	_lang = ""


## Pins the language ("ru" or "en"). Used by tests; reset() returns to auto.
static func set_language(lang: String) -> void:
	_lang = lang


static func ru_table() -> Dictionary:
	return _ru


const SETTING := "po_notepad/language"


## "auto", "ru" or "en": the user's choice, kept in Editor Settings.
static func preference() -> String:
	if not Engine.is_editor_hint():
		return "auto"
	var settings := EditorInterface.get_editor_settings()
	var value := str(settings.get_setting(SETTING)) if settings.has_setting(SETTING) else "auto"
	return value if value == "ru" or value == "en" else "auto"


static func set_preference(value: String) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_setting(SETTING, value)
	_lang = ""


static func language() -> String:
	if _lang.is_empty():
		_lang = "ru"
		if Engine.is_editor_hint():
			var choice := preference()
			if choice == "auto":
				# The editor's resolved language. The setting itself says "auto"
				# on most machines, so it cannot be read directly.
				choice = TranslationServer.get_tool_locale()
			_lang = "ru" if choice.begins_with("ru") else "en"
	return _lang


static func t(msg: String) -> String:
	if language() != "ru":
		return msg
	return _ru.get(msg, msg)
