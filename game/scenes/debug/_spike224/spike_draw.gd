extends Node2D
var tex: ImageTexture
var ci: RID
func _ready() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, Color(rng.randf(), float(x) / 31.0, float(y) / 31.0))
	tex = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for k in 4:
		var c := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(c, get_canvas_item())
		RenderingServer.canvas_item_add_texture_rect(c, Rect2(-16, -16, 32, 32), tex.get_rid())
		RenderingServer.canvas_item_set_transform(c, Transform2D(0.35 * (k + 1), Vector2(260.5 + k * 50, 60.25)))
func _draw() -> void:
	draw_texture(tex, Vector2(10, 10))
	draw_texture(tex, Vector2(50.5, 10.25))
	draw_texture_rect(tex, Rect2(90, 10, 24, 24), false)
	draw_texture_rect(tex, Rect2(130, 10, 28, 28), false)
	draw_set_transform(Vector2(200, 30), 0.6)
	draw_texture(tex, Vector2(-16, -16))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(10, 100, 40, 20), Color.WHITE, false)
	draw_rect(Rect2(60, 100, 40, 20).grow(-0.5), Color.WHITE, false, 1.0)
	draw_line(Vector2(110, 100), Vector2(150, 100), Color.WHITE)
	draw_line(Vector2(110, 110), Vector2(150, 110), Color.WHITE, 1.0)
	draw_line(Vector2(110, 120.5), Vector2(150, 120.5), Color.WHITE, 1.0)
	draw_rect(Rect2(10, 140, 380, 150), Color(0.85, 0.85, 0.8))
	var y := 145.0
	for s in ["Hello, MapleStory!  Item  STR 25  DEX 25", "Lv. 38 Fire/Poison Wizard +1,234 EXP", "Req LEV : 30  0123456789"]:
		MapleText.draw(self, Vector2(15, y), s, MapleText.BLACK); y += MapleText.LINE
		MapleText.draw(self, Vector2(15, y), s, MapleText.BLACK, MapleText.SMALL); y += MapleText.LINE_SMALL
		MapleText.draw(self, Vector2(15, y), s, MapleText.BLACK, MapleText.SIZE, true); y += MapleText.LINE
	MapleText.draw(self, Vector2(15, 300), "+42 EXP  outlined yellow", MapleText.YELLOW, 12, false, 1)
