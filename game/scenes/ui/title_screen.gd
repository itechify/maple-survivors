extends Node2D
## Title screen (docs/ARCHITECTURE.md 4.1): the v83 login scene (LoginBackdrop at the title section, BGM
## BgmUI/Title, the book frame) with the game's buttons on the wooden login signboard: Start (Login.img/CharSelect/
## BtSelect, the wooden "Start") goes to the stage select, Quit (Login.img/Title/BtQuit) exits. "Re-import WZ data" on
## the middle plank re-runs the WZ import: a small wooden plate of the same signboard (Login.img/Title/BtLoginIDLost,
## "Find login ID", widened from its text-free left columns so it carries our label instead; its own mouseOver and
## pressed art). Keys: Enter = Start, Esc = Quit.
##
## There is no login here, so the signboard's "Login ID" / "Password" fields are covered with wood from the blank
## right end of the same plank (columns 266-357, repeated), drawn right after the map run that holds the sign.

const BT_START := "UI.wz/Login.img/CharSelect/BtSelect"
const BT_QUIT := "UI.wz/Login.img/Title/BtQuit"
## The small signboard plate behind the re-import label, and its text-free left columns (measured: the words start at
## column 7 of the 82 px plate in every state).
const BT_PLATE := "UI.wz/Login.img/Title/BtLoginIDLost"
const PLATE_LEFT := 5.0
const PLATE_PAD := 9.0
const PLATE_TEXT := Color8(255, 238, 204)
const PLATE_OUTLINE := Color8(68, 34, 0)
## The login signboard (Map.wz/Obj/login.img/Title/signboard/0, placed at (137, 21) by MapLogin.img, 368x236 with its
## origin at the centre). Start goes on the (covered) top plank, the re-import link on the middle plank, Quit on the
## big bottom plank; plank centres in sign-local px.
const SIGN_CENTER := Vector2(137, 21)
const SIGN := "Map.wz/Obj/login.img/Title/signboard/0/0"
## Sign-local rects: the labels and fields to cover, and the blank wood used to cover them.
const SIGN_FIELDS := Rect2(60, 7, 206, 77)
const SIGN_WOOD := Rect2(266, 7, 92, 77)
const SIGN_SIZE := Vector2(368, 236)
const PLANK_TOP := Vector2(208, 46)
const PLANK_MID := Vector2(208, 104)
const PLANK_LOW := Vector2(208, 151)

var backdrop: LoginBackdrop
var ui: CanvasLayer
var start_button: WzButton
var quit_button: WzButton
var reimport: WzButton

var _root: Control


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.TITLE)
	add_child(backdrop)
	_cover_sign_fields()
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_root)
	start_button = WzButton.new(BT_START)
	start_button.name = "Start"
	start_button.fallback_size = Vector2(101, 30)
	start_button.label = "" if start_button.has_art() else "Start"
	start_button.pressed.connect(_on_start)
	_root.add_child(start_button)
	quit_button = WzButton.new(BT_QUIT)
	quit_button.name = "Quit"
	quit_button.fallback_size = Vector2(84, 38)
	quit_button.label = "" if quit_button.has_art() else "Quit"
	quit_button.pressed.connect(_on_quit)
	_root.add_child(quit_button)
	reimport = WzButton.new(BT_PLATE, "Re-import WZ data")
	reimport.name = "Reimport"
	reimport.label_color = PLATE_TEXT
	reimport.label_outline = 1
	reimport.label_outline_color = PLATE_OUTLINE
	reimport.fallback_size = Vector2(MapleText.width(reimport.label, MapleText.SMALL, true) + 2.0 * PLATE_PAD, 23)
	reimport.set_plate(ceilf(MapleText.width(reimport.label, MapleText.SMALL, true) + 2.0 * PLATE_PAD), PLATE_LEFT)
	reimport.pressed.connect(_on_reimport)
	_root.add_child(reimport)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Covers the signboard's login fields: a node drawn right after the map run that holds the sign.
func _cover_sign_fields() -> void:
	var runs := backdrop.find_runs("Title/signboard")
	var f := UiArt.frame(SIGN)
	if runs.is_empty() or f == null:
		return
	var run := runs[0]
	var sign := Node2D.new()
	sign.name = "SignPatch"
	run.get_parent().add_child(sign)
	run.get_parent().move_child(sign, run.get_index() + 1)
	sign.position = SIGN_CENTER - f.origin
	sign.draw.connect(func() -> void:
		var x := SIGN_FIELDS.position.x
		while x < SIGN_FIELDS.end.x:
			var w := minf(SIGN_WOOD.size.x, SIGN_FIELDS.end.x - x)
			UiArt.blit_part(sign, f, Rect2(SIGN_WOOD.position, Vector2(w, SIGN_WOOD.size.y)),
				Vector2(x, SIGN_FIELDS.position.y))
			x += w)
	sign.queue_redraw()


func _layout() -> void:
	var view := get_viewport_rect().size
	var sign_tl := view * 0.5 + SIGN_CENTER - LoginBackdrop.TITLE - SIGN_SIZE * 0.5
	start_button.position = (sign_tl + PLANK_TOP - start_button.size * 0.5).floor()
	quit_button.position = (sign_tl + PLANK_LOW - quit_button.size * 0.5).floor()
	reimport.position = (sign_tl + PLANK_MID - reimport.size * 0.5).floor()


func _unhandled_input(event: InputEvent) -> void:
	if MapleWindow.is_confirm(event):
		start_button.pressed.emit()
		get_viewport().set_input_as_handled()
	elif MapleWindow.key_pressed(event, KEY_ESCAPE):
		quit_button.pressed.emit()
		get_viewport().set_input_as_handled()


func _on_start() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_stage_select()


func _on_quit() -> void:
	get_tree().quit()


func _on_reimport() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_import()
