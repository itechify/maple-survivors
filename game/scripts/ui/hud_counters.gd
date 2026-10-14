class_name HudCounters
extends HudWidget
## Survival timer and kill count, supplied independently by RunScene.

func _draw() -> void:
	var view := get_viewport_rect().size
	var t := float(run_info.get("time", 0.0))
	if run_info.has("time_limit"):
		t = maxf(0.0, float(run_info.time_limit) - t)
	var big := FONT_SIZE + 8
	var ts := format_time(t)
	var tw := bold_font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(Vector2(floorf((view.x - tw) * 0.5), 28), ts, Color(1, 1, 1), big, bold_font)
	var ks := "KILLS %d" % int(run_info.get("kills", 0))
	var kw := bold_font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(Vector2(view.x - kw - 12, 28), ks, Color(1, 0.86, 0.3), big, bold_font)

