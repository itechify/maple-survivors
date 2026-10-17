class_name EnchantFx
extends CanvasLayer
## The v83 scroll result effect (#110): `Effect.wz/BasicEff.img/Enchant/Success` on a successful scroll,
## `Enchant/Failure` on a failure or a destroyed item, over the character. It lives in a screen-space layer above the
## in-run windows and is not frozen with the world (a round is held while the Equip and Item windows are open, and a
## world-space effect would sit on its first frame). The sounds are `Sound.wz/Game.img/EnchantSuccess|EnchantFailure`;
## the host plays them.
##
##   var fx := EnchantFx.new()
##   add_child(fx)
##   fx.play("success", avatar.get_global_transform_with_canvas().origin)   # RunWorld.scroll_used.result

## One layer above RunScene.UI_LAYER (the in-run windows).
const LAYER := 12
const SUCCESS_ANIM := "Effect.wz/BasicEff.img/Enchant/Success"
const FAILURE_ANIM := "Effect.wz/BasicEff.img/Enchant/Failure"
const SUCCESS_SOUND := "Sound.wz/Game.img/EnchantSuccess"
const FAILURE_SOUND := "Sound.wz/Game.img/EnchantFailure"

var renderer: FxRenderer


func _init() -> void:
	name = "EnchantFx"
	layer = LAYER
	renderer = FxRenderer.new()
	renderer.name = "Fx"
	add_child(renderer)


## The animation path of a `scroll_used` result (anything but "success" shows the failure art).
static func anim_path(result: String) -> String:
	return SUCCESS_ANIM if result == "success" else FAILURE_ANIM


## The sound path of a `scroll_used` result.
static func sound_path(result: String) -> String:
	return SUCCESS_SOUND if result == "success" else FAILURE_SOUND


## Plays the result's animation anchored at screen point `screen_pos` (the character's feet); the pooled slot id, or -1
## when the animation is missing.
func play(result: String, screen_pos: Vector2) -> int:
	return renderer.play(anim_path(result), screen_pos.round())
