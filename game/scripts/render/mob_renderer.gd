class_name MobRenderer
extends Node2D
## Draws every live mob slot of a MobSwarm-like object with one RenderingServer canvas item per slot (SpritePool).
##
## Reads the struct-of-arrays state documented in docs/ARCHITECTURE.md 4.4.3: `kind x y state state_t anim_t facing
## alpha` (kind indexes `kind_ids`, the original mob ids). Stance per state: stand / move / jump / hit1 / die1 from
## Mob.wz/<id>.img (info/link followed), with fallbacks (fly mobs: fly; no jump: move; no hit1: stand). Looping stances
## use `anim_t`; hit1/die1 play once from `state_t` and hold their last frame. WZ mob art faces left, so facing = 1
## mirrors. Alpha = regen fade (`alpha`) x the frame's a0 -> a1 ramp (die1 fades).
##
## Foothold layers: to draw mobs inside MapRenderer.actor_layer(L), use one MobRenderer per layer that has floors and
## pass `only_layer` = L with a per-slot layer array kept by update_slot_layers() (the layer of the mob's foothold, kept
## while it is airborne). A filtered renderer only allocates canvas items up to the highest slot it draws.

## Mirrors MobSwarm.STAND..FREE (checked by tests/unit/test_render_mobs.gd so a rename fails a test, not a build).
const STAND := 0
const MOVE := 1
const JUMP := 2
const HIT := 3
const DIE := 4
const FREE := 5
## Stance names tried in order for each state.
const STANCES := {
	STAND: ["stand", "fly", "move"],
	MOVE: ["move", "fly", "stand"],
	JUMP: ["jump", "fly", "move", "stand"],
	HIT: ["hit1", "stand", "fly", "move"],
	DIE: ["die1", "hit1", "stand", "fly", "move"],
}
## tier A: original cached player-skill mob cues; Slow plays once, Poison, Threaten and Stun repeat (pos 2).
## Stun uses the shared v83 stars from Hero's Shout (asset_manifest.json).
const STATUS_PATHS := ["Skill.wz/210.img/skill/2101003/mob", "Skill.wz/210.img/skill/2101005/mob",
	"Skill.wz/120.img/skill/1201006/mob", "Skill.wz/111.img/skill/1111008/mob"]
const SLOW_CUE := 0
const POISON_CUE := 1
const THREATEN_CUE := 2
const STUN_CUE := 3
const CUES_PER_SLOT := 4
## tier C: persistent Slow cue after its one-shot art, freeze fallback (Cold Beam has no mob overlay), poison fallback.
const SLOW_TINT := Color(1.0, 0.72, 0.40)
const FREEZE_TINT := Color(0.45, 0.80, 1.0)
const POISON_TINT := Color(0.72, 0.45, 0.90)
## tier C: stun fallback tint when the cached stars are absent.
const STUN_TINT := Color(1.0, 0.95, 0.55)

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Mob ids whose images were not found.
var missing: PackedInt32Array = []
var _action_anims: Dictionary = {}

var _pool: SpritePool
var _status_pool: SpritePool
var _status_anims: Array = []
## mob id -> Array (indexed by state) of SpriteAnim or null.
var _by_id: Dictionary = {}
## Per (kind index, state) animation for the last kind_ids (flat: kind * FREE + state).
var _flat: Array = []
var _cached_ids := PackedInt32Array()


func _ready() -> void:
	_ensure_pool()


