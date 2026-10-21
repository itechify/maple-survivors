extends TestCase
## Sharp text (#224, docs/ARCHITECTURE.md "Fonts and sharp text"): the window renders canvas items at its real
## resolution (stretch mode canvas_items) so fonts rasterise at window pixels, while logical text metrics stay frozen
## (sibling UI tickets lay out with them), one constant picks the antialiasing, and the pixel-art helpers reproduce what
## the old 800x600 render drew for thin outlines and nearest-scaled icons.

## Known strings and their widths at 12 / 11 px in the bundled Arimo (regular, bold), recorded before #224 with the
## old viewport stretch. Arimo ships with the game, so these hold on every platform.
const STRINGS := ["Hello World", "Lv. 38 Fire/Poison Wizard", "+1,234 EXP", "Req LEV : 30   STR 25 DEX 25",
	"Iiiil|llWWMMmm 0123456789", "HP Del / Ctrl", "Mesos 1,234,567"]
const GOLDEN := {
	"400_12": [61.0, 137.0, 64.0, 167.0, 155.0, 66.0, 92.0],
	"400_11": [57.0, 125.0, 59.0, 152.0, 142.0, 61.0, 84.0],
	"700_12": [66.0, 145.0, 64.0, 169.0, 161.0, 69.0, 94.0],
	"700_11": [61.0, 132.0, 59.0, 154.0, 147.0, 63.0, 86.0],
}
const PARAGRAPH := "A long tooltip sentence that has to wrap across lines in the item window."


