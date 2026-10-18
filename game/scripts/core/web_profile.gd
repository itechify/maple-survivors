class_name WebProfile
extends RefCounted
## Whether the game runs as the browser build (Godot's "web" feature; docs/ARCHITECTURE.md 10 "Web profile").
## Every web-only branch asks here, so unit tests can flip it with `forced` instead of needing a web export.

## -1 = ask the engine, 0 = pretend desktop, 1 = pretend web (tests only).
static var forced := -1


## True in the web export (or when a test forced it).
static func is_web() -> bool:
	if forced >= 0:
		return forced == 1
	return OS.has_feature("web")
