class_name PlayerSummonRenderer
extends Node2D
## One batched RenderingServer pool for every player summon; animation clocks come from fixed-tick sim state.
var library: AssetLibrary
var _pool: SpritePool
var _anims := {}

## Presents all live and dying allies without creating per-entity nodes.
func update_from(summons: PlayerSummons) -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())
	_pool.ensure(summons.active.size())
	for i in summons.active.size():
		if summons.active[i] == 0 or summons.definitions[i].has("echo"): # a clone is EchoCloneRenderer's
			_pool.hide(i)
			continue
		var path := String(summons.definitions[i].path) + "/" + summons.action[i]
		if not _anims.has(path):
			_anims[path] = library.anim(path)
		var anim: SpriteAnim = _anims[path]
		if anim == null or anim.is_empty():
			_pool.hide(i)
			continue
		var loops := summons.action[i] == "stand" or summons.action[i] == String(summons.definitions[i].move)
		var age := summons.age[i]
		_pool.show(i, anim.frame_at(age, loops), Vector2(roundf(summons.x[i]), roundf(summons.y[i])),
			summons.facing[i] > 0, anim.alpha_at(age, loops))
	_pool.hide_from(summons.active.size())
