class_name HudSkills
extends HudWidget
## Owned skill icons and ranks, supplied independently by RunScene.

func _draw() -> void:
	var x := 8.0
	for s: Variant in run_info.get("skills", []):
		if not (s is Dictionary):
			continue
		var icon := _frame(str(s.get("icon", "")))
		if icon != null:
			_blit(icon, Vector2(x, 8))
			_rank(Vector2(x + SKILL_ICON, 8 + SKILL_ICON), int(s.get("rank", 0)))
		x += SKILL_ICON + SKILL_GAP


