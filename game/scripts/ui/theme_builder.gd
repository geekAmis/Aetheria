class_name ThemeBuilder
extends RefCounted
## Тёмная «божественная» тема: тёплое золото, глубокий синий камень, стекло.

const BG0 := Color("#080d12")
const BG1 := Color("#0d151c")
const BG2 := Color("#15212b")
const BG3 := Color("#1d2c38")
const LINE := Color("#3a4a55")
const GOLD := Color("#e8c07a")
const GOLD_BRIGHT := Color("#ffe3a3")
const TEXT := Color("#e6eef3")
const MUTED := Color("#8fa3ae")
const TEAL := Color("#66d9c8")
const RED := Color("#e05a4e")
const GREEN := Color("#88c96a")


static func style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, border_w: int = 1, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var th := Theme.new()
	var rubik: Font = load("res://assets/fonts/Rubik.ttf")
	var serif: Font = load("res://assets/fonts/CormorantGaramond.ttf")
	if rubik == null:
		rubik = ThemeDB.fallback_font
	if serif == null:
		serif = rubik
	th.default_font = rubik
	th.default_font_size = 15

	# --- базовые панели
	th.set_stylebox("panel", "PanelContainer", style(Color(0.055, 0.085, 0.11, 0.94), Color(0.55, 0.45, 0.3, 0.30), 12, 1, 12))
	var glass := style(Color(0.035, 0.055, 0.07, 0.86), Color(0.35, 0.55, 0.6, 0.18), 12, 1, 12)
	glass.shadow_color = Color(0, 0, 0, 0.35)
	glass.shadow_size = 12
	glass.shadow_offset = Vector2(0, 4)
	th.set_type_variation("PanelGlass", "PanelContainer")
	th.set_stylebox("panel", "PanelGlass", glass)
	th.set_type_variation("PanelSolid", "PanelContainer")
	th.set_stylebox("panel", "PanelSolid", style(BG1, LINE, 10, 1, 12))
	th.set_type_variation("PanelCard", "PanelContainer")
	th.set_stylebox("panel", "PanelCard", style(Color(0.07, 0.10, 0.13, 0.9), Color(0.35, 0.45, 0.5, 0.25), 10, 1, 10))
	th.set_type_variation("PanelWarm", "PanelContainer")
	th.set_stylebox("panel", "PanelWarm", style(Color(0.13, 0.10, 0.075, 0.95), Color(0.72, 0.55, 0.32, 0.4), 12, 1, 12))

	# --- заголовки
	th.set_type_variation("Title", "Label")
	th.set_font("font", "Title", serif)
	th.set_font_size("font_size", "Title", 78)
	th.set_color("font_color", "Title", Color(0.94, 0.88, 0.76))
	th.set_type_variation("H1", "Label")
	th.set_font("font", "H1", serif)
	th.set_font_size("font_size", "H1", 34)
	th.set_color("font_color", "H1", GOLD_BRIGHT)
	th.set_type_variation("H2", "Label")
	th.set_font_size("font_size", "H2", 20)
	th.set_color("font_color", "H2", TEXT)
	th.set_type_variation("Small", "Label")
	th.set_font_size("font_size", "Small", 12)
	th.set_color("font_color", "Small", MUTED)
	th.set_type_variation("Muted", "Label")
	th.set_font_size("font_size", "Muted", 13)
	th.set_color("font_color", "Muted", MUTED)
	th.set_type_variation("GoldLabel", "Label")
	th.set_font_size("font_size", "GoldLabel", 15)
	th.set_color("font_color", "GoldLabel", GOLD)
	th.set_type_variation("Badge", "Label")
	th.set_font_size("font_size", "Badge", 11)
	th.set_color("font_color", "Badge", BG0)
	th.set_stylebox("normal", "Badge", style(GOLD, Color.TRANSPARENT, 6, 0, 6))
	th.set_type_variation("Value", "Label")
	th.set_font_size("font_size", "Value", 22)
	th.set_color("font_color", "Value", TEXT)
	th.set_type_variation("Caps", "Label")
	th.set_font_size("font_size", "Caps", 11)
	th.set_color("font_color", "Caps", MUTED)

	# --- кнопки
	var btn := style(Color(0.09, 0.13, 0.16, 0.95), Color(0.32, 0.42, 0.48, 0.5), 8, 1, 12)
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	var btn_h := style(Color(0.14, 0.20, 0.24, 0.98), Color(0.55, 0.65, 0.6, 0.55), 8, 1, 12)
	btn_h.content_margin_top = 8
	btn_h.content_margin_bottom = 8
	var btn_p := style(Color(0.18, 0.16, 0.10, 0.98), Color(0.9, 0.72, 0.4, 0.8), 8, 1, 12)
	btn_p.content_margin_top = 8
	btn_p.content_margin_bottom = 8
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", btn_h)
	th.set_stylebox("pressed", "Button", btn_p)
	th.set_stylebox("disabled", "Button", style(Color(0.07, 0.09, 0.1, 0.7), Color(0.2, 0.24, 0.26, 0.4), 8, 1, 12))
	th.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), GOLD, 8, 1, 12))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(1, 0.97, 0.88))
	th.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.58))
	th.set_font_size("font_size", "Button", 15)

	th.set_type_variation("GoldButton", "Button")
	th.set_stylebox("normal", "GoldButton", style(Color(0.55, 0.40, 0.20, 0.95), Color(0.95, 0.78, 0.45, 0.8), 9, 1, 14))
	th.set_stylebox("hover", "GoldButton", style(Color(0.72, 0.53, 0.27, 1.0), Color(1, 0.9, 0.62, 0.95), 9, 1, 14))
	th.set_stylebox("pressed", "GoldButton", style(Color(0.42, 0.30, 0.15, 1.0), Color(1, 0.9, 0.6, 1), 9, 1, 14))
	th.set_color("font_color", "GoldButton", Color(1, 0.96, 0.86))
	th.set_color("font_hover_color", "GoldButton", Color(1, 1, 1))
	th.set_font_size("font_size", "GoldButton", 16)

	th.set_type_variation("DangerButton", "Button")
	th.set_stylebox("normal", "DangerButton", style(Color(0.38, 0.13, 0.12, 0.95), Color(0.85, 0.35, 0.3, 0.7), 9, 1, 14))
	th.set_stylebox("hover", "DangerButton", style(Color(0.55, 0.18, 0.15, 1.0), Color(1, 0.5, 0.4, 0.9), 9, 1, 14))
	th.set_color("font_color", "DangerButton", Color(1, 0.85, 0.8))

	th.set_type_variation("GhostButton", "Button")
	th.set_stylebox("normal", "GhostButton", style(Color(0, 0, 0, 0.0), Color.TRANSPARENT, 8, 0, 10))
	th.set_stylebox("hover", "GhostButton", style(Color(0.15, 0.2, 0.24, 0.6), Color.TRANSPARENT, 8, 0, 10))
	th.set_stylebox("pressed", "GhostButton", style(Color(0.2, 0.18, 0.12, 0.8), Color(0.7, 0.55, 0.3, 0.5), 8, 1, 10))
	th.set_color("font_color", "GhostButton", MUTED)
	th.set_color("font_hover_color", "GhostButton", TEXT)

	th.set_type_variation("IconButton", "Button")
	th.set_stylebox("normal", "IconButton", style(Color(0.08, 0.12, 0.15, 0.6), Color(0.3, 0.4, 0.45, 0.3), 7, 1, 6))
	th.set_stylebox("hover", "IconButton", style(Color(0.16, 0.22, 0.26, 0.9), Color(0.6, 0.7, 0.65, 0.5), 7, 1, 6))
	th.set_stylebox("pressed", "IconButton", style(Color(0.25, 0.2, 0.12, 0.9), GOLD, 7, 1, 6))

	th.set_type_variation("CategoryButton", "Button")
	th.set_stylebox("normal", "CategoryButton", style(Color(0, 0, 0, 0), Color.TRANSPARENT, 6, 0, 8))
	th.set_stylebox("hover", "CategoryButton", style(Color(0.15, 0.2, 0.24, 0.55), Color.TRANSPARENT, 6, 0, 8))
	th.set_stylebox("pressed", "CategoryButton", style(Color(0.3, 0.23, 0.12, 0.9), Color(0.9, 0.72, 0.4, 0.75), 6, 1, 8))
	th.set_color("font_color", "CategoryButton", MUTED)
	th.set_color("font_pressed_color", "CategoryButton", GOLD_BRIGHT)
	th.set_font_size("font_size", "CategoryButton", 13)

	th.set_type_variation("Chip", "Button")
	th.set_stylebox("normal", "Chip", style(Color(0.08, 0.12, 0.15, 0.8), Color(0.3, 0.4, 0.45, 0.3), 14, 1, 9))
	th.set_stylebox("hover", "Chip", style(Color(0.15, 0.21, 0.25, 0.9), Color(0.5, 0.6, 0.55, 0.4), 14, 1, 9))
	th.set_stylebox("pressed", "Chip", style(Color(0.32, 0.25, 0.13, 0.95), GOLD, 14, 1, 9))
	th.set_color("font_color", "Chip", MUTED)
	th.set_color("font_pressed_color", "Chip", GOLD_BRIGHT)
	th.set_font_size("font_size", "Chip", 12)

	th.set_type_variation("ToolButton", "Button")
	th.set_stylebox("normal", "ToolButton", style(Color(0.075, 0.11, 0.14, 0.94), Color(0.25, 0.35, 0.4, 0.5), 8, 1, 6))
	th.set_stylebox("hover", "ToolButton", style(Color(0.13, 0.19, 0.23, 0.98), Color(0.55, 0.65, 0.6, 0.55), 8, 1, 6))
	th.set_stylebox("pressed", "ToolButton", style(Color(0.24, 0.20, 0.11, 0.98), Color(0.95, 0.78, 0.45, 0.9), 8, 1, 6))
	th.set_color("font_color", "ToolButton", TEXT)
	th.set_color("font_pressed_color", "ToolButton", GOLD_BRIGHT)
	th.set_font_size("font_size", "ToolButton", 11)

	th.set_type_variation("SpeedButton", "Button")
	th.set_stylebox("normal", "SpeedButton", style(Color(0.07, 0.10, 0.13, 0.8), Color.TRANSPARENT, 6, 0, 8))
	th.set_stylebox("hover", "SpeedButton", style(Color(0.14, 0.19, 0.23, 0.9), Color(0.4, 0.5, 0.5, 0.4), 6, 1, 8))
	th.set_stylebox("pressed", "SpeedButton", style(Color(0.32, 0.24, 0.12, 0.95), GOLD, 6, 1, 8))
	th.set_color("font_color", "SpeedButton", MUTED)
	th.set_color("font_pressed_color", "SpeedButton", GOLD_BRIGHT)
	th.set_font_size("font_size", "SpeedButton", 13)

	# --- ввод
	th.set_stylebox("normal", "LineEdit", style(Color(0.05, 0.08, 0.1, 0.95), Color(0.3, 0.4, 0.45, 0.5), 7, 1, 10))
	th.set_stylebox("focus", "LineEdit", style(Color(0.05, 0.08, 0.1, 0.95), GOLD, 7, 1, 10))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", MUTED)
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_stylebox("normal", "OptionButton", style(Color(0.05, 0.08, 0.1, 0.95), Color(0.3, 0.4, 0.45, 0.5), 7, 1, 10))
	th.set_stylebox("hover", "OptionButton", style(Color(0.1, 0.15, 0.18, 0.98), Color(0.5, 0.6, 0.55, 0.5), 7, 1, 10))
	th.set_stylebox("pressed", "OptionButton", style(Color(0.1, 0.15, 0.18, 0.98), GOLD, 7, 1, 10))
	th.set_color("font_color", "OptionButton", TEXT)

	th.set_stylebox("normal", "CheckButton", style(Color(0.1, 0.14, 0.17, 0.8), Color(0.3, 0.4, 0.45, 0.4), 12, 1, 8))
	th.set_stylebox("pressed", "CheckButton", style(Color(0.35, 0.26, 0.13, 0.9), GOLD, 12, 1, 8))
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_pressed_color", "CheckButton", GOLD_BRIGHT)

	var slider_bg := style(Color(0.15, 0.21, 0.24, 0.95), Color(0.4, 0.5, 0.5, 0.4), 4, 1, 0)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	var slider_fill := style(Color(0.72, 0.56, 0.30, 1.0), Color(0.9, 0.72, 0.4, 0.7), 4, 1, 0)
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", slider_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", style(ThemeBuilder.GOLD_BRIGHT, Color.TRANSPARENT, 4, 0, 0))

	th.set_stylebox("background", "ProgressBar", style(Color(0.06, 0.09, 0.11, 0.9), Color(0.25, 0.35, 0.4, 0.35), 4, 1, 0))
	th.set_stylebox("fill", "ProgressBar", style(Color(0.55, 0.43, 0.22, 0.95), Color.TRANSPARENT, 4, 0, 0))
	th.set_color("font_color", "ProgressBar", TEXT)
	th.set_font_size("font_size", "ProgressBar", 11)

	th.set_stylebox("scroll", "VScrollBar", style(Color(0, 0, 0, 0.2), Color.TRANSPARENT, 4, 0, 3))
	th.set_stylebox("grabber", "VScrollBar", style(Color(0.35, 0.45, 0.42, 0.7), Color.TRANSPARENT, 4, 0, 3))
	th.set_stylebox("grabber_highlight", "VScrollBar", style(GOLD, Color.TRANSPARENT, 4, 0, 3))
	th.set_stylebox("scroll", "HScrollBar", style(Color(0, 0, 0, 0.2), Color.TRANSPARENT, 4, 0, 3))
	th.set_stylebox("grabber", "HScrollBar", style(Color(0.35, 0.45, 0.42, 0.7), Color.TRANSPARENT, 4, 0, 3))
	th.set_stylebox("grabber_highlight", "HScrollBar", style(GOLD, Color.TRANSPARENT, 4, 0, 3))

	th.set_stylebox("panel", "PopupMenu", style(Color(0.04, 0.06, 0.08, 0.98), Color(0.4, 0.5, 0.5, 0.4), 8, 1, 8))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)

	th.set_constant("separation", "VBoxContainer", 6)
	th.set_constant("separation", "HBoxContainer", 6)
	th.set_constant("margin_left", "MarginContainer", 12)
	th.set_constant("margin_right", "MarginContainer", 12)
	th.set_constant("margin_top", "MarginContainer", 10)
	th.set_constant("margin_bottom", "MarginContainer", 10)
	th.set_stylebox("panel", "ScrollContainer", style(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0, 0))
	th.set_font_size("normal_font_size", "RichTextLabel", 14)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_stylebox("normal", "RichTextLabel", style(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0, 0))
	return th


static func color_for_race(id: String) -> Color:
	return D.race(id).get("color_c", GOLD)
