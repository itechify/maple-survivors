class_name LevelUpWindow
extends MapleWindow
## The level-up upgrade choice (docs/ARCHITECTURE.md 4.4.2 `choice_pending`, GAME_DESIGN section 8).
##
## Art: the v83 skill-up notice UIWindow.img/SkillUp/backgrd ("You've gained a Level!" with the slime, snail and
## orange mushroom) is the window; its uniform rows 169-179 are repeated to grow the panel for the choices. The level
## goes into the notice's level box (Basic.img/LevelNo digits). The baked-in skill-raising sentence is always
## replaced with the panel's own blank fill, so the notice reads "LEVEL n". Each choice is a skill-window row
## (UIWindow.img/Skill/skill0, skill1 when focused, widened to the panel) with the card icon in the slot
## (UIWindow.img/IconBase/0 when the
## card has no icon or the icon is missing), the name, the rank (rank_text: "NEW", "Lv. 1 → 2", the skill's canonical
## level change "Skill Lv. 2 → 3" for skill_rank cards, "MAX" at the last rank), the key (Basic.img/ItemNo digit) and
## the description and canonical before/after values below.
##
## Input: 1/2/3 (choice_1..3) pick a card; Up/Down move the focus, Enter picks it; the mouse highlights and clicks.
## `card_chosen` is emitted at once when a card is picked (then the window fades out); a new open() during the fade
## (queued level-ups) restarts the window with the new cards.
##
##   win.open(skill_text.dress(cards, loadout), level)
##                            # cards as in the choice_pending event: {id, kind, name, desc, icon, rank,
##                            # max_rank, skill, skill_name, skill_level, skill_level_next, skill_changes,
##                            # skill_mod_changes, skill_effect_stat, tier, magnitude, rank_before, skill_level_max},
##                            # dressed with SkillText (desc, plus `detail`: a learn card's level line, never shortened).
## `desc` and `detail` may hold v83 markup (#c...# is drawn orange, "\n" breaks the line).

## Label and unit of a rank card's canonical `x` by the skill's buff effect stat (skills.json `buff.stat`, the card's
## `skill_effect_stat`): a healing buff's x is HP per pulse; any other stat shows as a plain effect value.
const X_LABELS := {"hp": ["HP / pulse", ""], "weapon_damage_reduction": ["Weapon reduction", "%"], "slow": ["Move speed", "%"],
	"acc": ["Accuracy", ""],
	"threatened": ["Monster weapon ATT / DEF", ""]}
const X_LABEL_DEFAULT := ["Effect", ""]
## Label of each previewed field (UpgradePool.PREVIEW_FIELDS plus survivor passive stats); `x` comes from X_LABELS.
const FIELD_LABELS := {"mad": "Magic ATT", "mastery": "Mastery", "fixdamage": "Damage",
	"time": "Duration", "pdd": "Weapon DEF", "mdd": "Magic DEF", "acc": "Accuracy", "eva": "Avoid",
	"mobCount": "Targets", "cooltime": "Cooldown", "speed": "Speed", "range": "Range", "hp": "Recovery power",
	"damage": "Damage", "hpCon": "HP cost", "prop": "Success rate",
	"knockback_chance": "Knock-back chance", "blast_targets": "Blast targets", "pierce_falloff": "Pierce fall-off",
	UpgradePool.PASSIVE_MAX_HP: "Max HP per level-up", UpgradePool.PASSIVE_REGEN_HP: "HP per pulse"}
