class_name HudSkills
extends HudWidget
## Owned skill icons and ranks, supplied independently by RunScene. A cooling skill is covered by a dark overlay that
## clears clockwise from 12 o'clock (one polygon per icon); a ready skill waiting for MP is tinted blue.
##
## Two feeds: update(ps, info) takes the run's snapshot (info.skills: icon, rank, key_label, cooldown_left,
## cooldown_total, mp_short) when it changes; set_cooldowns() takes the per-frame cooldowns from reused buffers
## (RunWorld.read_skill_cooldowns, same order) and redraws only when an icon's sweep step or MP tint changed.

## tier C: eight 24 px icons per row keep fifteen skills left of the timer and boss bars at 800 px.
const ICON_SIZE := 24
const COLUMNS := 8
## tier C: below this remaining fraction the sweep is not drawn (a sliver too thin to triangulate or see).
const SWEEP_MIN := 0.002
## tier C: the sweep moves in steps of 1/SWEEP_STEPS of the cooldown (96 = one step per pixel of a 24 px icon's
## edge): smooth to the eye, and a long cooldown does not redraw the widget every frame.
const SWEEP_STEPS := 96
## Icon corners (half-size units) clockwise from 12 o'clock: top-right, bottom-right, bottom-left, top-left.
const CORNERS: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
## tier C: the cooldown overlay's darkness, and the blue modulation of a ready skill waiting for MP (it replaced
## Teleport's grey can't-afford tint so every skill shows the same cue).
const SWEEP_COLOR := Color(0, 0, 0, 0.6)
const MP_WAIT_TINT := Color(0.35, 0.5, 1.0)
## tier C: an icon whose skill the held weapon cannot use is greyed (the Skill window greys the same skill).
const BLOCKED_TINT := Color(0.4, 0.4, 0.4)
## An icon's state byte: normal (0), waiting for MP, blocked by the held weapon (RunWorld.read_skill_cooldowns).
const STATE_MP_WAIT := RunWorld.SKILL_STATE_MP_WAIT
const STATE_BLOCKED := RunWorld.SKILL_STATE_BLOCKED

## Reused overlay polygon (sweep_polygon resizes it in place).
var _sweep := PackedVector2Array()
## Per icon (info.skills order): the drawn sweep step (sweep_step) and state byte (0 / STATE_MP_WAIT / STATE_BLOCKED).
var _steps := PackedInt32Array()
var _short := PackedByteArray()


## The sweep step of an icon `remaining` of `total` seconds from ready: 0 when ready, before any cast or below
## SWEEP_MIN; SWEEP_STEPS when the overlay is full.
static func sweep_step(remaining: float, total: float) -> int:
	var f := clampf(remaining / total, 0.0, 1.0) if total > 0.0 else 0.0
	if f < SWEEP_MIN:
		return 0
	return clampi(ceili(f * SWEEP_STEPS), 1, SWEEP_STEPS)


## Takes the run's skill snapshot (see the class doc), including each icon's cooldown at that moment.
func update(p_player_state: Dictionary, p_run_info: Dictionary) -> void:
	super.update(p_player_state, p_run_info)
	var skills: Array = p_run_info.get("skills", [])
	_steps.resize(skills.size())
	_short.resize(skills.size())
	for i in skills.size():
		var s: Variant = skills[i]
		var row: Dictionary = s if s is Dictionary else {}
		_steps[i] = sweep_step(float(row.get("cooldown_left", 0.0)), float(row.get("cooldown_total", 0.0)))
		_short[i] = STATE_BLOCKED if bool(row.get("blocked", false)) \
			else STATE_MP_WAIT if bool(row.get("mp_short", false)) else 0


## The per-frame cooldowns of the icons, in snapshot order (RunWorld.read_skill_cooldowns' buffers). Builds nothing;
## queues a redraw and returns true only when an icon's sweep step or state (MP tint, blocked grey) changed.
func set_cooldowns(left: PackedFloat32Array, total: PackedFloat32Array, state: PackedByteArray) -> bool:
	var changed := false
	for i in mini(_steps.size(), mini(left.size(), mini(total.size(), state.size()))):
		var step := sweep_step(left[i], total[i])
		if step != _steps[i] or state[i] != _short[i]:
			_steps[i] = step
			_short[i] = state[i]
			changed = true
	if changed:
		queue_redraw()
	return changed


