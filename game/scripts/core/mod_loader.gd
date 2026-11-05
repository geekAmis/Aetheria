class_name ModLoader
extends RefCounted
## Аддитивные моды: новые файлы/скрипты поверх игры, без изменения ядра.
## Скрипт мода — mods/<name>/mod.gd, опционально с func setup(game).


static func load_for_game(game) -> void:
	var loaded: Array = []
	for root in D.mod_roots():
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		for mod_name in dir.get_directories():
			var base: String = str(root).path_join(mod_name)
			var entry: String = base.path_join("mod.gd")
			if not FileAccess.file_exists(entry):
				continue
			var script := _load_script(entry)
			if script == null:
				push_warning("[mods] cannot compile: " + entry)
				continue
			var instance = script.new()
			if instance == null:
				push_warning("[mods] cannot instantiate: " + entry)
				continue
			if instance is Node:
				instance.name = "Mod_" + str(mod_name).replace(" ", "_")
				game.add_child(instance)
				if instance.has_method("setup"):
					instance.call("setup", game)
			elif instance.has_method("setup"):
				instance.call("setup", game)
				game.set_meta("mod_" + str(mod_name), instance)
			loaded.append(str(mod_name))
	if not loaded.is_empty():
		print("[Mods] scripts: ", ", ".join(loaded))


static func _load_script(path: String) -> Script:
	if path.begins_with("res://") or path.begins_with("user://"):
		var res = load(path)
		if res is Script:
			return res
		return null
	# Портативная папка рядом с Aetheria.exe — абсолютный путь.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var src := f.get_as_text()
	f.close()
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return null
	return script
