class_name OptionsWindow
extends UiWindow
## The Options window (Menu -> Options, or the pause menu): BGM and SFX volume, the frame cap and the movement keys.
## Every change is applied and saved at once through the Settings setters (set_volume, set_max_fps,
## set_movement_keys); BtOK (or Esc) only closes.
##
##   OptionsWindow.new(Settings)
##
## Art: composed from the v83 System Option window (UI.wz/UIWindow.img/SysOpt `backgrnd`): its title, its BGM and
## SOUND rows as they are (SOFT ... LOUD sliders from Basic.img/Slider, the MUTE boxes from Basic.img/CheckBox), two
## of its empty rows relabelled FRAME CAP and MOVE KEYS with a CheckBox per choice, and its bottom strip with
## KeyConfig's BtOK. The other SysOpt rows (picture quality, mouse cursor, alerts...) have no meaning here and are left
## out. Without the cache the window keeps its layout and draws plain rows.

const ART := "UI.wz/UIWindow.img/SysOpt/backgrnd"
const SLIDER := "UI.wz/Basic.img/Slider/"
const CHECK := "UI.wz/Basic.img/CheckBox/"
const WIDTH := 299.0
## tier C (ours, measured on the v83 SysOpt backgrnd): its title part, row pitch, the source rows used (BGM 1, SOUND
## 2, the empty MONSTER INFO. row 8 as the template of ours), the bottom strip, the label box and the panel.
const HEADER_H := 32.0
const ROW_H := 30.0
const SRC_ROW_Y := {"bgm": 62.0, "sfx": 92.0, "blank": 272.0}
const SRC_BOTTOM_Y := 330.0
const BOTTOM_H := 36.0
const LABEL_BOX := Rect2(9, 1, 46, 27)
const LABEL_FILL := Color8(204, 85, 136)
const PANEL_X := 58.0
## tier C (ours): the slider track between the baked SOFT and LOUD words, the MUTE box left of the baked MUTE.
const TRACK := Rect2(93, 11, 116, 8)
const THUMB := Vector2(22, 14)
const MUTE_BOX := Vector2(243, 9)
const CHECK_SIZE := Vector2(12, 12)
## Rows top to bottom: id, label lines (our rows only).
const ROWS := [["bgm", ""], ["sfx", ""], ["frame_cap", "FRAME\nCAP"], ["movement", "MOVE\nKEYS"]]
## tier C (ours): the frame cap choices (GameSettings.max_fps: 0 = the display's refresh rate, -1 = uncapped) and
## their captions, then the movement choices.
const FRAME_CAPS := [0, 60, 144, -1]
const FRAME_CAP_NAMES := ["SCREEN", "60", "144", "OFF"]
const MOVEMENTS := ["arrows", "wasd"]
const MOVEMENT_NAMES := ["ARROWS", "WASD"]
## Choice i's checkbox x in a row (PANEL_X + CHOICE_X0 + i * step).
const CHOICE_X0 := 8.0
const FRAME_CAP_STEP := 56.0
const MOVEMENT_STEP := 84.0

## The settings every control writes.
var settings: GameSettings

var _sliding := ""
var _before_mute: Dictionary = {}
var _bt_ok: WzButton


func _init(p_settings: GameSettings = null) -> void:
	super._init()
	name = "OptionsWindow"
	window_id = "options"
	settings = p_settings
	size = Vector2(WIDTH, HEADER_H + ROWS.size() * ROW_H + BOTTOM_H)
	_bt_ok = WzButton.new("UI.wz/UIWindow.img/KeyConfig/BtOK")
	_bt_ok.name = "OK"
	_bt_ok.fallback_size = Vector2(47, 18)
	if not _bt_ok.has_art():
		_bt_ok.label = "OK"
	_bt_ok.position = Vector2(WIDTH - 10.0 - _bt_ok.size.x, size.y - BOTTOM_H + 12.0)
	_bt_ok.pressed.connect(request_close)
	add_child(_bt_ok)
	if settings != null:
		settings.changed.connect(queue_redraw)


## Top y of row `id`.
func row_y(id: String) -> float:
	for i in ROWS.size():
		if String(ROWS[i][0]) == id:
			return HEADER_H + i * ROW_H
	return -1.0


