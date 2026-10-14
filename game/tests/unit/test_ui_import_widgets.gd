extends TestCase
## Import screen folder validation and importer command (pure functions, a temp folder of empty .wz files), and the UI
## widgets: frame tiling math, Maple text wrapping, WzButton / WzImage with and without the asset cache.

const IMPORT := preload("res://scenes/ui/import_screen.gd")
var wz_dir := TestCase.test_dir("wz_folder")

var _nodes: Array[Node] = []


func before_each() -> void:
	_clear_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(wz_dir))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_clear_dir()


func _clear_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(wz_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)


func _touch(names: Array) -> void:
	for n: String in names:
		var f := FileAccess.open(ProjectSettings.globalize_path(wz_dir).path_join(n), FileAccess.WRITE)
		f.close()


# --- import screen -----------------------------------------------------------------------------------------------

func test_validate_wz_folder() -> void:
	var abs_dir := ProjectSettings.globalize_path(wz_dir)
	var v: Dictionary = IMPORT.validate_wz_folder("")
	assert_false(v.ok, "empty path")
	v = IMPORT.validate_wz_folder(abs_dir.path_join("nope"))
	assert_false(v.ok, "missing folder")
	assert_true(String(v.message).contains("does not exist"))
	v = IMPORT.validate_wz_folder(abs_dir)
	assert_false(v.ok, "empty folder")
	assert_eq((v.missing as PackedStringArray).size(), IMPORT.REQUIRED.size())
	assert_true(String(v.message).contains("No .wz files"))
	_touch(["Map.wz", "Mob.wz", "UI.wz"])
	v = IMPORT.validate_wz_folder(abs_dir)
	assert_false(v.ok, "partial folder")
	assert_true("Npc.wz" in v.missing, "Npc.wz is required (job instructors)")
	assert_false("Map.wz" in v.missing)
	assert_true(String(v.message).begins_with("Missing: "))
	_touch(IMPORT.REQUIRED)
	v = IMPORT.validate_wz_folder(abs_dir.replace("/", "\\") + "\\")
	assert_true(v.ok, "all files, Windows separators and a trailing slash: %s" % v.message)
	assert_eq((v.missing as PackedStringArray).size(), 0)


func test_required_files_match_the_pipeline_doc() -> void:
	# The repo root is above game/ (or above _scratch/godot_runs/<name>/game in an ISOLATE mirror).
	var doc := ""
	for up: String in ["..", "../../../.."]:
		var p := ProjectSettings.globalize_path("res://").path_join(up).path_join("docs/ASSET_PIPELINE.md").simplify_path()
		if FileAccess.file_exists(p):
			doc = FileAccess.get_file_as_string(p)
			break
	if doc == "":
		skip("docs/ASSET_PIPELINE.md not reachable from this project copy")
		return
	for f: String in IMPORT.REQUIRED:
		assert_true(doc.contains(f), "%s listed in ASSET_PIPELINE.md section 1" % f)


func test_importer_command() -> void:
	var args: PackedStringArray = IMPORT.importer_args("C:/v83", "C:/m.json", "C:/cache")
	assert_eq(args, PackedStringArray(["import", "--wz", "C:/v83", "--manifest", "C:/m.json", "--out", "C:/cache"]))
	var c: PackedStringArray = IMPORT.importer_candidates()
	assert_true(c.size() >= 1)
	for p in c:
		assert_true(p.get_file().begins_with("wzimport"), p)
	assert_true(c[c.size() - 1].replace("\\", "/").contains("tools/wzimport/target/release"), "dev build path")


# --- widgets -----------------------------------------------------------------------------------------------------

func test_tiled_frame_math() -> void:
	assert_eq(TiledFrame.center_count(246, 28, 20, 58), 8, "UtilDlgEx: 28 + 8 x 20 + 58 = 246")
	assert_eq(TiledFrame.center_count(247, 28, 20, 58), 9, "rounded up to whole pieces")
	assert_eq(TiledFrame.center_count(50, 28, 20, 58), 0, "never negative")
	assert_eq(TiledFrame.center_count(100, 10, 0, 10), 0, "zero-height centre")
	assert_eq(TiledFrame.frame_height(3, 21, 20, 55), 136.0)


