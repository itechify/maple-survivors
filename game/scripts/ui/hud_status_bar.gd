class_name HudStatusBar
extends HudWidget
## The original status bar, gauges and identity; the right-hand decorative controls are reserved for potions. There is
## no MP (ADR 0006): the v83 art's MP gauge is drawn empty (all gray) with no numbers.

func _draw() -> void:
	var view := get_viewport_rect().size
	var o := bar_origin(view)
	_draw_bar(o, view)
	_draw_gauges(o + GAUGE_POS)
	_draw_level(o)

func _draw_bar(o: Vector2, view: Vector2) -> void:
	var bg := _frame(SB + "base/backgrnd")
	if bg != null:
		var col := Rect2(bg.region.position + Vector2(BAR_W / 2.0, 0), Vector2(1, bg.region.size.y))
		draw_texture_rect_region(bg.page, Rect2(0, o.y, view.x, BAR_H), col)
		_blit(bg, o)
	_blit(_frame(SB + "base/backgrnd2"), o)

func _draw_gauges(g: Vector2) -> void:
	var bar := _frame(SB + "gauge/bar")
	if bar == null:
		return
	_blit(bar, g)
	var hp := float(player_state.get("hp", 0))
	var max_hp := float(player_state.get("max_hp", 0))
	var exp_v := float(player_state.get("exp", 0))
	var exp_next := float(run_info.get("exp_next", 0))
	_gray(g, HP_FILL, fill_width(hp, max_hp, HP_FILL.y))
	_gray(g, MP_FILL, 0.0)
	_gray(g, EXP_FILL, fill_width(exp_v, exp_next, EXP_FILL.y))
	_blit(_frame(SB + "gauge/graduation"), g)
	_number_text(g + Vector2(HP_TEXT_X, TEXT_Y), "[%d/%d]" % [int(hp), int(max_hp)])
	var pct := 0 if exp_next <= 0.0 else int(floorf(100.0 * clampf(exp_v / exp_next, 0.0, 1.0)))
	_number_text(g + Vector2(EXP_TEXT_X, TEXT_Y), "%d[%d%%]" % [int(exp_v), pct])

func _gray(g: Vector2, fill: Vector2, filled: float) -> void:
	var gray := _frame(SB + "gauge/gray")
	if gray == null or filled >= fill.y:
		return
	var x := g.x + fill.x + filled
	draw_texture_rect_region(gray.page, Rect2(x, g.y + FILL_Y, fill.y - filled, FILL_H), gray.region)

func _number_text(p: Vector2, text: String) -> void:
	var x := p.x
	for i in text.length():
		var ch := text[i]
		var key: String = {"[": "Lbracket", "]": "Rbracket", "/": "slash", "%": "percent"}.get(ch, ch)
		var f := _frame(SB + "number/" + key)
		if f == null:
			continue
		var dy := 0.0 if (ch == "[" or ch == "]") else 1.0
		_blit(f, Vector2(x, p.y + dy))
		x += f.region.size.x + 1.0

func _draw_level(o: Vector2) -> void:
	var lv := str(int(player_state.get("level", 1)))
	var x := o.x + LEVEL_POS.x
	for i in lv.length():
		var f := _frame("UI.wz/Basic.img/LevelNo/" + lv[i])
		if f == null:
			continue
		_blit(f, Vector2(x, o.y + LEVEL_POS.y))
		x += f.region.size.x
	_text(o + JOB_POS, str(run_info.get("job_name", "")), Color(1, 1, 1))
	_text(o + NAME_POS, str(run_info.get("name", "")), Color(1, 1, 1))
