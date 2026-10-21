extends SceneTree
## Headless child process for real filesystem ownership tests. Only the explicitly supplied scratch path is touched.

var save: SaveData


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(2)
		return
	save = SaveData.new(args[0], true)
	if args[1] == "write":
		print("SAVE_WRITER_RESULT=%d" % save.set_account({"nx": 999, "owned": []}))
		quit(0)
		return
	if args.size() != 3 or save.writer_error != OK:
		quit(3)
		return
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		quit(4)
		return
	file.store_string("ready")
	file.close()
	OS.delay_msec(30000) # Bounded child lifetime even if the parent test aborts before killing it.
	quit(0)
