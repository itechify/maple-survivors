class_name HudMessages
extends HudWidget
## Transient system messages above the status bar, plus a persistent cue while a skill waits for MP.

var _messages: Array[Dictionary] = []

func _draw() -> void:
	var origin := bar_origin(get_viewport_rect().size)
	_draw_messages(origin)
	if low_mp_visible():
		# tier C: low-MP cue above the six-line EXP message area, in warm red with the standard text outline.
		_text(origin + Vector2(MSG_INSET.x, -MSG_INSET.y - MSG_MAX * MSG_LINE), "Not enough MP", Color8(255, 112, 96))


## Whether the persistent low-MP cue is visible in the current run snapshot.
func low_mp_visible() -> bool:
	return bool(player_state.get("mp_short", false))

## Adds a system message, evicting the oldest when the message area is full.
func push_message(text: String, color: Color = SYSTEM_YELLOW) -> void:
	_messages.append({"text": text, "color": color, "age": 0.0})
	while _messages.size() > MSG_MAX:
		_messages.pop_front()
	if _canvas != null:
		_canvas.queue_redraw()


## Shows "+N EXP" (GAME_DESIGN section 5); nothing for n <= 0.

func show_exp(n: int) -> void:
	if n > 0:
		push_message("+%d EXP" % n)


## The message lines on screen, oldest first: [{"text", "color", "alpha"}].

func messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _messages:
		out.append({"text": m.text, "color": m.color, "alpha": message_alpha(float(m.age))})
	return out


## Ages and removes expired message lines.

func advance_messages(dt: float) -> void:
	if _messages.is_empty():
		return
	for m in _messages:
		m.age = float(m.age) + dt
	while not _messages.is_empty() and float(_messages[0].age) >= MSG_LIFE:
		_messages.pop_front()
	if _canvas != null:
		_canvas.queue_redraw()

func _process(delta: float) -> void:
	advance_messages(delta)


func _draw_messages(o: Vector2) -> void:
	var y := o.y - MSG_INSET.y
	for i in range(_messages.size() - 1, -1, -1):
		var m: Dictionary = _messages[i]
		var a := message_alpha(float(m.age))
		var c: Color = m.color
		c.a *= a
		_text(Vector2(o.x + MSG_INSET.x, y), str(m.text), c, FONT_SIZE, null, a)
		y -= MSG_LINE