func test_maple_text_wrap_and_ellipsize() -> void:
	var lines := MapleText.wrap("So you want to become a Magician? Choose your path, young one.", 120)
	assert_true(lines.size() >= 2, "wrapped: %s" % lines)
	for l in lines:
		assert_true(MapleText.width(l) <= 120.0 or not l.contains(" "), "line fits: %s" % l)
	assert_eq(" ".join(lines), "So you want to become a Magician? Choose your path, young one.", "no words lost")
	assert_eq(MapleText.wrap("a\nb", 500), PackedStringArray(["a", "b"]), "explicit breaks kept")
	assert_eq(MapleText.wrap("", 100), PackedStringArray([""]))
	var e := MapleText.ellipsize("Improved MaxMP Increase", 60)
	assert_true(e.ends_with("..."), e)
	assert_true(MapleText.width(e) <= 60.0, e)
	assert_eq(MapleText.ellipsize("Snail", 200), "Snail")
	assert_eq(MapleText.font().antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(MapleText.font(), MapleText.font(), "cached")
	assert_eq(MapleText.font(true).font_weight, 700)


func test_wz_button_without_art_keeps_size_and_signals() -> void:
	var b := WzButton.new("UI.wz/Nope.img/BtNothing", "OK")
	_nodes.append(b)
	assert_false(b.has_art())
	assert_eq(b.size, b.fallback_size)
	var hits: Array = []
	b.pressed.connect(func() -> void: hits.append(1))
	b.pressed.emit()
	assert_eq(hits.size(), 1)
	b.disabled = true
	assert_eq(b.state_name(), "disabled")
	assert_eq(b.focus_mode, Control.FOCUS_NONE, "no keyboard activation (Space is jump)")


func test_wz_button_and_image_with_cache() -> void:
	if not require_cache():
		return
	var b := WzButton.new("UI.wz/UIWindow.img/UtilDlgEx/BtOK")
	_nodes.append(b)
	assert_true(b.has_art(), "UtilDlgEx/BtOK in the cache")
	assert_eq(b.size, Vector2(46, 18), "normal canvas size")
	assert_eq(b.state_name(), "normal")
	b.key_focused = true
	assert_eq(b.state_name(), "keyFocused")
	var close := WzButton.new("UI.wz/UIWindow.img/UtilDlgEx/BtClose")
	_nodes.append(close)
	assert_eq(close.size, Vector2(85, 18))
	var npc := WzImage.new("Npc.wz/1032001.img/stand")
	_nodes.append(npc)
	assert_true(npc.has_art(), "Grendel's stand animation")
	assert_eq(npc.current_frame().origin, Vector2(38, 150))
	var img := WzImage.new("UI.wz/UIWindow.img/SkillUp/backgrd")
	_nodes.append(img)
	assert_eq(img.custom_minimum_size, LevelUpWindow.ART_SIZE, "the measured SkillUp size")
	assert_eq(UiArt.text("String.wz/Npc.img/1032001/name"), "Grendel the Really Old")
	assert_eq(UiArt.size_of("UI.wz/UIWindow.img/UtilDlgEx/t"), Vector2(JobAdvanceWindow.DLG_W, JobAdvanceWindow.TOP_H))
	assert_eq(UiArt.size_of("UI.wz/UIWindow.img/UtilDlgEx/s").y, JobAdvanceWindow.BOTTOM_H)
	assert_eq(UiArt.size_of("UI.wz/Basic.img/YesNo3/s"), Vector2(PauseMenu.BOX_W, PauseMenu.BOTTOM_H))
	assert_eq(UiArt.size_of("UI.wz/Login.img/WorldSelect/scroll/0/3"), Vector2(513, 401))
	for p: String in ["Skill.wz/100.img/skill/1000001/icon", "Character.wz/PetEquip/01812000.img/info/icon",
			"Item.wz/Consume/0200.img/02000002/info/icon", "Item.wz/Consume/0200.img/02000004/info/icon",
			"Item.wz/Consume/0200.img/02000005/info/icon", UiArt.FALLBACK_ICON]:
		assert_true(UiArt.frame(p) != null, "card icon %s in the cache" % p)


func test_every_card_icon_resolves() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	for c: Dictionary in data.upgrades.cards:
		var icon := String(c.icon)
		assert_ne(icon, "", "%s has an icon" % c.id)
		assert_true(UiArt.frame(icon) != null, "%s icon %s in the cache" % [c.id, icon])


func test_login_backdrop_in_cache() -> void:
	if not require_cache():
		return
	var lib := UiArt.lib()
	assert_true(lib.has_img(LoginBackdrop.MAP_IMG), "UI.wz/MapLogin.img imported (manifest mapimgs)")
	assert_true(lib.has_img("Map.wz/Back/login.img"))
	assert_true(lib.has_img("Map.wz/Obj/login.img"))
	assert_true(UiArt.anim("Map.wz/Obj/login.img/Title/logo/0") != null, "the title logo")
	assert_true(UiArt.frame(LoginBackdrop.FRAME) != null, "Login.img/Common/frame")
	assert_true(lib.sound(LoginBackdrop.BGM) != null, "BgmUI/Title")
