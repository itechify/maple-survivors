class_name UiArt
extends RefCounted
## Shared lookups and draw helpers for the MapleStory-styled UI (windows, title, stage select, results).
##
## Everything is addressed by WZ path through the asset cache ("Assets" autoload, or `library` when a caller sets one).
## Lookups never record a miss in AssetLibrary.missing for optional art (find() first, like Hud), and return null when
## the cache or the node is absent, so every widget degrades to "draw nothing" without art (unit tests, no cache).
##
## Drawing rule for UI canvases: `blit()` puts the canvas top-left at a point (UI art has origin 0,0 or ignores it);
## `blit_origin()` puts the canvas origin on the point (NPC sprites, mob icons, button keyFocused frames).

## UI click / hover sounds (Sound.wz/UI.img).
const SND_CLICK := "Sound.wz/UI.img/BtMouseClick"
const SND_OVER := "Sound.wz/UI.img/BtMouseOver"

## Library override (tests, tools); null = the "Assets" autoload.
static var library: AssetLibrary


## The asset library in use (null without an autoload and override).
static func lib() -> AssetLibrary:
	if library != null:
		return library
	return AssetLibrary.get_default()


## One canvas as a frame, or null when the cache/node is absent or not a canvas (no miss recorded).
static func frame(path: String) -> SpriteFrame:
	var l := lib()
	if l == null or path == "":
		return null
	if not WzImg.is_canvas(l.find(path)):
		return null
	var f := l.frame(path)
	return f if f != null and f.page != null else null


## The animation under a node ("0", "1", ... canvases, or one canvas), or null when absent (no miss recorded).
static func anim(path: String) -> SpriteAnim:
	var l := lib()
	if l == null or path == "":
		return null
	return l.find_anim(path)


## Any node of the cache by WZ path (null when absent; no miss recorded).
static func node(path: String) -> Variant:
	var l := lib()
	return l.find(path) if l != null else null


## A string leaf by WZ path ("" when absent).
static func text(path: String) -> String:
	var v: Variant = node(path)
	return String(v) if v is String else ""


## Size of a canvas in px (zero when absent).
static func size_of(path: String) -> Vector2:
	var f := frame(path)
	return f.region.size if f != null else Vector2.ZERO


## Draws a frame with its top-left at `p` (whole pixels).
static func blit(ci: CanvasItem, f: SpriteFrame, p: Vector2, col: Color = Color.WHITE) -> void:
	if f == null or f.page == null:
		return
	ci.draw_texture_rect_region(f.page, Rect2(p.floor(), f.region.size), f.region, col)


## Draws a frame with its origin at `p` (mirrored around p.x when `flip`).
static func blit_origin(ci: CanvasItem, f: SpriteFrame, p: Vector2, flip: bool = false,
		col: Color = Color.WHITE) -> void:
	if f == null or f.page == null:
		return
	MapDrawList.draw_frame(ci, f, p.floor(), flip, col)


## Draws the part `src` (canvas-local pixels) of a frame with its top-left at `p`, stretched to `dst_size` when given
## (only ever used to repeat 1-px wide/tall uniform slices; art is never scaled otherwise).
static func blit_part(ci: CanvasItem, f: SpriteFrame, src: Rect2, p: Vector2, dst_size: Vector2 = Vector2.ZERO,
		col: Color = Color.WHITE) -> void:
	if f == null or f.page == null or src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	var s := src.intersection(Rect2(Vector2.ZERO, f.region.size))
	if s.size.x <= 0.0 or s.size.y <= 0.0:
		return
	var dst := Rect2(p.floor(), s.size if dst_size == Vector2.ZERO else dst_size)
	ci.draw_texture_rect_region(f.page, dst, Rect2(f.region.position + s.position, s.size), col)


## Plays a UI sound through the "Sfx" autoload (no-op without it or without the cache).
static func play_sound(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx") as AudioService
	if sfx != null:
		sfx.play(path)


## The SpriteFrame drawn for a 32x32 icon slot: the icon at `path`, else the neutral fallback
## (UI.wz/UIWindow.img/IconBase/0, the empty icon base), else null.
static func icon_or_fallback(path: String) -> SpriteFrame:
	var f := frame(path)
	if f == null:
		f = frame(FALLBACK_ICON)
	return f


## Neutral icon for cards without (or with a missing) icon.
const FALLBACK_ICON := "UI.wz/UIWindow.img/IconBase/0"


## Draws an icon centred in a `box`-sized slot whose top-left is `p` (item icons are 27-32 px; their WZ origins
## position them on inventory slots, which we do not need here).
static func blit_icon(ci: CanvasItem, f: SpriteFrame, p: Vector2, box: Vector2 = Vector2(32, 32),
		col: Color = Color.WHITE) -> void:
	if f == null:
		return
	blit(ci, f, p + ((box - f.region.size) * 0.5).floor(), col)
