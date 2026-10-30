class_name Hud
extends CanvasLayer
## Hosts the independently updated HUD widgets (all HudWidget) and lays out the quick slot, buff-row and boss-bar space,
## plus the status bar's Menu button (`menu_button`) and the quick slot's collapse button (`quick_slot_button`).

const BAR_W := HudWidget.BAR_W
const BAR_H := HudWidget.BAR_H
const FONT_SIZE := HudWidget.FONT_SIZE
const SYSTEM_YELLOW := HudWidget.SYSTEM_YELLOW
const MSG_LIFE := HudWidget.MSG_LIFE
const MSG_FADE := HudWidget.MSG_FADE
const MSG_MAX := HudWidget.MSG_MAX

var library: AssetLibrary
var player_state: Dictionary = {}
var run_info: Dictionary = {}
var font: Font
var bold_font: Font
var status := HudStatusBar.new()
var counters := HudCounters.new()
var skills := HudSkills.new()
var meter := HudMeter.new()
var system_messages := HudMessages.new()
var quick_slot := HudQuickSlot.new()
var buff_row := HudBuffRow.new()
var boss_bar := HudBossBar.new()
## The status bar's Menu button (StatusBar.img/BtMenu: normal / mouseOver / pressed art). The only HUD control that
## takes the mouse; RunScene connects `pressed` to its Menu popup. PROCESS_MODE_ALWAYS: it keeps working while
## RunScene freezes the HUD (pause, open windows).
var menu_button := WzButton.new(HudWidget.SB + "BtMenu")
## The quick slot's collapse button (StatusBar.img/QuickSlotD, the down arrow, while the panel is shown; QuickSlot, the up
## arrow, while it is folded away). Like `menu_button` it takes the mouse and works while the HUD is frozen; RunScene
## connects `pressed` to the setting that remembers the state.
var quick_slot_button := WzButton.new(QUICK_SLOT_SHOWN_ART)

## tier C (ours): BtMenu's top-left in the 800 px status bar, at the right end under the quick slot button (a third-party v83-era
## client keeps the Menu button on the lower half of the bar, y 36).
const MENU_POS := Vector2(744, 36)
## tier C: the quick slot panel's top-left relative to the status bar's: flush with the bar's right end and standing
## 76 px above its top edge (the 80 px panel overlaps the bar by 4 px). Taken from a third-party v83-era client that lays
## it out at (875, 622) on a 1024 x 768 screen with the bar at y 698 (a fan renderer, not the official client: tier C
## here), right-aligned to 800 px.
const QUICK_SLOT_POS := Vector2(649, -76)
## tier C: the collapse button's top-left in the bar (the same client puts it at x 765, y 8 of the bar).
const QUICK_SLOT_BUTTON_POS := Vector2(765, 8)
const QUICK_SLOT_SHOWN_ART := HudWidget.SB + "QuickSlotD"
const QUICK_SLOT_FOLDED_ART := HudWidget.SB + "QuickSlot"

func _ready() -> void:
	layer = 10
	font = make_font()
	bold_font = make_font(700)
	for w: HudWidget in [status, counters, skills, meter, system_messages]:
		w.library = library
		add_child(w)
	status.name = "StatusBar"
	counters.name = "Counters"
	skills.name = "Skills"
	system_messages.name = "Messages"
	for w: HudWidget in [quick_slot, buff_row, boss_bar]:
		w.library = library
		add_child(w)
	quick_slot.name = "QuickSlot"
	buff_row.name = "BuffRow"
	boss_bar.name = "BossBar"
	menu_button.name = "MenuButton"
	menu_button.fallback_size = Vector2(54, 34)
	menu_button.label = "" if menu_button.has_art() else "MENU"
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_button)
	quick_slot_button.name = "QuickSlotButton"
	quick_slot_button.fallback_size = Vector2(28, 20)
	quick_slot_button.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(quick_slot_button)
	get_viewport().size_changed.connect(_layout_slots)
	_layout_slots()

## Folds the quick slot panel away or shows it, with the collapse button's arrow: the widget and button state follow
## `collapsed` (the run scene passes GameSettings.quick_slot_collapsed, the one stored value).
func apply_quick_slot_collapsed(collapsed: bool) -> void:
	quick_slot.visible = not collapsed
	quick_slot_button.base_path = QUICK_SLOT_FOLDED_ART if collapsed else QUICK_SLOT_SHOWN_ART


## Compatibility entry point for callers displaying a HUD without a run scene.
func update(ps: Dictionary, info: Dictionary) -> void:
	store_state(ps, info)
	for w: HudWidget in [status, counters, skills, meter, system_messages, quick_slot, buff_row, boss_bar]:
		w.update(ps, info)

## Stores the public snapshot; RunScene feeds the widgets individually.
func store_state(ps: Dictionary, info: Dictionary) -> void:
	player_state = ps
	run_info = info

## Adds a transient system message.
func push_message(text: String, color: Color = SYSTEM_YELLOW) -> void:
	system_messages.push_message(text, color)


## Shows an encounter notice without letting EXP messages evict it.
func push_notice(key: String, text: String, life: float = MSG_LIFE) -> void:
	system_messages.push_notice(key, text, life)

## Shows a collected EXP total.
func show_exp(n: int) -> void:
	system_messages.show_exp(n)

## Shows the collected-mesos notice.
func show_mesos(n: int) -> void:
	system_messages.show_mesos(n)

## Shows the equipment pickup notice.
func show_item_gain(item_name: String) -> void:
	system_messages.show_item_gain(item_name)

## Shows the "Equipped <item>" notice of an auto-worn pickup.
func show_equipped(item_name: String) -> void:
	system_messages.show_equipped(item_name)

## Shows the "inventory full" notice (an equipment drop that cannot be picked up).
func show_inventory_full() -> void:
	system_messages.show_inventory_full()

## Returns currently visible message lines.
func messages() -> Array[Dictionary]:
	return system_messages.messages()


## Advances message lifetimes for tests and non-processing hosts.
func advance_messages(dt: float) -> void:
	system_messages.advance_messages(dt)

func _layout_slots() -> void:
	var view := get_viewport().get_visible_rect().size
	quick_slot.position = bar_origin(view) + QUICK_SLOT_POS
	quick_slot.size = HudQuickSlot.PANEL_SIZE
	quick_slot_button.position = bar_origin(view) + QUICK_SLOT_BUTTON_POS
	menu_button.position = bar_origin(view) + MENU_POS
	buff_row.position = Vector2(view.x - 224, 42)
	buff_row.size = Vector2(212, 44)
	boss_bar.position = Vector2(floorf((view.x - 300) * 0.5), 42)
	boss_bar.size = Vector2(HudBossBar.BAR_WIDTH, HudBossBar.ROW_HEIGHT)

## Creates the common HUD and window system font.
static func make_font(weight: int = 400) -> Font:
	return HudWidget.make_font(weight)


## Top-left of the 800 px status bar in a view of `view` size.

static func bar_origin(view: Vector2) -> Vector2:
	return HudWidget.bar_origin(view)


## Width in px of the filled part of a gauge (0 when max <= 0).

static func fill_width(cur: float, max_v: float, full: float) -> float:
	return HudWidget.fill_width(cur, max_v, full)


## "MM:SS" for a number of seconds.
static func format_time(seconds: float) -> String:
	return HudWidget.format_time(seconds)

## Message alpha at the given age.
static func message_alpha(age: float) -> float:
	return HudWidget.message_alpha(age)