## Fields shown as a percent (canonical `damage` is the skill's percent of the weapon damage).
const PERCENT_FIELDS := ["mastery", "hp", "damage", "prop", "knockback_chance", "pierce_falloff"]
## Label and unit of each mod-card value (UpgradePool skill_mod_changes keys: a `count` card is SkillRunner.SHOTS or
## TARGETS), in display order. tier C: our wording.
const MOD_LABELS := {SkillRunner.SHOTS: ["Shots", ""], SkillRunner.TARGETS: ["Targets", ""], "attack_count": ["Hits", ""], "pierce": ["Pierce", ""],
	"blast_targets": ["Blast targets", ""], "pierce_falloff": ["Pierce fall-off", "%"],
	"damage": ["Damage", "%"], "cooldown": ["Cooldown", " s"], "area": ["Reach", "%"], "range": ["Range", " px"],
	"heal_power": ["Recovery", "%"], "heal_threshold": ["Heals below", "% HP"],
	"speed": ["Shot speed", ""], "crit": ["Critical rate", "%"], "revive_hp": ["Revive HP", "%"], "revive_guard": ["Guard", " s"], "form_time": ["Form duration", " s"], "form_power": ["Form power", "%"]}

## Emitted with the picked card's id.
signal card_chosen(card_id: String)

const ART := "UI.wz/UIWindow.img/SkillUp/backgrd"
const ROW := "UI.wz/UIWindow.img/Skill/skill0"
const ROW_FOCUS := "UI.wz/UIWindow.img/Skill/skill1"
const LEVEL_DIGITS := "UI.wz/Basic.img/LevelNo/"
const KEY_DIGITS := "UI.wz/Basic.img/ItemNo/"
## tier C: implementation-selected v83 Monster Card cue for Unique / Legendary offers; the owner reserved
## EnchantSuccess for future scrolling.
const SND_HIGH_TIER := "Sound.wz/Game.img/mCardGet"
## tier C: readable Potential-ladder accents on the v83 panel; the explicit label also identifies every tier.
const TIER_STYLES := {
	"normal": ["Normal", Color.WHITE],
	"rare": ["Rare", Color8(119, 187, 255)],
	"epic": ["Epic", Color8(204, 153, 255)],
	"unique": ["Unique", Color8(255, 204, 68)],
	"legendary": ["Legendary", Color8(119, 221, 136)],
}
## tier C: a compact label band tinted with the tier colour and a 2 px tier frame retain the original skill row and
## its focus art (owner: the 1 px frame was too faint for Rare on the blue panel).
const TIER_BAND := 16.0
const TIER_BACKGROUND := Color8(23, 52, 79)
const TIER_TINT := 0.3
const TIER_FRAME := 2.0
## SkillUp/backgrd geometry (measured from the v83 canvas, 215x201): rows above TOP_H are the notice, rows
## [MID_Y, MID_Y + MID_H) are uniform and repeat, the rest is the bottom edge.
const ART_SIZE := Vector2(215, 201)
const TOP_H := 169.0
const MID_Y := 169.0
const MID_H := 11.0
const BOTTOM_H := 21.0
## The notice's level box.
const LEVEL_BOX := Rect2(116, 108, 27, 17)
## The notice sentence (measured from the v83 canvas): per band of art rows [y0, y1), the x ranges [x0, x1) covered
## for every card - "BY REACHING " and ", YOU HAVE" around the level box, then the whole
## "RAISED YOUR [ ]" / "SKILL BY A LEVEL." lines. Column BLANK_X is plain panel fill in every one of those rows (the
## fill is a vertical gradient, so each covered row is painted with its own row's fill colour).
const SENTENCE_BANDS := [[105.0, 126.0, [Vector2(13, 82), Vector2(144, 202)]], [126.0, 164.0, [Vector2(13, 202)]]]
const BLANK_X := 14.0
## Choice rows inside the panel's inner fill (x 12..202). tier C: use the blanked notice sentence for compactness.
const ROWS_TOP := 140.0
## tier C: reward title plus instruction above the same canonical card rows.
const BONUS_ROWS_TOP := 64.0
const ROW_X := 12.0
const ROW_W := 191.0
const ROW_H := 35.0
## skill0: icon slot width (incl. its 1 px gap) and a uniform column of the name area.
const ROW_SLOT_W := 36.0
const ROW_MID_X := 60.0
const DESC_LINE := 13.0
## tier C: v83 skill descriptions run to four lines here (e.g. Nimble Feet with its orange cooldown line); the layout
## still shortens them to fit the view.
const DESC_MAX_LINES := 4
## tier C: compact separation and total vertical margin keep the 600px view's mascots and HUD clear.
const BLOCK_GAP := 4.0
const VIEW_MARGIN := 128.0