## The local rect of the "bgm" / "sfx" slider track.
func slider_rect(kind: String) -> Rect2:
	return Rect2(TRACK.position + Vector2(0, row_y(kind)), TRACK.size)


## The local rect of the "bgm" / "sfx" MUTE box.
func mute_rect(kind: String) -> Rect2:
	return Rect2(MUTE_BOX + Vector2(0, row_y(kind)), CHECK_SIZE)


## The local rect (box and caption) of frame cap choice `i` (FRAME_CAPS).
func frame_cap_rect(i: int) -> Rect2:
	return _choice_rect("frame_cap", i, FRAME_CAP_STEP, String(FRAME_CAP_NAMES[i]))


## The local rect (box and caption) of movement choice "arrows" / "wasd".
func movement_rect(scheme: String) -> Rect2:
	var i := MOVEMENTS.find(scheme)
	return _choice_rect("movement", i, MOVEMENT_STEP, String(MOVEMENT_NAMES[i]))


## The FRAME_CAPS index of the current setting (-1 when it is a value the window does not offer).
func frame_cap_choice() -> int:
	return FRAME_CAPS.find(settings.max_fps) if settings != null else 0


## True when the volume ("bgm" / "sfx") is 0.
func is_muted(kind: String) -> bool:
	return _volume(kind) <= 0.0


func _volume(kind: String) -> float:
	if settings == null:
		return 0.0
	return settings.bgm_volume if kind == "bgm" else settings.sfx_volume


func _choice_rect(row: String, i: int, step: float, caption: String) -> Rect2:
	var x := PANEL_X + CHOICE_X0 + i * step
	var w := CHECK_SIZE.x + 4.0 + MapleText.width(caption, MapleText.SMALL)
	return Rect2(x, row_y(row) + 8.0, w, CHECK_SIZE.y)


## The slider's hit area: the track widened to the thumb.
func _slider_hit(kind: String) -> Rect2:
	var r := slider_rect(kind)
	return Rect2(r.position.x - THUMB.x * 0.5, r.position.y - 4.0, r.size.x + THUMB.x, THUMB.y)


func _set_from_slider(kind: String, x: float) -> void:
	var r := slider_rect(kind)
	var v := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	settings.set_volume(kind, snappedf(v, 0.01))


func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	if settings == null:
		return
	if event is InputEventMouseMotion:
		if _sliding != "":
			_set_from_slider(_sliding, local.x)
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		_sliding = ""
		return
	for kind: String in ["bgm", "sfx"]:
		if _slider_hit(kind).has_point(local):
			_sliding = kind
			_set_from_slider(kind, local.x)
			return
		if mute_rect(kind).grow(2.0).has_point(local):
			_toggle_mute(kind)
			return
	for i in FRAME_CAPS.size():
		if frame_cap_rect(i).grow(2.0).has_point(local):
			UiArt.play_sound(UiArt.SND_CLICK)
			settings.set_max_fps(int(FRAME_CAPS[i]))
			return
	for scheme: String in MOVEMENTS:
		if movement_rect(scheme).grow(2.0).has_point(local):
			UiArt.play_sound(UiArt.SND_CLICK)
			settings.set_movement_keys(scheme)
			return


## MUTE: 0 volume; unchecking restores the volume it had (the default when it was opened muted).
func _toggle_mute(kind: String) -> void:
	UiArt.play_sound(UiArt.SND_CLICK)
	if is_muted(kind):
		var fallback := GameSettings.DEFAULT_BGM if kind == "bgm" else GameSettings.DEFAULT_SFX
		settings.set_volume(kind, float(_before_mute.get(kind, fallback)))
	else:
		_before_mute[kind] = _volume(kind)
		settings.set_volume(kind, 0.0)


