class_name HudBossBar
extends HudReservedSlot
## Stacked live-boss HP bars using v83 MobGage frames, icons and canonical or survivor hpTag colour indices.

const ART := "UI.wz/UIWindow.img/MobGage/"
## tier C: the reserved centred bar is 300 px wide; 42 px row pitch leaves a gap below the 37 px icon frame.
const BAR_WIDTH := 300.0
const ROW_HEIGHT := 42.0
const FILL_WIDTH := 256.0

var library: AssetLibrary
var _rows: Array[Dictionary] = []
var _frames: Dictionary = {}
var _font: SystemFont


func _ready() -> void:
	_font = HudWidget.make_font()


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
		row["icon"] = _frame(row.icon_path)
		_rows.append(row)
	size.y = maxf(ROW_HEIGHT, _rows.size() * ROW_HEIGHT)
	visible = not _rows.is_empty()


## The snapshots actually displayed, in encounter order (empty before arrival and immediately after death).
func displayed() -> Array[Dictionary]:
	return _rows.duplicate(true)


func _draw() -> void:
	if _font == null:
		return
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var y := i * ROW_HEIGHT
		_blit(_frame(ART + "backgrnd"), Rect2(0, y, 35, 37))
		_blit(_frame(ART + "backgrnd2"), Rect2(35, y + 17, 4, 19))
		_blit(_frame(ART + "backgrnd3"), Rect2(39, y + 17, FILL_WIDTH, 20))
		_blit(_frame(ART + "backgrnd4"), Rect2(295, y + 17, 5, 20))
		_blit(_frame(row.background_path), Rect2(39, y + 21, FILL_WIDTH, 12))
		var fill := HudWidget.fill_width(float(row.hp), float(row.max_hp), FILL_WIDTH)
		if fill > 0:
			_blit(_frame(row.color_path), Rect2(39, y + 22, fill, 10))
		var icon: SpriteFrame = row.icon
		if icon != null:
			_blit(icon, Rect2(Vector2(5, y + 6), icon.size()))
		var at := Vector2(40, y + 13)
		draw_string_outline(_font, at, row.name, HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH - 40, 12, 2, Color.BLACK)
		draw_string(_font, at, row.name, HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH - 40, 12, Color.WHITE)


func _frame(path: String) -> SpriteFrame:
	if not _frames.has(path):
		var lib := library if library != null else AssetLibrary.get_default()
		_frames[path] = lib.frame(path) if lib != null else null
	return _frames[path]


func _blit(frame: SpriteFrame, rect: Rect2) -> void:
	if frame != null and frame.page != null:
		draw_texture_rect_region(frame.page, rect, frame.region)