## The cards on offer.
var cards: Array = []
## The level shown in the notice.
var level := 0
## Boss rewards use the same card-choice interface without the gained-level notice.
var bonus := false
## Index of the focused card (-1 = none).
var focus := -1

## Per card: {"row": Rect2 (panel-local row art), "block": Rect2 (row + description, the mouse target),
## "desc", "changes": PackedStringArray}.
var _blocks: Array[Dictionary] = []


func _init() -> void:
	super._init()
	window_hotkeys = true
	name = "LevelUpWindow"
	panel_size = ART_SIZE


## Opens the window with the cards of a choice_pending event and the new level.
func open(p_cards: Array, p_level: int, p_bonus: bool = false) -> void:
	cards = p_cards.duplicate(true)
	level = p_level
	bonus = p_bonus
	focus = 0 if not cards.is_empty() else -1
	_build_layout()
	_show_window()
	for card: Dictionary in cards:
		if String(card.get("tier", "normal")) in ["unique", "legendary"]:
			UiArt.play_sound(SND_HIGH_TIER)
			break


## Picks card `i`: emits card_chosen(id) and closes. False when closed or out of range.
func choose(i: int) -> bool:
	if not _open or i < 0 or i >= cards.size():
		return false
	var id := String((cards[i] as Dictionary).get("id", ""))
	focus = i
	panel.queue_redraw()
	UiArt.play_sound(UiArt.SND_CLICK)
	_hide_window()
	card_chosen.emit(id)
	return true


## Moves the focus to card `i` (clamped; plays the hover sound when it changes).
func set_focus(i: int) -> void:
	if cards.is_empty():
		return
	i = clampi(i, 0, cards.size() - 1)
	if i != focus:
		focus = i
		UiArt.play_sound(UiArt.SND_OVER)
		panel.queue_redraw()


## The mouse target of card `i` in window coordinates (empty when out of range).
func card_rect(i: int) -> Rect2:
	if i < 0 or i >= _blocks.size():
		return Rect2()
	var r: Rect2 = _blocks[i].block
	return Rect2(r.position + panel.position, r.size)


## The offered canonical skill level (learn/rank) or consumed modifier steps; fillers have no rank text.
static func rank_text(card: Dictionary) -> String:
	var kind := String(card.get("kind", ""))
	if card.get("card_kind", "") == "mastery":
		return "Rank %d · Mastery" % int(card.get("skill_rank_max", 0))
	if card.get("card_kind", "") == "owned_active":
		return "Rank %d → %d" % [int(card.get("skill_rank_before", 0)), int(card.get("skill_rank_before", 0)) + 1]
	if card.get("card_kind", "") == "new_active":
		return "NEW  Rank 1"
	if kind == "filler":
		return ""
	var rank := int(card.get("rank", 1))
	var max_rank := int(card.get("max_rank", 0))
	var s := ""
	var lv := int(card.get("skill_level", 0))
	var lv_next := int(card.get("skill_level_next", 0))
	if kind == "skill_new" and lv_next > 0:
		var level_max := int(card.get("skill_level_max", 0))
		return "NEW  Skill Lv. %d" % lv_next + ("  MAX" if level_max > 0 and lv_next >= level_max else "")
	if kind == "skill_rank" and lv > 0 and lv_next > lv:
		s = "Skill Lv. %d → %d" % [lv, lv_next]
		rank = lv_next
	elif rank <= 1:
		return "NEW"
	else:
		s = "Lv. %d → %d" % [int(card.get("rank_before", rank - 1)), rank]
	if max_rank > 1 and rank >= max_rank:
		s += "  MAX"
	return s