func _draw() -> void:
	var bg := UiArt.frame(ART)
	if bg != null:
		UiArt.blit_part(self, bg, Rect2(0, 0, WIDTH, HEADER_H), Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
		MapleText.draw(self, Vector2(8, 6), "SYSTEM OPTION", MapleText.BLACK, MapleText.SMALL, true)
	for row: Array in ROWS:
		var id := String(row[0])
		var y := row_y(id)
		var src := float(SRC_ROW_Y.get(id, SRC_ROW_Y.blank))
		if bg != null:
			UiArt.blit_part(self, bg, Rect2(0, src, WIDTH, ROW_H), Vector2(0, y))
		else:
			draw_rect(Rect2(PANEL_X, y + 1.0, 230, ROW_H - 3.0), Color8(221, 221, 210))
		if String(row[1]) != "" or bg == null:
			_draw_label(y, String(row[1]) if String(row[1]) != "" else id.to_upper())
		match id:
			"bgm", "sfx":
				_draw_volume(id, bg == null)
			"frame_cap":
				for i in FRAME_CAPS.size():
					_draw_choice(frame_cap_rect(i), String(FRAME_CAP_NAMES[i]), i == frame_cap_choice())
			"movement":
				for i in MOVEMENTS.size():
					var scheme := String(MOVEMENTS[i])
					_draw_choice(movement_rect(scheme), String(MOVEMENT_NAMES[i]),
						settings != null and settings.movement_keys == scheme)
	var bottom := size.y - BOTTOM_H
	if bg != null:
		UiArt.blit_part(self, bg, Rect2(0, SRC_BOTTOM_Y, WIDTH, BOTTOM_H), Vector2(0, bottom))
	else:
		draw_rect(Rect2(0, bottom + 8.0, WIDTH, BOTTOM_H - 10.0), Color8(153, 187, 204))


func _draw_label(y: float, text: String) -> void:
	var box := Rect2(LABEL_BOX.position + Vector2(0, y), LABEL_BOX.size)
	draw_rect(box, LABEL_FILL)
	var lines := text.split("\n")
	var top := box.position.y + floorf((box.size.y - lines.size() * 11.0) * 0.5) - 1.0
	for i in lines.size():
		MapleText.draw_centered(self, box.position.x, top + i * 11.0, box.size.x, lines[i], MapleText.WHITE, 9, true)


func _draw_volume(kind: String, plain: bool) -> void:
	var r := slider_rect(kind)
	var left := UiArt.frame(SLIDER + "left")
	var mid := UiArt.frame(SLIDER + "mid")
	var right := UiArt.frame(SLIDER + "right")
	if left != null and mid != null and right != null:
		UiArt.blit(self, left, r.position)
		UiArt.blit_part(self, mid, Rect2(Vector2.ZERO, mid.region.size), r.position + Vector2(3, 0),
			Vector2(r.size.x - 6.0, r.size.y))
		UiArt.blit(self, right, Vector2(r.end.x - 3.0, r.position.y))
	else:
		draw_rect(r, Color8(120, 140, 160))
	if plain:
		MapleText.draw(self, Vector2(PANEL_X + 12.0, r.position.y - 3.0), "SOFT", MapleText.BLACK, 9)
		MapleText.draw(self, Vector2(r.end.x + 6.0, r.position.y - 3.0), "LOUD", MapleText.BLACK, 9)
		MapleText.draw(self, mute_rect(kind).position + Vector2(16, -1), "MUTE", MapleText.BLACK, 9)
	var thumb_at := Vector2(r.position.x + r.size.x * _volume(kind) - THUMB.x * 0.5, r.get_center().y - THUMB.y * 0.5)
	var thumb := UiArt.frame(SLIDER + ("thumbPressed" if _sliding == kind else "thumbNormal"))
	if thumb != null:
		UiArt.blit(self, thumb, thumb_at.round())
	else:
		draw_rect(Rect2(thumb_at.round(), THUMB), Color8(68, 136, 187))
	_draw_check(mute_rect(kind).position, is_muted(kind))


func _draw_choice(r: Rect2, caption: String, on: bool) -> void:
	_draw_check(r.position, on)
	MapleText.draw(self, r.position + Vector2(CHECK_SIZE.x + 4.0, -1.0), caption, MapleText.BLACK, MapleText.SMALL)


func _draw_check(at: Vector2, on: bool) -> void:
	var f := UiArt.frame(CHECK + ("1" if on else "0"))
	if f != null:
		UiArt.blit(self, f, at)
		return
	draw_rect(Rect2(at, CHECK_SIZE), Color.WHITE)
	draw_rect(Rect2(at, CHECK_SIZE), Color8(90, 90, 90), false)
	if on:
		draw_rect(Rect2(at + Vector2(3, 3), CHECK_SIZE - Vector2(6, 6)), Color8(40, 40, 40))
