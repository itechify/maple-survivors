class_name AssetCachePaths
extends RefCounted
## Where the imported v83 asset cache and the player's WZ folder live (docs/ASSET_PIPELINE.md).
##
## Resolution order for the cache root: MAPLE_SURVIVORS_CACHE env var, then `[assets] cache_dir` in
## user://settings.cfg, then <user data dir>/asset_cache/v83 (on Windows %APPDATA%/MapleSurvivors/asset_cache/v83,
## the same folder scripts/import.sh writes to). The WZ root: MAPLE_WZ_ROOT, then `[assets] wz_root`.

const CACHE_ENV := "MAPLE_SURVIVORS_CACHE"
const WZ_ENV := "MAPLE_WZ_ROOT"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SUBDIR := "asset_cache/v83"


## Absolute path of the asset cache root (it may not exist yet).
static func resolve_cache_root() -> String:
	var env := OS.get_environment(CACHE_ENV)
	if env != "":
		return _normalize(env)
	var configured := _setting("cache_dir")
	if configured != "":
		return _normalize(configured)
	return _normalize(OS.get_user_data_dir().path_join(DEFAULT_SUBDIR))


## Absolute path of the player's v83 folder, or "" when not configured.
static func resolve_wz_root() -> String:
	var env := OS.get_environment(WZ_ENV)
	if env != "":
		return _normalize(env)
	return _normalize(_setting("wz_root"))


static func _setting(key: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return String(cfg.get_value("assets", key, ""))


static func _normalize(p: String) -> String:
	return p.replace("\\", "/").rstrip("/")
