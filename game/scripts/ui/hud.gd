class_name Hud
extends CanvasLayer
## Hosts the independently updated HUD widgets (all HudWidget) and lays out the quickslot, buff-row and boss-bar space,
## plus the status bar's Menu button (`menu_button`).

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
var font: SystemFont
var bold_font: SystemFont
var status := HudStatusBar.new()
var counters := HudCounters.new()
var skills := HudSkills.new()
var system_messages := HudMessages.new()
var potion_slot := HudPotionQuickslot.new()
var buff_row := HudBuffRow.new()
var boss_bar := HudBossBar.new()
## The status bar's Menu button (StatusBar.img/BtMenu: normal / mouseOver / pressed art). The only HUD control that
## takes the mouse; RunScene connects `pressed` to its Menu popup. PROCESS_MODE_ALWAYS: it keeps working while
## RunScene freezes the HUD (pause, open windows).
var menu_button := WzButton.new(HudWidget.SB + "BtMenu")

## tier C (ours): BtMenu's top-left in the 800 px status bar, at the right end past the potion quickslot's labels.
const MENU_POS := Vector2(744, 20)

func _ready() -> void:
	layer = 10
	font = make_font()
	bold_font = make_font(700)
	for w: HudWidget in [status, counters, skills, system_messages]:
		w.library = library
		add_child(w)
	status.name = "StatusBar"
	counters.name = "Counters"
	skills.name = "Skills"
	system_messages.name = "Messages"
	for w: HudWidget in [potion_slot, buff_row, boss_bar]:
		w.library = library
		add_child(w)
	potion_slot.name = "PotionQuickslot"
	buff_row.name = "BuffRow"
	boss_bar.name = "BossBar"
	menu_button.name = "MenuButton"
	menu_button.fallback_size = Vector2(54, 34)
	menu_button.label = "" if menu_button.has_art() else "MENU"
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_button)
	get_viewport().size_changed.connect(_layout_slots)
	_layout_slots()

## Compatibility entry point for callers displaying a HUD without a run scene.
func update(ps: Dictionary, info: Dictionary) -> void:
	store_state(ps, info)
	for w: HudWidget in [status, counters, skills, system_messages, potion_slot, buff_row, boss_bar]:
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

## Returns currently visible message lines.
func messages() -> Array[Dictionary]:
	return system_messages.messages()


## Whether a ready skill is waiting for MP in the current HUD snapshot.
func low_mp_visible() -> bool:
	return system_messages.low_mp_visible()

## Advances message lifetimes for tests and non-processing hosts.
func advance_messages(dt: float) -> void:
	system_messages.advance_messages(dt)

func _layout_slots() -> void:
	var view := get_viewport().get_visible_rect().size
	# tier C: reserved layout for the difficulty-overhaul HUD.
	potion_slot.position = bar_origin(view) + Vector2(571, 8)
	potion_slot.size = Vector2(221, 59)
	menu_button.position = bar_origin(view) + MENU_POS
	buff_row.position = Vector2(view.x - 224, 42)
	buff_row.size = Vector2(212, 44)
	boss_bar.position = Vector2(floorf((view.x - 300) * 0.5), 42)
	boss_bar.size = Vector2(HudBossBar.BAR_WIDTH, HudBossBar.ROW_HEIGHT)

## Creates the common HUD and window system font.
static func make_font(weight: int = 400) -> SystemFont:
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
