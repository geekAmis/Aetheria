extends Node
## Save — JSON-снапшоты мира + пользовательские настройки.

const SAVE_DIR := "user://saves"
const SLOT_AUTO := 0
const SLOT_MANUAL := 1
const VERSION := 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.aetheria.json" % [SAVE_DIR, slot]


func save_world(slot: int, data: Dictionary) -> bool:
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	data["saved_at_text"] = Time.get_datetime_string_from_system(false, true)
	var txt := JSON.stringify(data, "\t")
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: " + slot_path(slot))
		return false
	f.store_string(txt)
	f.close()
	return true


func load_world(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		push_error("Corrupt save: " + path)
		return {}
	return parsed


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func list_slots() -> Array:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var out: Array = []
	for s in range(0, 4):
		var path := slot_path(s)
		if not FileAccess.file_exists(path):
			out.append({"slot": s, "exists": false})
			continue
		var info := {"slot": s, "exists": true, "name": "?", "year": 0, "pop": 0, "saved_at_text": "", "seed": 0}
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				info["name"] = parsed.get("world_name", "?")
				info["year"] = parsed.get("year", 0)
				info["pop"] = parsed.get("population", 0)
				info["saved_at_text"] = parsed.get("saved_at_text", "")
				info["seed"] = parsed.get("seed", 0)
				info["version"] = parsed.get("version", 1)
		out.append(info)
	return out


func latest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for s in range(0, 4):
		if not has_slot(s):
			continue
		var d := load_world(s)
		var t := float(d.get("saved_at", 0.0))
		if t > best_time:
			best_time = t
			best = s
	return best


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(SAVE_DIR))
