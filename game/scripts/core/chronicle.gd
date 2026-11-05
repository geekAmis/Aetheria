class_name ChronicleData
extends RefCounted
## Летопись мира. События с фильтрами, важностью и привязкой к месту.

var events: Array = []
var population_history: Array = []  # [{year, pop, settlements}]
var max_events := 500


func add(year: int, day: int, type: String, text: String, importance: int = 1, settlement_id: int = -1, pos: Vector2 = Vector2(-1, -1), icon: String = "dot") -> void:
	events.append({
		"year": year, "day": day, "type": type, "text": text,
		"importance": importance, "settlement_id": settlement_id,
		"pos": [pos.x, pos.y], "icon": icon
	})
	if events.size() > max_events:
		events = events.slice(events.size() - max_events, events.size())


func record_population(year: int, pop: int, settlements: int) -> void:
	if population_history.size() > 0 and population_history.back().get("year", -1) == year:
		population_history.back()["pop"] = pop
		population_history.back()["settlements"] = settlements
	else:
		population_history.append({"year": year, "pop": pop, "settlements": settlements})
	if population_history.size() > 900:
		population_history = population_history.slice(population_history.size() - 900, population_history.size())


func count_type(type: String) -> int:
	var c := 0
	for e in events:
		if e.type == type:
			c += 1
	return c


func to_dict() -> Dictionary:
	return {"events": events, "population_history": population_history}


static func from_dict(d: Dictionary) -> ChronicleData:
	var c := ChronicleData.new()
	c.events = d.get("events", []).duplicate(true)
	c.population_history = d.get("population_history", []).duplicate(true)
	return c
