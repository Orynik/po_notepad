@tool
extends RefCounted

## Editor colors and icons shared by the screen and the entry form.
## The screen reads text-editor settings. The form reads Editor theme colors.


static func setting_color(setting: String, fallback: Color) -> Color:
	var settings := EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(setting):
		var value: Variant = settings.get_setting(setting)
		if value is Color:
			return value
	return fallback


static func theme_color(color_name: StringName, fallback: Color) -> Color:
	if not Engine.is_editor_hint():
		return fallback
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_color(color_name, &"Editor"):
		return theme.get_color(color_name, &"Editor")
	return fallback


static func icon(icon_name: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var theme := EditorInterface.get_editor_theme()
	if theme == null or not theme.has_icon(icon_name, &"EditorIcons"):
		return null
	return theme.get_icon(icon_name, &"EditorIcons")


## A button that shows only an editor icon. The name goes to the tooltip and
## to screen readers. Without the icon (outside the editor) the name is shown
## as text, so the button never ends up blank.
static func icon_button(icon_name: String, label: String, tip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.tooltip_text = tip
	button.accessibility_name = label
	var texture := icon(icon_name)
	if texture != null:
		button.icon = texture
	else:
		button.text = label
	bind(button.pressed, callback)
	return button


## Pixel size multiplied by the editor scale, so layouts hold on hiDPI.
static func scaled(pixels: float) -> float:
	if not Engine.is_editor_hint():
		return pixels
	return pixels * EditorInterface.get_editor_scale()


static func scaled_vec(x: float, y: float) -> Vector2:
	return Vector2(scaled(x), scaled(y))


static func bind(sig: Signal, method: Callable) -> void:
	var err := sig.connect(method)
	if err != OK:
		push_error("po_notepad: %s" % error_string(err))
