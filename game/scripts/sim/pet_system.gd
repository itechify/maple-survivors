class_name PetSystem
extends RefCounted
## The pet out in a round (spec #34, ADR 0003, ticket #119): where it is, what it does and what it can do. Pure sim:
## no nodes, input, time or files, and no random numbers, so a round is the same for the same seed, account and pet.
##
## Movement uses the player's own physics (a second PlayerMotion on the same footholds and Physics.img values) driven by
## a small follow controller that presses the keys a player would: it walks toward the player, hops up onto a platform
## the player stands on when it is within a jump, drops down through the floor after the player, and jumps when it is
## stuck against a wall. It does not use ropes: while the player climbs one it hangs on the rope beside them. It
## teleports to the player when farther than `teleport_distance`, or when it stayed farther than `lost_distance` for
## `lost_seconds` (stuck behind a gap or a platform too high to reach).
##
## Abilities (`abilities`, from the account's owned pet upgrades; the base pet always collects every drop kind in
## `pickup_radius` of itself, as Item Pouch and Meso Magnet do):
##   auto_hp / auto_mp (1812002/1812003)  drink the character's potion below the ALERT level, once per `potion_delay`
##   wing_boots (1812004)  run to the nearest resting drop within `leash` px of the player, then come back
##   binocular (1812005)   `pickup_radius` x `binocular_mult`
##   vac (9990000, survivor-only)  every drop on the map flies to the pet (PickupSystem does the flying)
## All numbers are tier C survivor data (`cash_items.json` "pet"), listed in docs/GAME_DESIGN.md.

const UPGRADE_AUTO_HP := 1812002
const UPGRADE_AUTO_MP := 1812003
const UPGRADE_WING_BOOTS := 1812004
const UPGRADE_BINOCULAR := 1812005
const UPGRADE_VAC := 9990000
## Ability name -> the owned pet upgrade that grants it.
const ABILITY_ITEMS := {"auto_hp": UPGRADE_AUTO_HP, "auto_mp": UPGRADE_AUTO_MP, "wing_boots": UPGRADE_WING_BOOTS,
	"binocular": UPGRADE_BINOCULAR, "vac": UPGRADE_VAC}

const TUNING_DEFAULTS := {
	"pickup_radius": 60.0,  # tier C: the base pet picks up drops this close to its centre
	"center_up": 15.0,  # tier C: the pet's centre is this far above its feet
	"binocular_mult": 2.0,  # tier C: Binocular roughly doubles the pickup radius
	"follow_gap": 40.0,  # tier C: stands still this close (px) to the player
	"beside_offset": 30.0,  # tier C: a pet brought out stands this far (px) behind the player, not on top of it
	"follow_speed_mult": 1.1,  # tier C: walks a little faster than the player so it catches up
	"teleport_distance": 600.0,  # tier C: farther than this from the player -> teleports at once
	"lost_distance": 280.0,  # tier C: farther than this for lost_seconds -> teleports
	"lost_seconds": 3.0,  # tier C
	"leash": 220.0,  # tier C: Wing Boots fetch drops at most this far (px) from the player
	"fetch_dy": 80.0,  # tier C: ... and at most this far above or below the player (the pet jumps ~77 px)
	"fetch_gap": 6.0,  # tier C: how close the pet walks to a drop it fetches
	"fetch_speed_mult": 1.5,  # tier C: Wing Boots run
	"fetch_give_up": 2.5,  # tier C: seconds on one fetch before the pet gives up on it and follows again
	"fetch_pause": 2.0,  # tier C: seconds without fetching after giving up
	"potion_delay": 1.0,  # tier C: minimum seconds between the pet's drinks of one kind
	"jump_min_rise": 20.0,  # tier C: hops up when the player's feet are at least this far above its own
	"jump_max_rise": 70.0,  # tier C: ... and at most this far (the jump apex is 77 px)
	"jump_reach_dx": 80.0,  # tier C: ... and the player is at most this far sideways
	"down_min_drop": 20.0,  # tier C: drops through the floor when the player is this far below
	"down_dx": 60.0,  # tier C: ... and at most this far sideways
	"stuck_seconds": 0.3,  # tier C: jumps after pushing against a wall this long
}

