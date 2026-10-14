extends SceneTree
## Writes the Godot Engine licence notices that must travel with an exported build (scripts/export.sh): the engine's
## MIT licence text, the copyright of every bundled third-party component and the full text of each licence they use,
## all taken from the running engine itself (Engine.get_license_text / get_copyright_info / get_license_info).
##
##   godot --headless --path game --script res://tools/write_licenses.gd -- <abs output file>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("write_licenses: give the output file")
		quit(2)
		return
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		print("write_licenses: cannot write %s" % args[0])
		quit(1)
		return
	f.store_string(notices())
	f.close()
	print("write_licenses: wrote %s" % args[0])
	quit()


## The whole notices text: Godot's licence, then each component's copyright lines, then the licence texts.
static func notices() -> String:
	var v := Engine.get_version_info()
	var out := PackedStringArray()
	out.append("Maple Survivors is built with the Godot Engine %s (https://godotengine.org)." % String(v.get("string", "")))
	out.append("")
	out.append("== Godot Engine licence ==")
	out.append("")
	out.append(Engine.get_license_text())
	out.append("")
	out.append("== Third-party components bundled in the Godot Engine ==")
	for c: Dictionary in Engine.get_copyright_info():
		out.append("")
		out.append("Component: %s" % String(c.get("name", "")))
		for part: Dictionary in c.get("parts", []):
			for line: String in part.get("copyright", []):
				out.append("  Copyright: %s" % line)
			out.append("  License: %s" % String(part.get("license", "")))
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	out.append("")
	out.append("== Licence texts ==")
	for n: String in names:
		out.append("")
		out.append("License: %s" % n)
		out.append("")
		out.append(String(licenses[n]))
	return "\n".join(out) + "\n"
