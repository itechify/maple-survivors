class_name InventoryWiring
extends RefCounted
## What a round (RunScene) and the Free Market hub share when they host the Equip and Item windows over a RunWorld
## (spec #33): the two window factories registered on the WindowStack, the Enchant scroll effect, and the signal wiring
## of every inventory window (shops too) to the host. The host supplies what differs: `on_action(action)` after the
## character changed, `on_notice(text)` for a refusal message and `play_sound(path)`.
##
##   var wiring := InventoryWiring.install(stack, world, self, library, _on_item_action, _push_notice, _sound)
##   stack.open(wiring.wire(ShopWindow.new(world, npc_id)))
##   wiring.scroll_used(String(e.result), avatar.get_global_transform_with_canvas().origin)

## The scroll result effect, a child of the host.
var enchant: EnchantFx
var _on_action: Callable
var _on_notice: Callable
var _play_sound: Callable


## Registers "equip" and "item" on `stack` over `world` and adds the EnchantFx to `host`.
static func install(stack: WindowStack, world: RunWorld, host: Node, library: AssetLibrary, on_action: Callable,
		on_notice: Callable, play_sound: Callable) -> InventoryWiring:
	var wiring := InventoryWiring.new()
	wiring._on_action = on_action
	wiring._on_notice = on_notice
	wiring._play_sound = play_sound
	wiring.enchant = EnchantFx.new()
	wiring.enchant.renderer.library = library
	host.add_child(wiring.enchant)
	stack.register("equip", func() -> UiWindow: return wiring.wire(EquipWindow.new(world)))
	stack.register("item", func() -> UiWindow: return wiring.wire(ItemWindow.new(world)))
	return wiring


## Connects an inventory window's item_action and notice signals to the host; returns it.
func wire(w: InventoryWindow) -> UiWindow:
	w.item_action.connect(_on_action)
	w.notice.connect(_on_notice)
	return w


## A scroll was read: the Enchant effect over screen point `screen_pos` (the character's feet) and its sound.
func scroll_used(result: String, screen_pos: Vector2) -> void:
	enchant.play(result, screen_pos)
	_play_sound.call(EnchantFx.sound_path(result))
