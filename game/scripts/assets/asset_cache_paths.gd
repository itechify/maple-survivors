class_name AssetCachePaths
extends RefCounted
## Where the imported v83 asset cache and the player's WZ folder live (docs/ASSET_PIPELINE.md).
##
## Resolution order for the cache root: MAPLE_SURVIVORS_CACHE env var, then `[assets] cache_dir` in
## user://settings.cfg, then <user data dir>/asset_cache/v83 (on Windows %APPDATA%/MapleSurvivors/asset_cache/v83,
## the same folder scripts/import.sh writes to). The WZ root: MAPLE_WZ_ROOT, then `[assets] wz_root`.
## Web build (WebProfile.is_web): the cache is always <user data dir>/asset_cache/v83 (`/userfs/MapleSurvivors/...`,
## where the web shell writes it) and there is no WZ root: the env var and both settings are skipped.

const CACHE_ENV := "MAPLE_SURVIVORS_CACHE"
const WZ_ENV := "MAPLE_WZ_ROOT"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SUBDIR := "asset_cache/v83"


## Absolute path of the asset cache root (it may not exist yet).
static func resolve_cache_root() -> String:
	var web := WebProfile.is_web()
	return cache_root_for(web, "" if web else OS.get_environment(CACHE_ENV), "" if web else _setting("cache_dir"),
		OS.get_user_data_dir())


## The cache root for already gathered inputs (the pure rule behind resolve_cache_root): web = the user dir default
## only; desktop = env var, then the configured cache_dir, then the user dir default.
static func cache_root_for(web: bool, env: String, configured: String, user_dir: String) -> String:
	if not web:
		if env != "":
			return _normalize(env)
		if configured != "":
			return _normalize(configured)
	return _normalize(user_dir.path_join(DEFAULT_SUBDIR))


## Absolute path of the player's v83 folder, or "" when not configured (always "" on web).
static func resolve_wz_root() -> String:
	if WebProfile.is_web():
		return ""
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
