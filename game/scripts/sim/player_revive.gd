class_name PlayerRevive
extends HitHook
## Second life (spec #372 BS3, ruling D6, docs/GAME_DESIGN.md 7.81): a lethal hit does not kill the character when it owns
## a ready reaction skill with a `revive` block. Owned by RunWorld as `revive` and registered as a HitHook at HIT_ORDER.
## The skill's recharge is its ordinary cooldown (runner.cooldowns), so the HUD slot, Mastery, the Booster passive and
## every cooldown modifier apply with no timer here; this class keeps only the guard timer. No RNG, no Nodes.
## A hit from a source marked `unrevivable` (the flow driver's diagnostic lethal hit) kills regardless.

## Where the hook sits among take_hit's hooks (ascending order runs first). tier C: after any damage-side hook.
const HIT_ORDER := 100
## Defaults for a `revive` block that omits a field (the Resurrection definition spells them out, BS8).
## tier C: ours (spec #372 D6): back at half max HP.
const DEFAULT_HP := 0.5
## tier C: ours (spec #372 D6): two seconds in which no hit lands, boss skill attacks and balls included.
const DEFAULT_GUARD := 2.0
## tier C: ours (spec #372 D6): px the monsters in the skill's box are shoved away from the character.
const DEFAULT_PUSH := 140.0
## The recharge counts as run out at or below this many seconds, like SkillRunner.cast_ready's ready test.
const READY_EPS := 1e-6

## Seconds of guard left.
var guard_t := 0.0


## True while the guard runs.
func guarding() -> bool:
	return guard_t > READY_EPS


## Counts the guard down.
func step(dt: float) -> void:
	if guard_t > 0.0:
		guard_t = maxf(0.0, guard_t - dt)


## HitHook entry: revives when it can.
func intercept_lethal(world: RunWorld, source: Dictionary) -> bool:
	return try_revive(world, source)


## The owned, ready reaction skill with a `revive` block that would catch a lethal hit now ("" when none): learned order,
## so the first one owned. Needs the skill owned, its recharge run out and the character alive.
func ready_skill(world: RunWorld) -> String:
	for key: String in world.loadout.order:
		if world.book.def(key).has("revive") and world.runner.stats_of(world, key).cast_rule == "reaction" \
				and float(world.runner.cooldowns.get(key, 0.0)) <= READY_EPS:
			return key
	return ""


## Revives the character from a lethal hit of `source` when a skill is ready and the source allows it: sets HP, starts the
## guard and the recharge, shoves the monsters in the box and records it. False, with nothing changed, otherwise.
func try_revive(world: RunWorld, source: Dictionary) -> bool:
	if bool(source.get("unrevivable", false)) or world.state == RunWorld.DEAD:
		return false
	var key := ready_skill(world)
	if key == "":
		return false
	var st := world.runner.stats_of(world, key)
	var plan := plan_of(world, st)
	var hp := world.grant_second_life(float(plan.hp))
	guard_t = float(plan.guard)
	var recharge := SkillRunner.restart_cooldown(st)
	world.runner.cooldowns[key] = recharge
	world.runner.cooldown_totals[key] = recharge
	var pushed := _shove(world, st, float(plan.push))
	world.revives.append({"t": world.time, "level": int(world.player_state.level), "rank": int(st.rank),
		"source_kind": String(source.get("source_kind", "other")), "hp": int(hp)})
	world.emit("player_revived", {"skill": key, "hp": int(hp), "max_hp": int(world.player_state.max_hp),
		"pos": world.player.pos, "guard": guard_t, "recharge": recharge, "pushed": pushed})
	return true


## The resolved plan for the resolved stats `st` of a reaction skill: {hp (the HP to return with, whole), guard (s),
## push (px)}. `st.revive` already carries the modifiers (Loadout.stats).
func plan_of(world: RunWorld, st: Dictionary) -> Dictionary:
	var max_hp := int(world.player_state.max_hp)
	var revive: Dictionary = st.revive
	return {"hp": clampi(ceili(float(max_hp) * float(revive.hp)), 1, max_hp),
		"guard": maxf(0.0, float(revive.guard)), "push": maxf(0.0, float(revive.push))}


## Shoves every non-boss, non-steady monster meeting the skill's box (scaled by `area`) `distance` px away from the
## character, in slot order, with no damage and no status. Returns how many were shoved.
func _shove(world: RunWorld, st: Dictionary, distance: float) -> int:
	if distance <= 0.0 or not bool(st.has_box):
		return 0
	var slots := world.skill_box_targets(st.box)
	slots.sort()
	var pushed := 0
	for m: int in slots:
		if world.swarm.mob_kind(m).boss or world.swarm.steady[m] != 0 or world.swarm.fh[m] < 0:
			continue
		world.swarm.knockback(m, world.player.pos.x, distance, world.fhm, world.bounds)
		pushed += 1
	return pushed
