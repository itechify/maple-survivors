class_name HudBossBar
extends HudWidget
## Stacked live-boss HP bars using v83 MobGage frames, icons and canonical or survivor hpTag colour indices.

const ART := "UI.wz/UIWindow.img/MobGage/"
## tier C: the reserved centred bar is 300 px wide; 42 px row pitch leaves a gap below the 37 px icon frame.
const BAR_WIDTH := 300.0
const ROW_HEIGHT := 42.0
const FILL_WIDTH := 256.0

var _rows: Array[Dictionary] = []


## Receives the scene's live boss snapshots; every displayed value and frame comes from this snapshot.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	_rows.clear()
	for boss: Dictionary in info.get("bosses", []):
		var row := boss.duplicate()
		row["ratio"] = clampf(float(row.hp) / maxf(1.0, float(row.max_hp)), 0.0, 1.0)
		row["icon_path"] = ART + "Mob/" + str(int(row.icon_id))
		row["color_path"] = ART + "Gage/%d/0" % int(row.hp_tag_color)
		row["background_path"] = ART + "Gage/%d/1" % int(row.hp_tag_bgcolor)
		row["icon"] = _frame(row.icon_path, true)
		_rows.append(row)
	size.y = maxf(ROW_HEIGHT, _rows.size() * ROW_HEIGHT)
	visible = not _rows.is_empty()


## The snapshots actually displayed, in encounter order (empty before arrival and immediately after death).
func displayed() -> Array[Dictionary]:
	return _rows.duplicate(true)


func _draw() -> void:
	if font == null:
		return
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var y := i * ROW_HEIGHT
		_blit_rect(_frame(ART + "backgrnd", true), Rect2(0, y, 35, 37))
		_blit_rect(_frame(ART + "backgrnd2", true), Rect2(35, y + 17, 4, 19))
		_blit_rect(_frame(ART + "backgrnd3", true), Rect2(39, y + 17, FILL_WIDTH, 20))
		_blit_rect(_frame(ART + "backgrnd4", true), Rect2(295, y + 17, 5, 20))
		_blit_rect(_frame(row.background_path, true), Rect2(39, y + 21, FILL_WIDTH, 12))
		var fill := fill_width(float(row.hp), float(row.max_hp), FILL_WIDTH)
		if fill > 0:
			_blit_rect(_frame(row.color_path, true), Rect2(39, y + 22, fill, 10))
		var icon: SpriteFrame = row.icon
		if icon != null:
			_blit_rect(icon, Rect2(Vector2(5, y + 6), icon.size()))
		_text(Vector2(40, y + 13), row.name, Color.WHITE, FONT_SIZE, null, 1.0, Color.BLACK, BAR_WIDTH - 40)