## Values that change with the card: a rank card's canonical values at the offered rank (mastery is already a percent
## in card data), then a mod card's effective values (skill_mod_changes).
static func change_lines(card: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var mods: Dictionary = card.get("skill_mod_changes", {})
	for key: String in MOD_LABELS:
		if mods.has(key) and mods[key].before != mods[key].after:
			var unit: String = MOD_LABELS[key][1]
			var line := "%s: %s%s → %s%s" % [card.get("skill_mod_labels", {}).get(key, MOD_LABELS[key][0]), SkillText.number(float(mods[key].before)), unit,
				SkillText.number(float(mods[key].after)), unit]
			lines.append_array(MapleText.wrap_markup(line, ROW_W - 8.0, MapleText.SMALL))
	var changes: Dictionary = card.get("skill_changes", {})
	var x_label: Array = X_LABELS.get(String(card.get("skill_effect_stat", "")), X_LABEL_DEFAULT)
	for field: String in UpgradePool.PREVIEW_FIELDS + UpgradePool.PASSIVE_PREVIEW_KEYS + UpgradePool.MECHANIC_PREVIEW_KEYS:
		if not changes.has(field):
			continue
		var values: Dictionary = changes[field]
		if values.before == values.after:
			continue
		var suffix := " s" if field in ["time", "cooltime"] else ""
		if field == "range":
			suffix = " px"
		if field in PERCENT_FIELDS:
			suffix = "%"
		elif field == "x":
			suffix = x_label[1]
		var label := String(x_label[0]) if field == "x" else String(FIELD_LABELS[field])
		lines.append("%s: %d%s → %d%s" % [label, int(values.before), suffix, int(values.after), suffix])
	return lines


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	var d := MapleWindow.digit_of(event)
	if d >= 1 and d <= cards.size():
		choose(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		set_focus((focus + step + cards.size()) % maxi(1, cards.size()) if focus >= 0 else 0)
		return true
	if MapleWindow.is_confirm(event):
		choose(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	var hit := -1
	for i in _blocks.size():
		if (_blocks[i].block as Rect2).has_point(local):
			hit = i
			break
	if event is InputEventMouseMotion:
		if hit >= 0:
			set_focus(hit)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and hit >= 0:
			choose(hit)


func _build_layout() -> void:
	var minimum := BONUS_ROWS_TOP + BOTTOM_H if bonus else ART_SIZE.y
	var height := minimum
	var view_h := size.y if size.y > 0.0 else Vector2(GameSettings.BASE_VIEW).y
	# tier C: dense previews shorten prose before hiding any tier, magnitude or changed canonical value.
	for desc_limit in range(DESC_MAX_LINES, 0, -1):
		_blocks.clear()
		var y := BONUS_ROWS_TOP if bonus else ROWS_TOP
		for c: Variant in cards:
			var card: Dictionary = c if c is Dictionary else {}
			var desc := MapleText.wrap_markup(String(card.get("desc", "")), ROW_W - 8.0, MapleText.SMALL)
			if desc.size() > desc_limit:
				desc = desc.slice(0, desc_limit)
				# The shortened line loses its orange rather than cut a markup code in half.
				desc[desc_limit - 1] = MapleText.ellipsize(MapleText.plain(desc[desc_limit - 1]) + " ...",
					ROW_W - 8.0, MapleText.SMALL)
			# The level line of a learn card is never shortened, like the before -> after values.
			var changes := MapleText.wrap_markup(String(card.get("detail", "")), ROW_W - 8.0, MapleText.SMALL) \
				if String(card.get("detail", "")) != "" else PackedStringArray()
			changes.append_array(change_lines(card))
			var h := ROW_H + TIER_BAND + 3.0 + (desc.size() + changes.size()) * DESC_LINE
			_blocks.append({"row": Rect2(ROW_X, y, ROW_W, ROW_H), "block": Rect2(ROW_X, y, ROW_W, h),
				"desc": desc, "changes": changes})
			y += h + BLOCK_GAP
		height = maxf(minimum, y - BLOCK_GAP + 4.0 + BOTTOM_H - 8.0)
		if height <= view_h - VIEW_MARGIN:
			break
	panel_size = Vector2(ART_SIZE.x, ceilf(height))


func _draw_panel(ci: Control) -> void:
	if bonus:
		_draw_bonus_art(ci, UiArt.frame(ART))
	else:
		_draw_art_without_sentence(ci, UiArt.frame(ART))
		_draw_level(ci)
	if not cards.is_empty():
		MapleText.draw_centered(ci, 8, 128 if not bonus else 48, panel_size.x - 16,
			String(cards[0].get("slots", "")), MapleText.BLACK, MapleText.SMALL)
	var row0 := UiArt.frame(ROW)
	var row1 := UiArt.frame(ROW_FOCUS)
	for i in mini(cards.size(), _blocks.size()):
		_draw_card(ci, i, cards[i], row1 if i == focus else row0)


func _draw_bonus_art(ci: Control, f: SpriteFrame) -> void:
	if f != null:
		var bottom_y := MID_Y + MID_H
		var bottom_h := f.region.size.y - bottom_y
		var end := panel_size.y - bottom_h
		var y := 0.0
		while y < end:
			var h := minf(MID_H, end - y)
			UiArt.blit_part(ci, f, Rect2(0, MID_Y, f.region.size.x, h), Vector2(0, y))
			y += h
		UiArt.blit_part(ci, f, Rect2(0, bottom_y, f.region.size.x, bottom_h), Vector2(0, end))
	MapleText.draw_centered(ci, 0, 12, panel_size.x, "Boss Reward", MapleText.WHITE, MapleText.SIZE, true)
	MapleText.draw_centered(ci, 0, 30, panel_size.x, "Choose an upgrade", MapleText.WHITE, MapleText.SMALL)


## The window art like TiledFrame.draw_v_slices, with the notice sentence's words (SENTENCE_BANDS) replaced by the
## blank fill column of their own rows (the art is translucent, so the words are left out rather than painted over).
func _draw_art_without_sentence(ci: Control, f: SpriteFrame) -> void:
	if f == null:
		return
	var w := f.region.size.x
	var y := 0.0
	for band: Array in SENTENCE_BANDS:
		var y0 := float(band[0])
		var h := float(band[1]) - y0
		if y0 > y:
			UiArt.blit_part(ci, f, Rect2(0, y, w, y0 - y), Vector2(0, y))
		var x := 0.0
		for c: Vector2 in band[2]:
			if c.x > x:
				UiArt.blit_part(ci, f, Rect2(x, y0, c.x - x, h), Vector2(x, y0))
			UiArt.blit_part(ci, f, Rect2(BLANK_X, y0, 1, h), Vector2(c.x, y0), Vector2(c.y - c.x, h))
			x = c.y
		UiArt.blit_part(ci, f, Rect2(x, y0, w - x, h), Vector2(x, y0))
		y = float(band[1])
	UiArt.blit_part(ci, f, Rect2(0, y, w, TOP_H - y), Vector2(0, y))
	# Mid rows and the bottom edge exactly as TiledFrame.draw_v_slices draws them below TOP_H.
	var bottom_y := MID_Y + MID_H
	var bottom_h := f.region.size.y - bottom_y
	var yy := TOP_H
	var end := maxf(TOP_H, panel_size.y - bottom_h)
	while yy < end:
		var hh := minf(MID_H, end - yy)
		UiArt.blit_part(ci, f, Rect2(0, MID_Y, w, hh), Vector2(0, yy))
		yy += hh
	UiArt.blit_part(ci, f, Rect2(0, bottom_y, w, bottom_h), Vector2(0, end))


func _draw_level(ci: Control) -> void:
	var s := str(level)
	var frames: Array[SpriteFrame] = []
	var w := 0.0
	for ch in s:
		var f := UiArt.frame(LEVEL_DIGITS + ch)
		if f == null:
			frames.clear()
			break
		frames.append(f)
		w += f.region.size.x
	if not frames.is_empty() and w <= LEVEL_BOX.size.x:
		var x := LEVEL_BOX.position.x + floorf((LEVEL_BOX.size.x - w) * 0.5)
		for f in frames:
			UiArt.blit(ci, f, Vector2(x, LEVEL_BOX.position.y + floorf((LEVEL_BOX.size.y - f.region.size.y) * 0.5)))
			x += f.region.size.x
	else:
		MapleText.draw_centered(ci, LEVEL_BOX.position.x, LEVEL_BOX.position.y + 2.0, LEVEL_BOX.size.x, s,
			MapleText.WHITE, MapleText.SIZE, true)


func _draw_card(ci: Control, i: int, card: Dictionary, row_art: SpriteFrame) -> void:
	var b: Dictionary = _blocks[i]
	var r: Rect2 = b.row
	var p := r.position
	if row_art != null:
		TiledFrame.draw_h_slices(ci, p, row_art, ROW_SLOT_W, ROW_MID_X, r.size.x)
	else:
		ci.draw_rect(r, Color8(238, 238, 238) if i != focus else Color8(204, 221, 238))
	UiArt.blit_icon(ci, UiArt.icon_or_fallback(String(card.get("icon", ""))), p + Vector2(1, 1))
	var key := UiArt.frame(KEY_DIGITS + str(i + 1))
	if key != null:
		UiArt.blit(ci, key, p + Vector2(2, 2))
	var tx := p.x + ROW_SLOT_W + 4.0
	var name_w := r.end.x - tx - 3.0
	var nm := String(card.get("name", ""))
	var name_size := MapleText.SIZE if MapleText.width(nm, MapleText.SIZE, true) <= name_w else MapleText.SMALL
	MapleText.draw(ci, Vector2(tx, p.y + 2.0), MapleText.ellipsize(nm, name_w, name_size, true), MapleText.BLACK,
		name_size, true)
	var rt := rank_text(card)
	var learned := rt.begins_with("NEW")
	var rank_col := MapleText.ORANGE if learned or rt.ends_with("MAX") else Color8(68, 68, 68)
	MapleText.draw(ci, Vector2(tx, p.y + 19.0), rt, rank_col, MapleText.SMALL, learned)
	var style: Array = TIER_STYLES.get(String(card.get("tier", "normal")), TIER_STYLES.normal)
	var colour: Color = style[1]
	var band := Rect2(p + Vector2(1, ROW_H), Vector2(ROW_W - 2.0, TIER_BAND))
	ci.draw_rect(band, TIER_BACKGROUND)
	ci.draw_rect(band, Color(colour, TIER_TINT))
	MapleText.draw(ci, Vector2(p.x + 4.0, r.end.y + 2.0), String(style[0]), colour, MapleText.SMALL, true)
	var y := r.end.y + TIER_BAND + 3.0
	for line: String in b.desc:
		MapleText.draw_markup(ci, Vector2(p.x + 4.0, y), line, MapleText.WHITE, MapleText.SMALL, false, 0,
			MapleText.PANEL_SHADOW, true)
		y += DESC_LINE
	for line: String in b.changes:
		MapleText.draw_markup(ci, Vector2(p.x + 4.0, y), line, MapleText.WHITE, MapleText.SMALL, false, 0,
			MapleText.PANEL_SHADOW, true)
		y += DESC_LINE
	var block: Rect2 = b.block
	ci.draw_rect(Rect2(block.position + Vector2.ONE, block.size - Vector2(2, 2)), colour, false, TIER_FRAME)