## Pet species item id (5000000...).
var species := 0
## {auto_hp, auto_mp, wing_boots, binocular, vac}: bool.
var abilities := {"auto_hp": false, "auto_mp": false, "wing_boots": false, "binocular": false, "vac": false}
var tuning: Dictionary
## The pet's body, a PlayerMotion on the round's footholds (read pos, facing, vel; never written by outsiders).
var motion: PlayerMotion
## "stand", "move", "jump" or "hang" (the animation to draw).
var action := "stand"
## True while the pet is running to a drop (Wing Boots).
var fetching := false
## Drinks so far, by kind; counted apart from the player's.
var drinks := {"hp": 0, "mp": 0}
## Drops it picked up so far (by the pet, incl. VAC).
var pickups := 0

var _apart_t := 0.0
var _stuck_t := 0.0
var _fetch_t := 0.0
var _fetch_slot := -1
var _fetch_pause_t := 0.0
var _moved := 0.0
var _drink_cd := {"hp": 0.0, "mp": 0.0}
var _hanging := false


func _init(p_species: int, p_abilities: Dictionary, p_tuning: Dictionary, constants: PhysicsConstants) -> void:
	species = p_species
	for key: String in abilities:
		abilities[key] = bool(p_abilities.get(key, false))
	tuning = TUNING_DEFAULTS.duplicate()
	for key: String in p_tuning:
		if tuning.has(key):
			tuning[key] = float(p_tuning[key])
	motion = PlayerMotion.new(constants)


## The abilities an account's owned items give: {ability: bool}. VAC needs Wing Boots and Binocular, like the shop.
static func abilities_from(owned: Array) -> Dictionary:
	var out := {}
	for ability: String in ABILITY_ITEMS:
		out[ability] = _owns(owned, int(ABILITY_ITEMS[ability]))
	return out


## Stands the pet at `p` (snaps onto a floor at most a pixel below, else it falls) and forgets what it was doing.
func place(p: Vector2, fhm: FootholdMap) -> void:
	motion.place(p, fhm)
	_apart_t = 0.0
	_stuck_t = 0.0
	_fetch_t = 0.0
	_fetch_slot = -1
	fetching = false
	_hanging = false
	_moved = 1.0
	action = "stand"


## Brings the pet out next to the player: `beside_offset` px behind the way the player faces (else in front) on the same
## flat floor, so it is not hidden behind or over the avatar; with no such floor it stands on the player. It faces the
## player's way. Used when it is first brought out (teleports and tests use place()).
func place_beside(player: PlayerMotion, fhm: FootholdMap) -> void:
	var offset := float(tuning.beside_offset)
	for side: int in [-1, 1]:
		var x := player.pos.x + float(side * player.facing) * offset
		var f := fhm.find_below(x, player.pos.y - 2.0) if fhm != null else FootholdMap.NONE
		if f >= 0 and absf(fhm.y_at(f, x) - player.pos.y) <= 2.0:
			place(Vector2(x, player.pos.y), fhm)
			motion.facing = player.facing
			return
	place(player.pos, fhm)
	motion.facing = player.facing


## The pet's pickup centre.
func center() -> Vector2:
	return motion.pos - Vector2(0.0, float(tuning.center_up))


## The pickup radius: pickup_radius, times binocular_mult with Binocular.
func pickup_radius() -> float:
	var r := float(tuning.pickup_radius)
	return r * float(tuning.binocular_mult) if abilities.binocular else r


## What the renderer and telemetry read: species, pos (feet), facing (-1/1), action, fetching, abilities.
func view() -> Dictionary:
	return {"species": species, "pos": motion.pos, "facing": motion.facing, "action": action,
		"fetching": fetching, "abilities": abilities.duplicate()}


## Advances the pet by dt: teleport check, then follow (or fetch, or hang). Appends `pet_teleported` to events.
func step(dt: float, player: PlayerMotion, fhm: FootholdMap, bounds: Rect2, drops: PickupSystem, events: Array) -> void:
	_drink_cd.hp = maxf(0.0, float(_drink_cd.hp) - dt)
	_drink_cd.mp = maxf(0.0, float(_drink_cd.mp) - dt)
	_fetch_pause_t = maxf(0.0, _fetch_pause_t - dt)
	if player.ladder >= 0:
		_hang(player)
		return
	_hanging = false
	var gap := motion.pos.distance_to(player.pos)
	if gap > float(tuning.teleport_distance):
		_teleport(player, fhm, events)
	elif gap > float(tuning.lost_distance):
		_apart_t += dt
		if _apart_t >= float(tuning.lost_seconds):
			_teleport(player, fhm, events)
	else:
		_apart_t = 0.0
	var target := _target(dt, player, drops)
	var input := _input(dt, player, target)
	var mult := float(tuning.fetch_speed_mult) if fetching else float(tuning.follow_speed_mult)
	motion.speed_stat = roundi(maxf(100.0, float(player.speed_stat)) * mult)
	var before := motion.pos.x
	motion.step(dt, input, fhm, null, bounds)
	_moved = absf(motion.pos.x - before)
	action = _action_name()