## What each icon shows now: [{icon, rank, key_label, sweep_step, mp_short, blocked}] in snapshot order (for tests).
func displayed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var skills: Array = run_info.get("skills", [])
	for i in skills.size():
		var row: Dictionary = skills[i] if skills[i] is Dictionary else {}
		out.append({"icon": String(row.get("icon", "")), "rank": int(row.get("rank", 0)),
			"key_label": String(row.get("key_label", "")), "sweep_step": _steps[i], "mp_short": _short[i] == STATE_MP_WAIT,
			"blocked": _short[i] == STATE_BLOCKED})
	return out


## Fills `out` with the dark cooldown overlay of an icon in `rect`: with fraction f = remaining / total left, a wedge
## of f x 360 degrees from the centre, clipped to the icon and ending at 12 o'clock, so the overlay clears clockwise
## from 12 o'clock. Empty when ready, before any cast (total <= 0) or below SWEEP_MIN; the whole rect when full.
## `out` is the caller's reused array (resized in place), so the draw loop builds no new array per icon.
static func sweep_polygon(remaining: float, total: float, rect: Rect2, out: PackedVector2Array) -> void:
	var f := clampf(remaining / total, 0.0, 1.0) if total > 0.0 else 0.0
	if f < SWEEP_MIN:
		out.resize(0)
		return
	if f >= 1.0 - SWEEP_MIN:
		out.resize(4)
		out[0] = rect.position
		out[1] = Vector2(rect.end.x, rect.position.y)
		out[2] = rect.end
		out[3] = Vector2(rect.position.x, rect.end.y)
		return
	var c := rect.get_center()
	var h := rect.size * 0.5
	var start := (1.0 - f) * TAU
	out.resize(7)
	out[0] = c
	out[1] = _edge_point(c, h, start)
	var n := 2
	for corner: Vector2 in CORNERS:
		if fposmod(atan2(corner.x * h.x, -corner.y * h.y), TAU) > start + 1e-5:
			out[n] = c + corner * h
			n += 1
	out[n] = Vector2(c.x, rect.position.y)
	out.resize(n + 1)


## Where the ray from `c` at clockwise-from-12 angle `a` leaves a box of half size `h`.
static func _edge_point(c: Vector2, h: Vector2, a: float) -> Vector2:
	var d := Vector2(sin(a), -cos(a))
	var t := INF
	if absf(d.x) > 1e-9:
		t = h.x / absf(d.x)
	if absf(d.y) > 1e-9:
		t = minf(t, h.y / absf(d.y))
	return c + d * t


func _draw() -> void:
	var skills: Array = run_info.get("skills", [])
	var i := 0
	for n in mini(skills.size(), _steps.size()):
		var s: Variant = skills[n]
		if not (s is Dictionary):
			continue
		var p := Vector2(8 + (i % COLUMNS) * (ICON_SIZE + SKILL_GAP), 8 + (i / COLUMNS) * (ICON_SIZE + SKILL_GAP))
		var icon := _frame(str(s.get("icon", "")))
		if icon != null:
			var rect := Rect2(p, Vector2(ICON_SIZE, ICON_SIZE))
			var tint := BLOCKED_TINT if _short[n] == STATE_BLOCKED \
				else MP_WAIT_TINT if _short[n] == STATE_MP_WAIT else Color.WHITE
			PixelDraw.blit_scaled(self, icon.page, rect, icon.region, tint)
			sweep_polygon(float(_steps[n]), float(SWEEP_STEPS), rect, _sweep)
			if not _sweep.is_empty():
				draw_colored_polygon(_sweep, SWEEP_COLOR)
			_rank(p + Vector2(ICON_SIZE, ICON_SIZE), int(s.get("rank", 0)))
		_text(p + Vector2(1, 10), String(s.get("key_label", "")), Color.WHITE, 10)
		i += 1
