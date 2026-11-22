# po_notepad

Редактор `.po` внутри Godot 4.7: каталог можно править списком и как текст, сливать с POT и проверять перед сохранением. Подробное описание — в [addons/po_notepad/README.md](addons/po_notepad/README.md).

Лицензия: [MIT](LICENSE).

## Установка в игру

Скопируйте папку `addons/po_notepad` в `addons/` своего проекта и включите плагин: Project Settings → Plugins → po_notepad.

## Структура репозитория

- `addons/po_notepad/` — сам плагин. Только эта папка попадает в архив для Asset Library (см. `.gitattributes`).
- `test/po_notepad/` — тесты GdUnit4.
- `project.godot` — минимальный проект, чтобы открыть плагин и прогнать тесты отдельно от игры.

## Тесты

GdUnit4 в репозиторий не входит. Поставьте его в `addons/gdUnit4` (через Asset Library или из релиза GdUnit4), затем:

```
godot --headless --path . --import
godot --path . --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://test
```
