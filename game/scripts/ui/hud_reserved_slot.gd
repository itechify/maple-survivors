class_name HudReservedSlot
extends Control
## A separately fed HUD position for the upcoming potion, buff and boss widgets.

var player_state: Dictionary = {}
var run_info: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Receives the current state even while the reserved slot has no content.
func update(ps: Dictionary, info: Dictionary) -> void:
	player_state = ps
	run_info = info
	queue_redraw()
