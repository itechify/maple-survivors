extends "res://tools/playtest/brain_link.gd"
## The brain link over the decision protocol (playtest_protocol.gd): writes each message as one "@@PT " stdout line
## and, for a decide, blocks until one answer line arrives on stdin. On stdin EOF it logs "brain lost", sets `lost`
## and stops asking; the driver then finishes the round on its baseline. Tool code only.

const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")

var _write: Callable
var _read: Callable


## `write(line)` / `read() -> line` default to stdout print and a blocking stdin read (tests inject fakes).
func _init(write := Callable(), read := Callable()) -> void:
	mode = "stdio"
	_write = write if write.is_valid() else func(line: String) -> void: print(line)
	_read = read if read.is_valid() else func() -> String: return OS.read_string_from_stdin(PROTOCOL.READ_BUFFER)


func ask(decide: Dictionary) -> Dictionary:
	if lost:
		return {"error": "brain lost"}
	_write.call(PROTOCOL.encode(decide))
	var line: String = _read.call()
	if line.strip_edges() == "":
		lost = true
		_write.call("playtest_driver: brain lost (stdin closed); finishing the round on the builtin baseline")
		return {"error": "brain lost"}
	var answer := PROTOCOL.parse_answer(line)
	if not answer.has("error") and int(answer.id) != int(decide.id):
		return {"error": "answer id %d for decide %d" % [int(answer.id), int(decide.id)]}
	return answer


func send(msg: Dictionary) -> void:
	_write.call(PROTOCOL.encode(msg))
