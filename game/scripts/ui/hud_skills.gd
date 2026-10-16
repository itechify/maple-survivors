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
			# tier C: grey modulation makes a manual skill's MP affordability visible without another notice.
			var tint := Color.WHITE if bool(s.get("affordable", true)) else Color(0.35, 0.35, 0.35)
			draw_texture_rect_region(icon.page, Rect2(p, Vector2(ICON_SIZE, ICON_SIZE)), icon.region, tint)
			_rank(p + Vector2(ICON_SIZE, ICON_SIZE), int(s.get("rank", 0)))
		_text(p + Vector2(1, 10), String(s.get("key_label", "")), Color.WHITE, 10)
		i += 1