## Whether the pet should drink `kind` now: it has the ability, ALERT is on and above the level, and the delay is over.
func drink_ready(kind: String, fraction: float, alert_level: float) -> bool:
	return bool(abilities["auto_" + kind]) and alert_level > 0.0 and fraction < alert_level \
		and float(_drink_cd[kind]) <= 0.0


## Records a drink: counts it and starts the delay.
func drank(kind: String) -> void:
	drinks[kind] = int(drinks[kind]) + 1
	_drink_cd[kind] = float(tuning.potion_delay)


func _hang(player: PlayerMotion) -> void:
	_hanging = true
	fetching = false
	_apart_t = 0.0
	motion.pos = player.pos
	motion.vel = Vector2.ZERO
	motion.fh = -1
	motion.state = PlayerMotion.ST_AIR
	motion.facing = player.facing
	_moved = 1.0
	action = "hang"


func _teleport(player: PlayerMotion, fhm: FootholdMap, events: Array) -> void:
	var from := motion.pos
	place(player.pos, fhm)
	motion.facing = player.facing
	events.append({"type": "pet_teleported", "from": from, "pos": motion.pos})


## Where the pet is heading: a resting drop within the leash (Wing Boots), else the player.
func _target(dt: float, player: PlayerMotion, drops: PickupSystem) -> Vector2:
	fetching = false
	if abilities.wing_boots and _fetch_pause_t <= 0.0:
		var slot := _nearest_drop(player.pos, drops)
		if slot >= 0:
			if slot != _fetch_slot:
				_fetch_slot = slot
				_fetch_t = 0.0
			_fetch_t += dt
			if _fetch_t > float(tuning.fetch_give_up):
				_fetch_pause_t = float(tuning.fetch_pause)
				_fetch_slot = -1
			else:
				fetching = true
				return Vector2(drops.x[slot], drops.y[slot])
		else:
			_fetch_slot = -1
	return player.pos


## The resting drop nearest the pet that lies within the leash of the player (-1 = none).
func _nearest_drop(anchor: Vector2, drops: PickupSystem) -> int:
	var leash := float(tuning.leash)
	var dy_max := float(tuning.fetch_dy)
	var best := -1
	var best_d := INF
	for i in drops.capacity():
		if drops.active[i] == 0 or drops.state[i] != PickupSystem.REST:
			continue
		var px := drops.x[i]
		var py := drops.y[i]
		if absf(py - anchor.y) > dy_max or absf(px - anchor.x) > leash:
			continue
		var d := absf(px - motion.pos.x)
		if d < best_d:
			best_d = d
			best = i
	return best


## The keys the pet presses this tick.
func _input(dt: float, player: PlayerMotion, target: Vector2) -> MoveInput:
	var input := MoveInput.new()
	var dx := target.x - motion.pos.x
	var stay := float(tuning.fetch_gap) if fetching else float(tuning.follow_gap)
	var grounded := motion.fh >= 0 and motion.state != PlayerMotion.ST_AIR
	var rise := motion.pos.y - target.y  # > 0: the target is above the pet's feet
	var target_grounded := fetching or player.fh >= 0
	if absf(dx) > stay:
		input.right = dx > 0.0
		input.left = dx < 0.0
	if not grounded:
		_stuck_t = 0.0
		return input
	if target_grounded and rise >= float(tuning.jump_min_rise) and rise <= float(tuning.jump_max_rise) \
			and absf(dx) <= float(tuning.jump_reach_dx):
		input.right = dx > 0.0
		input.left = dx < 0.0
		input.jump_pressed = true
		input.jump_held = true
	elif target_grounded and -rise >= float(tuning.down_min_drop) and absf(dx) <= float(tuning.down_dx):
		input.down = true
		input.jump_pressed = true
		input.jump_held = true
	elif input.dir() != 0 and _moved < 0.2:
		_stuck_t += dt
		if _stuck_t >= float(tuning.stuck_seconds):
			_stuck_t = 0.0
			input.jump_pressed = true
			input.jump_held = true
	else:
		_stuck_t = 0.0
	return input


func _action_name() -> String:
	match motion.state:
		PlayerMotion.ST_AIR:
			return "jump"
		PlayerMotion.ST_WALK:
			return "move"
	return "stand"


static func _owns(owned: Array, id: int) -> bool:
	for have: Variant in owned:
		if int(have) == id:
			return true
	return false
