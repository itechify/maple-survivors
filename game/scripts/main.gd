extends Node
## Bootstrap scene. Phase 1 replaces this with the scene flow of docs/ARCHITECTURE.md section 4.1.


func _ready() -> void:
	print("Maple Survivors: cache root = ", AssetCachePaths.resolve_cache_root())
