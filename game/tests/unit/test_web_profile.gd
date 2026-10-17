extends TestCase
## Web profile in game/ (spec #130, docs/ARCHITECTURE.md 10 "Web profile"): the cache location the web shell writes,
## the bundled fallback font, the web display settings and the hidden desktop-only controls. All checked on desktop
## with WebProfile.forced instead of a web export.

var _cfg := TestCase.test_dir("web_profile_settings.cfg")
var _nodes: Array[Node] = []
var _env_cache := ""
var _env_wz := ""


func before_each() -> void:
	_env_cache = OS.get_environment(AssetCachePaths.CACHE_ENV)
	_env_wz = OS.get_environment(AssetCachePaths.WZ_ENV)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(_cfg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg))


func after_each() -> void:
	WebProfile.forced = -1
	OS.set_environment(AssetCachePaths.CACHE_ENV, _env_cache)
	OS.set_environment(AssetCachePaths.WZ_ENV, _env_wz)
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


# --- cache path ------------------------------------------------------------------------------------------------------

func test_web_cache_root_is_the_user_dir_default() -> void:
	var want := OS.get_user_data_dir().replace("\\", "/").path_join("asset_cache/v83")
	assert_eq(AssetCachePaths.cache_root_for(true, "/env/cache", "/settings/cache", OS.get_user_data_dir()), want,
		"web ignores the env var and cache_dir")
	assert_eq(AssetCachePaths.cache_root_for(true, "", "", "/userfs/MapleSurvivors"),
		"/userfs/MapleSurvivors/asset_cache/v83", "the path the web shell writes (IDBFS /userfs)")


func test_desktop_cache_root_keeps_its_order() -> void:
	assert_eq(AssetCachePaths.cache_root_for(false, "C:\\env", "/settings", "/u"), "C:/env", "env first")
	assert_eq(AssetCachePaths.cache_root_for(false, "", "/settings/", "/u"), "/settings", "then cache_dir")
	assert_eq(AssetCachePaths.cache_root_for(false, "", "", "/u"), "/u/asset_cache/v83")


func test_resolve_uses_the_web_rule_when_web() -> void:
	OS.set_environment(AssetCachePaths.CACHE_ENV, "/somewhere/else")
	OS.set_environment(AssetCachePaths.WZ_ENV, "/wz")
	assert_eq(AssetCachePaths.resolve_cache_root(), "/somewhere/else", "desktop honours the env var")
	assert_eq(AssetCachePaths.resolve_wz_root(), "/wz")
	WebProfile.forced = 1
	assert_eq(AssetCachePaths.resolve_cache_root(),
		OS.get_user_data_dir().replace("\\", "/").path_join("asset_cache/v83"))
	assert_eq(AssetCachePaths.resolve_wz_root(), "", "web has no WZ folder")


# --- fonts -----------------------------------------------------------------------------------------------------------

const NOPE := ["NoSuchFont_for_tests"]


func _width(f: Font, bold_size: int = 12) -> Vector2:
	return f.get_string_size("Hello World", HORIZONTAL_ALIGNMENT_LEFT, -1, bold_size)


func test_arimo_fonts_load_with_arial_metrics() -> void:
	var regular := MapleFonts.arimo(400)
	var bold := MapleFonts.arimo(700)
	assert_true(regular != null and bold != null, "bundled Arimo loads")
	var w := _width(regular).x
	var wb := _width(bold).x
	# Arial's advances at 12 px for 'Hello World' add up to about 62 (Arimo is metric compatible with Arial).
	assert_near(w, 62.0, 2.0, "Arial-like metrics")
	assert_true(wb > w, "bold is wider than regular (%f vs %f)" % [wb, w])


func test_no_system_font_means_arimo_itself() -> void:
	# A SystemFont with no match would draw with the engine's built-in font and ignore its fallbacks (checked: same
	# size as ThemeDB.fallback_font), so the browser build, which has no system fonts, must get Arimo directly.
	var f := MapleFonts.make(PackedStringArray(NOPE), 400)
	assert_false(f is SystemFont, "no system match -> not a SystemFont")
	assert_eq(_width(f), _width(MapleFonts.arimo(400)))
	var b := MapleFonts.make(PackedStringArray(NOPE), 700)
	assert_eq(_width(b), _width(MapleFonts.arimo(700)), "bold too")
	assert_ne(_width(f), _width(ThemeDB.fallback_font), "not the engine's built-in font")


func test_system_match_keeps_the_system_font_with_arimo_behind_it() -> void:
	var f := MapleFonts.make_with(PackedStringArray(["Arial", "Tahoma"]), 700, true)
	assert_true(f is SystemFont, "a system font was found -> SystemFont")
	var s := f as SystemFont
	assert_eq(s.font_names, PackedStringArray(["Arial", "Tahoma"]))
	assert_eq(s.font_weight, 700)
	assert_eq(s.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(s.fallbacks.size(), 1, "Arimo as the glyph fallback")


func test_game_fonts_ask_for_system_names_first() -> void:
	# On desktop (Arial present) MapleText/HUD fonts are SystemFonts as before; where Arial is missing they are Arimo.
	for bold in [false, true]:
		var f := MapleText.font(bold)
		assert_true(f is SystemFont or f is FontVariation)
		if f is SystemFont:
			assert_true("Arial" in (f as SystemFont).font_names)
	for w in [400, 700]:
		var h := HudWidget.make_font(w)
		assert_true(h is SystemFont or h is FontVariation)
		assert_true(_width(h).x > 40.0)
