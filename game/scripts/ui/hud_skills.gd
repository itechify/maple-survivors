class_name HudSkills
extends HudWidget
## Owned skill icons and ranks, supplied independently by RunScene.

## tier C: eight 24 px icons per row keep fifteen skills left of the timer and boss bars at 800 px.
const ICON_SIZE := 24
const COLUMNS := 8


func _draw() -> void:
	var i := 0
	for s: Variant in run_info.get("skills", []):
		if not (s is Dictionary):
			continue
		var p := Vector2(8 + (i % COLUMNS) * (ICON_SIZE + SKILL_GAP), 8 + (i / COLUMNS) * (ICON_SIZE + SKILL_GAP))
		var icon := _frame(str(s.get("icon", "")))
		if icon != null:
			_blit_rect(icon, Rect2(p, Vector2(ICON_SIZE, ICON_SIZE)))
			_rank(p + Vector2(ICON_SIZE, ICON_SIZE), int(s.get("rank", 0)))
		i += 1
