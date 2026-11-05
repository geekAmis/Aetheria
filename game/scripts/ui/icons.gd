class_name Icons
extends RefCounted
## Векторные иконки, рисуемые из SVG-путей в рантайме. Белые — тонируются modulate.

static var _cache: Dictionary = {}
static var _paths := {
	"raise": "<path d='M12 20V6M6 12l6-6 6 6'/><path d='M4 20h16'/>",
	"lower": "<path d='M12 4v14M6 12l6 6 6-6'/><path d='M4 20h16'/>",
	"smooth": "<path d='M3 15c3-6 6 6 9 0s6 6 9 0'/><path d='M3 8c3-4 6 4 9 0s6 4 9 0' opacity='.5'/>",
	"mountain": "<path d='M2 20l7-13 4 7 2-3 7 9z' fill='white' fill-opacity='.18'/><path d='M9 7l-2 4h4z' fill='white'/>",
	"hill": "<path d='M2 19c3-6 6-6 9 0M12 19c3-4 6-4 9 0'/>",
	"sand": "<path d='M3 18c3-2 6-2 9 0s6 2 9 0'/><circle cx='7' cy='11' r='1' fill='white'/><circle cx='13' cy='9' r='1' fill='white'/><circle cx='17' cy='13' r='1' fill='white'/>",
	"grass": "<path d='M12 21V9M12 14c0-4-3-6-6-6 0 4 3 6 6 6zM12 16c0-4 3-6 6-6 0 4-3 6-6 6z'/><path d='M12 21c0-4-2-7-5-9M12 21c0-4 2-7 5-9' opacity='.6'/>",
	"forest": "<path d='M8 21v-5M8 16l-4-6h3L4 5h8L9 10h3z' fill='white' fill-opacity='.16'/><path d='M17 21v-4M17 17l-3-5h2L14 8h6l-2 4h2z' fill='white' fill-opacity='.16'/>",
	"water": "<path d='M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0'/><path d='M3 14c2-2 4-2 6 0s4 2 6 0 4-2 6 0'/><path d='M3 19c2-2 4-2 6 0s4 2 6 0 4-2 6 0'/>",
	"river": "<path d='M6 3c0 5 6 5 6 10s-5 4-5 8'/><path d='M14 3c0 5 5 5 5 10' opacity='.5'/>",
	"lake": "<path d='M12 3s6 7 6 11a6 6 0 1 1-12 0c0-4 6-11 6-11z' fill='white' fill-opacity='.18'/>",
	"ocean": "<path d='M2 8c3-3 5 3 8 0s5 3 8 0 2 0 4 0'/><path d='M2 14c3-3 5 3 8 0s5 3 8 0 2 0 4 0'/><path d='M2 20c3-3 5 3 8 0s5 3 8 0 2 0 4 0'/>",
	"dry": "<circle cx='17' cy='6' r='3'/><path d='M3 20l4-6 3 3 4-7 6 10' fill='white' fill-opacity='.12'/>",
	"tree": "<path d='M12 22v-6'/><path d='M12 16l-6-8h4L7 3h10l-3 5h4z' fill='white' fill-opacity='.18'/>",
	"bush": "<path d='M4 20c0-4 3-6 8-6s8 2 8 6z' fill='white' fill-opacity='.16'/><path d='M12 14V9M9 12l-3-2M15 11l3-2'/>",
	"paw": "<circle cx='7' cy='8' r='1.7'/><circle cx='12' cy='6' r='1.7'/><circle cx='17' cy='8' r='1.7'/><path d='M12 11c-4 0-6 3-5 6 1 3 4 2 5 2s4 1 5-2c1-3-1-6-5-6z' fill='white'/>",
	"people": "<circle cx='9' cy='8' r='3'/><path d='M3 21c0-4 2-7 6-7s6 3 6 7'/><circle cx='17' cy='9' r='2.4'/><path d='M15 14c4 0 6 2 6 6'/>",
	"lightning": "<path d='M13 2L4 14h7l-1 8 9-12h-7z' fill='white' fill-opacity='.9'/>",
	"tornado": "<path d='M3 5h18M5 9h14M7 13h10M9 17h7M11 21h3'/>",
	"meteor": "<circle cx='16' cy='8' r='4' fill='white' fill-opacity='.25'/><path d='M15 9L3 21M10 4L2 12M18 14L8 22'/>",
	"bomb": "<circle cx='11' cy='14' r='7' fill='white' fill-opacity='.2'/><path d='M16 8l3-3M17 4h4v4'/>",
	"nuke": "<circle cx='12' cy='12' r='2' fill='white'/><path d='M12 3a9 9 0 0 1 5 2l-3 5-2-1zM7 19a9 9 0 0 1-3-8l6 1v2zM17 19l-3-5 2-1 3 5a9 9 0 0 1-2 1z' fill='white' fill-opacity='.8'/>",
	"quake": "<path d='M2 16h4l2-5 3 9 2-11 3 7h6'/>",
	"rain": "<path d='M6 14a4 4 0 1 1 1-8 5 5 0 0 1 10 0 4 4 0 1 1 1 8z' fill='white' fill-opacity='.14'/><path d='M7 18l-1 3M12 18l-1 3M17 18l-1 3'/>",
	"acid": "<path d='M12 3s5 6 5 10a5 5 0 1 1-10 0c0-4 5-10 5-10z' fill='white' fill-opacity='.14'/><path d='M6 21h12M8 18h8' opacity='.6'/>",
	"fire": "<path d='M12 2c1 5 6 6 6 12a6 6 0 1 1-12 0c0-3 2-5 3-7 0 3 2 4 3 4 1-3 0-6 0-9z' fill='white' fill-opacity='.2'/>",
	"plague": "<path d='M12 3v18M4 7l16 10M20 7L4 17'/><circle cx='12' cy='12' r='3' fill='white'/>",
	"drought": "<circle cx='12' cy='9' r='4' fill='white' fill-opacity='.25'/><path d='M3 20c3-2 5 2 8 0s5 2 8 0M6 16l2-2M15 17l2-2'/>",
	"flood": "<path d='M5 12V5h8v7M3 12h12'/><path d='M2 17c2-2 4-2 6 0s4 2 6 0 4-2 6 0M2 21c2-2 4-2 6 0s4 2 6 0 4-2 6 0'/>",
	"volcano": "<path d='M2 21l6-12h8l6 12z' fill='white' fill-opacity='.12'/><path d='M10 9l2-4 2 4M12 2v2'/><path d='M8 14c2 1 6-1 8 0'/>",
	"snow": "<path d='M12 2v20M3 6l18 12M21 6L3 18M9 4l3 2 3-2M9 20l3-2 3 2'/>",
	"gift": "<path d='M3 9h18v3H3zM5 12v9h14v-9M12 9v12'/><path d='M12 9c-4 0-6-1-6-3s4-2 6 3c2-5 6-5 6-3s-2 3-6 3z'/>",
	"tech": "<circle cx='12' cy='12' r='2' fill='white'/><ellipse cx='12' cy='12' rx='10' ry='4'/><ellipse cx='12' cy='12' rx='4' ry='10'/>",
	"crown": "<path d='M3 18h18l-2-10-5 4-2-7-2 7-5-4z' fill='white' fill-opacity='.2'/><path d='M5 21h14'/>",
	"sword": "<path d='M4 20l4-4M14 3l7 7-9 9-4-4z' fill='white' fill-opacity='.12'/><path d='M3 21l4-4M12 8l4 4'/>",
	"peace": "<path d='M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z'/><path d='M12 3v18M12 12l6-5M12 12l-6-5'/>",
	"prophet": "<path d='M12 2l2 5 5 .5-4 3 1 5-4-2.5L8 15l1-5-4-3 5-.5z' fill='white' fill-opacity='.8'/><path d='M6 21c0-3 2-5 6-5s6 2 6 5'/>",
	"miracle": "<path d='M12 2v4M12 18v4M2 12h4M18 12h4M5 5l3 3M16 16l3 3M19 5l-3 3M8 16l-3 3'/><circle cx='12' cy='12' r='2' fill='white'/>",
	"heart": "<path d='M12 21S3 14 3 8a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 6-9 13-9 13z' fill='white' fill-opacity='.22'/>",
	"leaf": "<path d='M20 3C10 4 4 9 4 16c0 3 2 5 5 5 7 0 11-7 11-18z' fill='white' fill-opacity='.14'/><path d='M4 20C8 14 13 10 20 6'/>",
	"book": "<path d='M4 4h7a3 3 0 0 1 3 3v14a3 3 0 0 0-3-3H4z'/><path d='M20 4h-7a3 3 0 0 0-3 3v14a3 3 0 0 1 3-3h7z'/>",
	"luck": "<path d='M12 12c-4-4-8-2-8 1s4 4 8-1zm0 0c4-4 8-2 8 1s-4 4-8-1zm0 0c-4 4-2 8 1 8s4-4-1-8zm0 0c4 4 2 8-1 8s-4-4 1-8z' fill='white' fill-opacity='.2'/>",
	"skull": "<path d='M12 2a8 8 0 0 0-8 8c0 3 1 4 2 5v4h3v3h6v-3h3v-4c1-1 2-2 2-5a8 8 0 0 0-8-8z' fill='white' fill-opacity='.16'/><circle cx='9' cy='10' r='1.5' fill='white'/><circle cx='15' cy='10' r='1.5' fill='white'/><path d='M12 13v3'/>",
	"ghost": "<path d='M5 21V9a7 7 0 0 1 14 0v12l-2-2-2 2-2-2-2 2-2-2z' fill='white' fill-opacity='.14'/><circle cx='9' cy='9' r='1.4' fill='white'/><circle cx='15' cy='9' r='1.4' fill='white'/>",
	"inspect": "<circle cx='10' cy='10' r='6'/><path d='M15 15l6 6'/>",
	"chronicle": "<path d='M5 3h13a2 2 0 0 1 2 2v16H7a2 2 0 0 1-2-2z'/><path d='M8 7h8M8 11h8M8 15h5'/>",
	"world": "<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c3 3 4 6 4 9s-1 6-4 9M12 3c-3 3-4 6-4 9s1 6 4 9'/>",
	"stats": "<path d='M4 20V10M10 20V4M16 20v-7M22 20H2'/>",
	"map": "<path d='M3 5l6-2 6 2 6-2v16l-6 2-6-2-6 2z'/><path d='M9 3v16M15 5v16'/>",
	"settings": "<circle cx='12' cy='12' r='3'/><path d='M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2'/>",
	"pause": "<path d='M8 5v14M16 5v14'/>",
	"play": "<path d='M7 4l13 8-13 8z' fill='white'/>",
	"speed": "<path d='M3 5l9 7-9 7zM12 5l9 7-9 7z' fill='white' fill-opacity='.85'/>",
	"save": "<path d='M4 3h13l3 3v15H4z'/><path d='M8 3v6h8V3M8 21v-7h8v7'/>",
	"load": "<path d='M3 6h7l2 3h9v11H3z'/><path d='M3 9h18'/>",
	"home": "<path d='M3 11l9-8 9 8M5 10v11h14V10'/>",
	"close": "<path d='M5 5l14 14M19 5L5 19'/>",
	"plus": "<path d='M12 4v16M4 12h16'/>",
	"minus": "<path d='M4 12h16'/>",
	"eye": "<path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z'/><circle cx='12' cy='12' r='3' fill='white'/>",
	"layers": "<path d='M12 2l10 5-10 5L2 7zM2 12l10 5 10-5M2 17l10 5 10-5'/>",
	"essence": "<path d='M12 2l7 7-7 13-7-13z' fill='white' fill-opacity='.25'/><path d='M5 9h14M12 2L8 9l4 13 4-13z'/>",
	"era": "<path d='M6 3h12M6 21h12M7 3c0 5 10 5 10 0M7 21c0-5 10-5 10 0'/><path d='M12 12v5'/>",
	"calendar": "<rect x='3' y='5' width='18' height='16' rx='2'/><path d='M8 3v4M16 3v4M3 10h18'/>",
	"wheat": "<path d='M12 22V8M12 12c-3 0-4-2-4-5 3 0 4 2 4 5zM12 12c3 0 4-2 4-5-3 0-4 2-4 5zM12 17c-3 0-4-2-4-5 3 0 4 2 4 5zM12 17c3 0 4-2 4-5-3 0-4 2-4 5z'/>",
	"log": "<path d='M4 7l8-4 8 4-8 4zM4 7v10l8 4 8-4V7M12 11v10'/>",
	"rock": "<path d='M4 16l4-10 8-2 4 8-2 8H7z' fill='white' fill-opacity='.16'/>",
	"iron": "<path d='M4 16l3-7h10l3 7zM6 16v4h12v-4M8 9l1-3h6l1 3'/>",
	"coin": "<circle cx='12' cy='12' r='9'/><path d='M12 6v12M9 9h6M9 15h6'/>",
	"crate": "<path d='M3 6l9-3 9 3v12l-9 3-9-3zM3 6l9 3 9-3M12 9v12M7 4.6v12M17 4.6v12'/>",
	"flask": "<path d='M9 3h6M10 3v6L4 19a2 2 0 0 0 2 3h12a2 2 0 0 0 2-3L14 9V3'/><path d='M7 16h10'/>",
	"temple": "<path d='M3 9l9-6 9 6zM5 9v9M9 9v9M15 9v9M19 9v9M3 21h18M3 18h18'/>",
	"smile": "<circle cx='12' cy='12' r='9'/><path d='M8 14s1 3 4 3 4-3 4-3'/><circle cx='9' cy='9' r='1' fill='white'/><circle cx='15' cy='9' r='1' fill='white'/>",
	"shield": "<path d='M12 2l8 3v6c0 5-3 9-8 11-5-2-8-6-8-11V5z' fill='white' fill-opacity='.14'/><path d='M12 6v10'/>",
	"wand": "<path d='M4 20L16 8M14 4l1 4 4 1-4 1-1 4-1-4-4-1 4-1z'/>",
	"brush": "<path d='M4 20c4 0 5-2 5-5l8-8 3 3-8 8c-2 3-4 4-8 4z'/><path d='M14 5l3-3 3 3-3 3z'/>",
	"music": "<path d='M9 18V5l10-2v13'/><circle cx='6' cy='18' r='3'/><circle cx='16' cy='16' r='3'/>",
	"sound": "<path d='M4 9v6h4l5 4V5L8 9z'/><path d='M16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12'/>",
	"star": "<path d='M12 2l3 7 7 .5-5 4.5 2 7-7-4-7 4 2-7-5-4.5 7-.5z' fill='white' fill-opacity='.25'/>",
	"dot": "<circle cx='12' cy='12' r='4' fill='white'/>",
	"chevron": "<path d='M9 5l7 7-7 7'/>",
	"war": "<path d='M4 20l4-4M14 3l7 7-9 9-4-4zM12 8l4 4M3 21l4-4'/><path d='M17 17l4 4M20 4l-4 4M16 3l-2 2M21 8l-2 2' opacity='.7'/>",
	"food": "<path d='M4 21h16M6 21c0-6 2-10 6-10s6 4 6 10'/><path d='M12 11V4M9 6c0-2 3-3 3-3s3 1 3 3'/>",
	"leader": "<circle cx='12' cy='8' r='4'/><path d='M4 21c0-5 3-8 8-8s8 3 8 8'/><path d='M9 4l3-2 3 2'/>",
	"info": "<circle cx='12' cy='12' r='9'/><path d='M12 11v6'/><circle cx='12' cy='7.5' r='1' fill='white'/>",
	"fast": "<path d='M12 4l8 8-8 8M4 4l8 8-8 8'/>"
}


static func get_icon(icon_name: String, scale: float = 3.0) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var body: String = _paths.get(icon_name, _paths["dot"])
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>" + body + "</svg>"
	var img := Image.new()
	var err := img.load_svg_from_string(svg, scale)
	if err != OK:
		img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_cache[icon_name] = tex
	return tex


static func icon_rect(icon_name: String, tint: Color, px: int = 20) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = get_icon(icon_name)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
