class_name ScriptErrorGuard
extends Logger
## Records the GDScript runtime errors raised while it is attached.
##
## In Godot 4.7 a runtime error does not stop the program: it aborts only the current function, which returns its
## default value, and the caller carries on. A test that errors before recording a failure would therefore "pass".
## The test runner attaches this guard around every test and turns recorded script errors into failures.
## Only ERROR_TYPE_SCRIPT counts; engine errors (push_error, ERR_FAIL_* in built-ins) do not abort GDScript.

var _mutex := Mutex.new()
var _errors: PackedStringArray = []
var _attached := false


func attach() -> void:
	if _attached:
		return
	_attached = true
	OS.add_logger(self)


func detach() -> void:
	if not _attached:
		return
	_attached = false
	OS.remove_logger(self)


## The recorded script errors, one line each: "<file>:<line> in <function>: <message>".
func errors() -> PackedStringArray:
	_mutex.lock()
	var out := _errors.duplicate()
	_mutex.unlock()
	return out


func clear() -> void:
	_mutex.lock()
	_errors.clear()
	_mutex.unlock()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != Logger.ERROR_TYPE_SCRIPT:
		return
	var message := code if rationale == "" else "%s (%s)" % [code, rationale]
	_mutex.lock()
	_errors.append("%s:%d in %s: %s" % [file, line, function, message])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
