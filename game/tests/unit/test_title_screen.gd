extends TestCase
## Title screen (docs/ARCHITECTURE.md 4.1): the key art (KeyArt) covers the view in place of the v83 login scene, and
## the TitleButtons sit under the logo, inside the view, without overlapping; Enter presses Start. The web-only
## entries are covered by test_web_profile.gd.

var _nodes: Array[Node] = []


func after_each() -> void:
	WebProfile.forced = -1
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _title(web := false) -> Node2D:
	WebProfile.forced = 1 if web else 0
	var t := load("res://scenes/ui/title_screen.tscn").instantiate() as Node2D
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(t)
	_nodes.append(t)
	return t


func _buttons(t: Node2D) -> Array[TitleButton]:
	var out: Array[TitleButton] = []
	for b: TitleButton in [t.start_button, t.reimport, t.quit_button, t.fullscreen_button, t.export_save_button,
			t.import_save_button]:
		if b != null and b.visible:
			out.append(b)
	return out


func test_cover_rect_covers_and_keeps_the_aspect() -> void:
	for view: Vector2 in [Vector2(800, 600), Vector2(1066, 600), Vector2(800, 900), Vector2(1400, 600)]:
		var r := KeyArt.cover_rect(view)
		assert_true(r.encloses(Rect2(Vector2.ZERO, view)), "covers %s" % view)
		assert_true(absf(r.size.x / r.size.y - KeyArt.SIZE.x / KeyArt.SIZE.y) < 0.01, "aspect at %s" % view)
		assert_true(absf(r.get_center().x - view.x * 0.5) <= 1.0 and absf(r.get_center().y - view.y * 0.5) <= 1.0,
			"centred at %s" % view)


func test_title_shows_the_key_art_not_the_login_scene() -> void:
	var t := _title()
	assert_true(t.find_children("*", "LoginBackdrop", true, false).is_empty(), "no v83 login backdrop")
	var art: KeyArt = t.art
	assert_true(art.texture != null, "the key art is loaded")
	var view := Rect2(Vector2.ZERO, t.get_viewport_rect().size)
	assert_true(Rect2(art.position, art.size).encloses(view), "the art covers the view")


func test_buttons_sit_under_the_logo_inside_the_view() -> void:
	for web: bool in [false, true]:
		var t := _title(web)
		var view := Rect2(Vector2.ZERO, t.get_viewport_rect().size)
		var bs := _buttons(t)
		assert_eq(bs.size(), 5 if web else 3, "visible buttons (web %s)" % web)
		var logo_bottom: float = (t.art as KeyArt).art_to_view(Vector2(0, t.LOGO_BOTTOM)).y
		for i in bs.size():
			var r := Rect2(bs[i].position, bs[i].size)
			assert_true(view.encloses(r), "%s is inside the view" % bs[i].name)
			assert_true(r.position.y >= logo_bottom - 1.0 or r.end.y >= view.size.y - 40.0,
				"%s is under the logo" % bs[i].name)
			for j in range(i + 1, bs.size()):
				assert_false(r.intersects(Rect2(bs[j].position, bs[j].size)),
					"%s and %s do not overlap" % [bs[i].name, bs[j].name])
		assert_true(t.start_button.size.y > t.reimport.size.y, "Start is the big button")


func test_enter_presses_start() -> void:
	var t := _title()
	t.start_button.pressed.disconnect(t._on_start)
	var starts := [0]
	t.start_button.pressed.connect(func() -> void: starts[0] += 1)
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	t._unhandled_input(e)
	assert_eq(starts[0], 1, "Enter = Start")


func test_title_button_fits_its_label() -> void:
	var b := TitleButton.new("Re-import WZ data")
	_nodes.append(b)
	var text_w := MapleText.width("Re-import WZ data", TitleButton.SECONDARY_TEXT, true)
	assert_true(b.size.x >= text_w + 2.0 * TitleButton.PAD - 1.0, "the label fits with its padding")
	assert_eq(b.focus_mode, Control.FOCUS_NONE, "no keyboard focus (Enter belongs to the screen)")
	var wide := TitleButton.new("Start", TitleButton.Style.PRIMARY, 168.0)
	_nodes.append(wide)
	assert_eq(wide.size, Vector2(168, TitleButton.PRIMARY_HEIGHT))
