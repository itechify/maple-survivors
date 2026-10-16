extends WzButton
## Original View All Characters plaque with an offline run-history label; preserves its angled frame and arrow.

## tier C: label patch inside the original ViewAllChar/BtVAC ink bounds, private spec32/v83-login-refs/charselect_1.png.
const PATCH := [Vector2(10, 17), Vector2(102, 8), Vector2(104, 30), Vector2(12, 39)]
const BURGUNDY := Color8(103, 38, 23)
const TEXT_AT := Vector2(12, 19)
const TEXT_ANGLE := -0.10
const TEXT_WIDTH := 88.0


func _init() -> void:
	super("UI.wz/Login.img/ViewAllChar/BtVAC")
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "Run history [H]"
	focus_entered.connect(func() -> void: key_focused = true)
	focus_exited.connect(func() -> void: key_focused = false)


func _draw() -> void:
	super._draw()
	draw_colored_polygon(PATCH, BURGUNDY)
	draw_set_transform(TEXT_AT, TEXT_ANGLE)
	MapleText.draw_centered(self, 0, 0, TEXT_WIDTH, "Run history", Color8(255, 238, 204), MapleText.SMALL,
		false, 1, Color8(68, 34, 0))
	draw_set_transform(Vector2.ZERO)
