extends TestCase
## The export presets (game/export_presets.cfg): the "Web" preset (spec #130, ADR 0004) is a single-threaded web export
## that bundles exactly what the desktop build bundles, uses the web shell from the repo's web/ folder and is not a PWA
## (no service worker caching the game or the player's data).

const PRESETS_PATH := "res://export_presets.cfg"


func test_web_preset_is_single_threaded_and_matches_desktop_filters() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS_PATH), OK, "export_presets.cfg loads")
	var desktop := _preset(cfg, "Windows Desktop")
	var web := _preset(cfg, "Web")
	assert_ne(desktop, "", "a Windows Desktop preset exists")
	assert_ne(web, "", "a Web preset exists")
	if desktop == "" or web == "":
		return
	assert_eq(cfg.get_value(web, "platform"), "Web")
	for key in ["export_filter", "include_filter", "exclude_filter", "script_export_mode"]:
		assert_eq(cfg.get_value(web, key), cfg.get_value(desktop, key), "Web %s matches desktop" % key)
	var opts := web + ".options"
	assert_eq(cfg.get_value(opts, "variant/thread_support"), false, "single-threaded (no COOP/COEP on Pages)")
	assert_eq(cfg.get_value(opts, "variant/extensions_support"), false, "no GDExtension variant")
	assert_eq(cfg.get_value(opts, "progressive_web_app/enabled"), false, "no PWA service worker")
	var shell := String(cfg.get_value(opts, "html/custom_html_shell", ""))
	assert_eq(shell, "res://../web/index.html", "the shell is the repo's web/index.html")
	assert_true(String(cfg.get_value(web, "export_path", "")).begins_with("export/"), "exports under the ignored export/")


## Section name ("preset.N") of the preset called `name`, or "".
func _preset(cfg: ConfigFile, name: String) -> String:
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and String(cfg.get_value(section, "name", "")) == name:
			return section
	return ""