func test_window_draws_canvas_items_at_its_own_resolution() -> void:
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand")
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/scale_mode")), "integer")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 800)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 600)
	assert_eq(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")), 0,
		"nearest: pixel art stays pixel art")
	assert_true(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")))
	assert_true(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel")))


func test_arimo_metrics_are_unchanged_in_logical_pixels() -> void:
	for w in [400, 700]:
		var f := MapleFonts.arimo(w)
		for sz in [12, 11]:
			var want: Array = GOLDEN["%d_%d" % [w, sz]]
			for i in STRINGS.size():
				assert_eq(f.get_string_size(STRINGS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x, want[i],
					"%s at %d px, weight %d" % [STRINGS[i], sz, w])
			assert_eq(f.get_ascent(sz), 11.0 if sz == 12 else 10.0, "ascent %d" % sz)
			assert_eq(f.get_height(sz), 14.0 if sz == 12 else 13.0, "height %d" % sz)


func test_maple_text_metrics_and_wrapping_are_unchanged() -> void:
	# The game font is the system Arial on Windows, Arimo elsewhere; both are metric compatible, so the recorded widths
	# hold for MapleText on the owner's machine and wherever Arimo is used (a Linux "Arial" alias may hint differently).
	var f := MapleText.font()
	if f is FontVariation or OS.get_name() == "Windows":
		var want: Array = GOLDEN["400_12"]
		for i in STRINGS.size():
			assert_eq(MapleText.width(STRINGS[i]), want[i], STRINGS[i])
		assert_eq(MapleText.wrap(PARAGRAPH, 120), PackedStringArray(["A long tooltip sentence", "that has to wrap",
			"across lines in the", "item window."]))
	assert_eq(MapleText.LINE, 15)
	assert_eq(MapleText.LINE_SMALL, 13)
	assert_eq(MapleText.ascent(12), 11.0)
	assert_eq(MapleText.ascent(11), 10.0)


func test_antialiasing_does_not_move_text() -> void:
	# The AA choice only changes how glyphs are rasterised: the widths of both variants are identical.
	for weight in [400, 700]:
		var crisp := _arimo_copy(weight, TextServer.FONT_ANTIALIASING_NONE)
		var gray := _arimo_copy(weight, TextServer.FONT_ANTIALIASING_GRAY)
		for s: String in STRINGS:
			for sz in [12, 11]:
				assert_eq(gray.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz),
					crisp.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz), "%s %d %d" % [s, sz, weight])


func test_one_constant_sets_the_antialiasing_of_every_game_font() -> void:
	var want := TextServer.FONT_ANTIALIASING_GRAY if MapleFonts.ANTIALIASED else TextServer.FONT_ANTIALIASING_NONE
	assert_eq(MapleFonts.antialiasing(), want)
	var sys := MapleFonts.make_with(PackedStringArray(["Arial"]), 400, true) as SystemFont
	assert_eq(sys.antialiasing, want, "SystemFont")
	assert_eq(sys.hinting, TextServer.HINTING_NORMAL, "hinting fixed: it moves advances")
	assert_eq(sys.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED)
	var arimo := (MapleFonts.arimo(400) as FontVariation).base_font as FontFile
	assert_eq(arimo.antialiasing, want, "bundled Arimo")
	assert_eq(arimo.hinting, TextServer.HINTING_NORMAL)
	for f: Font in [MapleText.font(), MapleText.font(true), HudWidget.make_font(400), HudWidget.make_font(700)]:
		var aa: int = (f as SystemFont).antialiasing if f is SystemFont \
			else ((f as FontVariation).base_font as FontFile).antialiasing
		assert_eq(aa, want, "game font %s" % f)


func test_thin_outline_covers_the_old_800x600_pixels() -> void:
	# What draw_rect(Rect2(10, 100, 40, 20), c, false) lit in the 800x600 render (measured, GL compatibility): the top
	# edge one row above the rect, the left edge one column left of it, the right and bottom edges inside it.
	var lit := {}
	var area := 0
	for r: Rect2 in PixelDraw.outline_rects(Rect2(10, 100, 40, 20)):
		area += int(r.get_area())
		for y in range(int(r.position.y), int(r.end.y)):
			for x in range(int(r.position.x), int(r.end.x)):
				lit[Vector2i(x, y)] = true
	var want := {}
	for x in range(10, 50):
		want[Vector2i(x, 99)] = true
	for y in range(100, 120):
		want[Vector2i(9, y)] = true
	for y in range(100, 119):
		want[Vector2i(49, y)] = true
	for x in range(9, 50):
		want[Vector2i(x, 119)] = true
	assert_eq(lit.size(), want.size(), "pixel count")
	assert_eq(area, lit.size(), "no pixel drawn twice (translucent outlines)")
	for p: Vector2i in want:
		assert_true(lit.has(p), "lit %s" % p)


func test_nearest_runs_pick_the_texels_the_gpu_picked() -> void:
	# Destination pixel i of a nearest downscale src -> dst samples texel floor((i + 0.5) * src / dst); runs group
	# consecutive pixels with consecutive texels so each run is an unscaled 1:1 copy.
	var runs := PixelDraw.nearest_runs(32, 24)
	var picked := PackedInt32Array()
	for k in range(0, runs.size(), 3):
		for j in runs[k + 2]:
			assert_eq(runs[k] + j, picked.size(), "runs are contiguous in the destination")
			picked.append(runs[k + 1] + j)
	assert_eq(picked.size(), 24)
	for i in 24:
		assert_eq(picked[i], int(floor((i + 0.5) * 32.0 / 24.0)), "pixel %d" % i)
	assert_eq(runs.size() / 3, 9, "32 -> 24 is nine runs (one texel in four is dropped)")
	assert_eq(PixelDraw.nearest_runs(24, 24), PackedInt32Array([0, 0, 24]), "same size: one run")


func _arimo_copy(weight: int, aa: TextServer.FontAntialiasing) -> Font:
	var file := (load(MapleFonts.ARIMO_PATH) as FontFile).duplicate() as FontFile
	file.antialiasing = aa
	file.hinting = TextServer.HINTING_NORMAL
	file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var v := FontVariation.new()
	v.base_font = file
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v


func test_tool_fill_override_is_never_saved() -> void:
	# main.gd --fill (evidence of the fill-window mode) must not persist into the player's settings.cfg.
	var path := TestCase.test_dir("sharp_text_settings.cfg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := GameSettings.new(path)
	s.fill_override = true
	s.set_volume("master", 0.5)
	var back := GameSettings.new(path)
	assert_false(back.fill_window, "the override is not written")
	assert_false(back.fill_override, "nor read back")
	s.free()
	back.free()


func test_capture_rect_scales_logical_crops_to_the_capture() -> void:
	# A capture holds the view at the window's integer scale (bars excluded): 800x600 view, 1600x1200 capture.
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(vp)
	assert_true(vp.is_inside_tree(), "capture viewport is attached to the test scene")
	var img := Image.create(1600, 1200, false, Image.FORMAT_RGBA8)
	assert_eq(GameSettings.capture_rect(img, vp, Rect2(10, 20, 100, 50)), Rect2i(20, 40, 200, 100))
	var same := Image.create(800, 600, false, Image.FORMAT_RGBA8)
	assert_eq(GameSettings.capture_rect(same, vp, Rect2(10, 20, 100, 50)), Rect2i(10, 20, 100, 50), "1x")
	var sheet := GameSettings.capture_logical(vp, img, Rect2(0, 0, 760, 300))
	assert_eq(sheet.get_size(), Vector2i(760, 300), "contact sheets keep their logical size")
	vp.free()


func test_edge_outline_lights_the_rows_and_columns_on_the_edges_once() -> void:
	# draw_rect(Rect2(5, 7, 4, 3), c, false, 1.0) lit rows 7 and 10, columns 5 and 9 in the 800x600 render.
	var lit := {}
	var area := 0
	for r: Rect2 in PixelDraw.edge_outline_rects(Rect2(5, 7, 4, 3)):
		area += int(r.get_area())
		for y in range(int(r.position.y), int(r.end.y)):
			for x in range(int(r.position.x), int(r.end.x)):
				lit[Vector2i(x, y)] = true
	var want := {}
	for x in range(5, 10):
		want[Vector2i(x, 7)] = true
		want[Vector2i(x, 10)] = true
	for y in range(8, 10):
		want[Vector2i(5, y)] = true
		want[Vector2i(9, y)] = true
	assert_eq(lit, want)
	assert_eq(area, want.size(), "corners drawn once")
