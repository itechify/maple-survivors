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
## Shared number of quantized cooldown sweep steps.
const SWEEP_STEPS := CooldownSweep.SWEEP_STEPS
## tier C: blue modulation of a ready skill waiting for MP.
const MP_WAIT_TINT := Color(0.35, 0.5, 1.0)
## An icon's state byte: normal (0) or waiting for MP (RunWorld.read_skill_cooldowns).
const STATE_MP_WAIT := RunWorld.SKILL_STATE_MP_WAIT

## Reused overlay polygon (CooldownSweep resizes it in place).
var _sweep := PackedVector2Array()
## Per icon (info.skills order): the drawn sweep step (sweep_step) and state byte (0 / STATE_MP_WAIT).
var _steps := PackedInt32Array()
var _short := PackedByteArray()


## The shared overlay step of an icon `remaining` of `total` seconds from ready.
static func sweep_step(remaining: float, total: float) -> int:
	return CooldownSweep.sweep_step(remaining, total)


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
		_short[i] = STATE_MP_WAIT if bool(row.get("mp_short", false)) else 0


## The per-frame cooldowns of the icons, in snapshot order (RunWorld.read_skill_cooldowns' buffers). Builds nothing;
## queues a redraw and returns true only when an icon's sweep step or state (MP tint) changed.
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


## What each icon shows now: [{icon, rank, key_label, sweep_step, mp_short}] in snapshot order (for tests).
func displayed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var skills: Array = run_info.get("skills", [])
	for i in skills.size():
		var row: Dictionary = skills[i] if skills[i] is Dictionary else {}
		out.append({"icon": String(row.get("icon", "")), "rank": int(row.get("rank", 0)),
			"key_label": String(row.get("key_label", "")), "sweep_step": _steps[i], "mp_short": _short[i] == STATE_MP_WAIT})
	return out


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
			var tint := MP_WAIT_TINT if _short[n] == STATE_MP_WAIT else Color.WHITE
			PixelDraw.blit_scaled(self, icon.page, rect, icon.region, tint)
			CooldownSweep.draw_overlay(self, _steps[n], rect, _sweep)
			_rank(p + Vector2(ICON_SIZE, ICON_SIZE), int(s.get("rank", 0)))
		_text(p + Vector2(1, 10), String(s.get("key_label", "")), Color.WHITE, 10)
		i += 1