## Mob ids of a MobKind list (RunWorld.mob_kinds / MobSwarm.kinds), for update_from().
static func ids_from_kinds(kinds: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: Variant in kinds:
		out.append(int(k.id) if k is Object else int(k))
	return out


## Whether a state's animation loops (stand/move/jump) or plays once (hit1/die1).
static func state_loops(state: int) -> bool:
	return state != HIT and state != DIE


## Per-slot foothold layer for update_from()'s layer filter: `fh_layer[swarm.fh[i]]` (fh_layer = FootholdMap.layer) while
## the mob stands on a foothold, the last such layer while it is airborne (fh -1), `fallback` for a slot never seen on a
## floor or freed. Packed arrays are values: pass the previous result and keep the returned array.
static func update_slot_layers(swarm: Object, fh_layer: PackedInt32Array, layers: PackedInt32Array,
		fallback: int = 0) -> PackedInt32Array:
	var fhs: PackedInt32Array = swarm.fh
	var states: PackedInt32Array = swarm.state
	var n := fhs.size()
	var old := layers.size()
	layers.resize(n)
	for i in range(old, n):
		layers[i] = fallback
	var nl := fh_layer.size()
	for i in n:
		var f := fhs[i]
		if f >= 0 and f < nl:
			layers[i] = fh_layer[f]
		elif states[i] == FREE:
			layers[i] = fallback
	return layers


## Draws the swarm. `swarm` exposes the arrays above; `kind_ids[kind]` is the mob id. With `only_layer` >= 0 only the
## slots whose `slot_layers` entry equals it are drawn (see update_slot_layers()).
func update_from(swarm: Object, kind_ids: PackedInt32Array, only_layer: int = -1,
		slot_layers: PackedInt32Array = PackedInt32Array(), action_state: Dictionary = {}) -> void:
	_ensure_pool()
	var states: PackedInt32Array = swarm.state
	var kinds: PackedInt32Array = swarm.kind
	var xs: PackedFloat32Array = swarm.x
	var ys: PackedFloat32Array = swarm.y
	var st_t: PackedFloat32Array = swarm.state_t
	var an_t: PackedFloat32Array = swarm.anim_t
	var facing: PackedInt32Array = swarm.facing
	var alpha: PackedFloat32Array = swarm.alpha
	var statuses := swarm as MobSwarm
	var has_statuses := statuses != null and statuses.has_statuses()
	var status_left := PackedFloat64Array()
	var status_elapsed := PackedFloat32Array()
	if has_statuses:
		status_left = statuses.status_left
		status_elapsed = statuses.status_elapsed
		_load_status_anims()
	else:
		_status_pool.hide_from(0)
	var actions: PackedStringArray = action_state.get("actions", PackedStringArray())
	var action_times: PackedFloat32Array = action_state.get("times", PackedFloat32Array())
	var action_facings: PackedInt32Array = action_state.get("facings", PackedInt32Array())
	var n := states.size()
	var filtered := only_layer >= 0
	var nl := slot_layers.size()
	if not filtered:
		_pool.ensure(n)
	if kind_ids != _cached_ids:
		_cached_ids = kind_ids.duplicate()
		_flat.clear()
		for id in kind_ids:
			for st in range(STAND, FREE):
				_flat.append(anim_for(id, st))
	var nk := kind_ids.size()
	var cap := _pool.size()
	for i in n:
		var st := states[i]
		var k := kinds[i]
		if st < STAND or st >= FREE or k < 0 or k >= nk or (filtered and (i >= nl or slot_layers[i] != only_layer)):
			_pool.hide(i)
			if has_statuses:
				_hide_statuses(i)
			continue
		var anim: SpriteAnim = _flat[k * FREE + st]
		var loop := st < HIT
		var t := an_t[i] if loop else st_t[i]
		var face := facing[i]
		if st != DIE and i < actions.size() and actions[i] != "":
			var path := _lib().mob_anim_img_path(kind_ids[k]) + "/" + actions[i]
			if not _action_anims.has(path):
				_action_anims[path] = _lib().find_anim(path)
			var action: SpriteAnim = _action_anims[path]
			if action != null:
				anim = action
				loop = false
				t = float(action_times[i])
				face = int(action_facings[i])
		if anim == null:
			_pool.hide(i)
			if has_statuses:
				_hide_statuses(i)
			continue
		var f := anim.frames[anim.index_at(t, loop)]
		var a := clampf(alpha[i], 0.0, 1.0)
		if f.a0 != 1.0 or f.a1 != 1.0:
			var lt := fposmod(t, anim.total) if loop and anim.total > 0.0 else t
			a *= f.alpha_at(clampf(lt - f.start, 0.0, f.delay_s))
		if i >= cap:
			cap = i + 1
			_pool.ensure(cap)
		var pos := Vector2(roundf(xs[i]), roundf(ys[i]))
		var tint := Color.WHITE
		if has_statuses and st != DIE:
			var base := i * MobSwarm.STATUS_COUNT
			var slow := status_left[base + MobSwarm.SLOW]
			var poison := status_left[base + MobSwarm.POISON]
			var stun := status_left[base + MobSwarm.STUN]
			var threat := status_left[base + MobSwarm.THREATENED]
			if slow > 0.0 or poison > 0.0 or threat > 0.0 or stun > 0.0:
				var box: Rect2 = statuses.mob_kind(i).hitbox
				_draw_cue(i, SLOW_CUE, slow, status_elapsed[base + MobSwarm.SLOW], box, pos, face > 0, a)
				_draw_cue(i, POISON_CUE, poison, status_elapsed[base + MobSwarm.POISON], box, pos, face > 0, a)
				_draw_cue(i, THREATEN_CUE, threat, status_elapsed[base + MobSwarm.THREATENED], box, pos, face > 0, a)
				_draw_cue(i, STUN_CUE, stun, status_elapsed[base + MobSwarm.STUN], box, pos, face > 0, a)
			else:
				_hide_statuses(i)
			if slow > 0.0:
				tint = SLOW_TINT
			if poison > 0.0 and _status_anims[POISON_CUE] == null:
				tint = POISON_TINT
			if stun > 0.0 and _status_anims[STUN_CUE] == null:
				tint = STUN_TINT
			if status_left[base + MobSwarm.FREEZE] > 0.0:
				tint = FREEZE_TINT
		elif has_statuses:
			_hide_statuses(i)
		_pool.show(i, f, pos, face > 0, a, 0.0, tint)
	_pool.hide_from(n)
	_status_pool.hide_from(n * CUES_PER_SLOT)


func _load_status_anims() -> void:
	if not _status_anims.is_empty():
		return
	for path: String in STATUS_PATHS:
		_status_anims.append(_lib().find_anim(path))


## Shows cue `cue` (Slow plays once, Poison, Threaten and Stun repeat) of slot i while its status has `left` seconds.
func _draw_cue(i: int, cue: int, left: float, elapsed: float, box: Rect2, pos: Vector2, flip: bool, alpha: float) -> void:
	var slot := i * CUES_PER_SLOT + cue
	var anim: SpriteAnim = _status_anims[cue]
	if left <= 0.0 or anim == null or (cue == SLOW_CUE and elapsed >= anim.total):
		_status_pool.hide(slot)
		return
	_status_pool.ensure(slot + 1)
	# tier C: canonical pos3 at body centre (Slow), pos2 at body top (Poison, Threaten, Stun); WZ origins supply spacing.
	var anchor := Vector2(0.0, box.get_center().y if cue == SLOW_CUE else box.position.y)
	_status_pool.show(slot, anim.frames[anim.index_at(elapsed, cue != SLOW_CUE)], (pos + anchor).round(), flip, alpha)


func _hide_statuses(i: int) -> void:
	_status_pool.hide(i * CUES_PER_SLOT + SLOW_CUE)
	_status_pool.hide(i * CUES_PER_SLOT + POISON_CUE)
	_status_pool.hide(i * CUES_PER_SLOT + THREATEN_CUE)
	_status_pool.hide(i * CUES_PER_SLOT + STUN_CUE)


## The animation a mob shows in a state (cached per id; null when the mob has none).
func anim_for(mob_id: int, state: int) -> SpriteAnim:
	var per: Variant = _by_id.get(mob_id)
	if per == null:
		per = _load_mob(mob_id)
		_by_id[mob_id] = per
	var arr: Array = per
	return arr[state] if state >= 0 and state < arr.size() else null


## Number of slots currently drawn.
func visible_count() -> int:
	return _pool.shown_count() if _pool != null else 0


## Hides everything.
func clear() -> void:
	if _pool != null:
		_pool.hide_from(0)
		_status_pool.hide_from(0)


func _load_mob(mob_id: int) -> Array:
	var out: Array = []
	out.resize(FREE)
	var lib := _lib()
	if lib == null:
		return out
	var path := lib.mob_anim_img_path(mob_id)
	if not lib.has_img(path):
		missing.append(mob_id)
		return out
	for st in range(STAND, FREE):
		for stance: String in STANCES[st]:
			var a := lib.find_anim(path + "/" + stance)
			if a != null:
				out[st] = a
				break
	return out


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())
		_status_pool = SpritePool.new(get_canvas_item())


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
