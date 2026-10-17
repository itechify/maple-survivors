class_name HudMessages
extends HudWidget
## Transient system messages above the status bar, plus a persistent cue while a skill waits for MP.

var _messages: Array[Dictionary] = []
var _notices: Array[Dictionary] = []

func _draw() -> void:
	var origin := bar_origin(get_viewport_rect().size)
	_draw_messages(origin)
	# tier C: encounter notices sit one line above the low-MP cue, independently of the six EXP lines.
	var y := origin.y - MSG_INSET.y - (MSG_MAX + 1) * MSG_LINE
	for notice: Dictionary in _notices:
		var alpha := clampf((float(notice.life) - float(notice.age)) / MSG_FADE, 0.0, 1.0)
		var color: Color = notice.color
		color.a *= alpha
		_text(Vector2(origin.x + MSG_INSET.x, y), notice.text, color, FONT_SIZE, null, alpha)
		y -= MSG_LINE
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
	queue_redraw()


## Shows "+N EXP" (GAME_DESIGN section 5); nothing for n <= 0.

func show_exp(n: int) -> void:
	if n > 0:
		push_message("+%d EXP" % n)


## Shows the v83 meso pickup notice (tier B: client string pool entry 0x12F); nothing for n <= 0.
func show_mesos(n: int) -> void:
	if n > 0:
		push_message("You have gained mesos (+%d)" % n)


## Shows the v83 item pickup notice for equipment, "You have gained an item (Wooden Wand)" (tier B: v83 client string
## pool, open client reimplementations); without a name just "You have gained an item".
func show_item_gain(item_name: String) -> void:
	push_message("You have gained an item (%s)" % item_name if item_name != "" else "You have gained an item")


## Shows the v83 full-inventory notice when a drop cannot be picked up (tier B: v83 client string pool).
func show_inventory_full() -> void:
	push_message("You can't get anymore items.")


## Keeps a timed encounter notice outside the EXP queue; the same encounter replaces its previous notice.
func push_notice(key: String, text: String, life: float = MSG_LIFE) -> void:
	_notices = _notices.filter(func(n: Dictionary) -> bool: return n.key != key)
	_notices.append({"key": key, "text": text, "color": SYSTEM_YELLOW, "age": 0.0, "life": life})
	queue_redraw()


## The message lines on screen, oldest first: [{"text", "color", "alpha"}].

func messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _messages:
		out.append({"text": m.text, "color": m.color, "alpha": message_alpha(float(m.age))})
	for n in _notices:
		out.append({"text": n.text, "color": n.color,
			"alpha": clampf((float(n.life) - float(n.age)) / MSG_FADE, 0.0, 1.0)})
	return out


## Ages and removes expired message lines.

func advance_messages(dt: float) -> void:
	if _messages.is_empty() and _notices.is_empty():
		return
	for m in _messages:
		m.age = float(m.age) + dt
	while not _messages.is_empty() and float(_messages[0].age) >= MSG_LIFE:
		_messages.pop_front()
	for notice in _notices:
		notice.age = float(notice.age) + dt
	_notices = _notices.filter(func(n: Dictionary) -> bool: return float(n.age) < float(n.life))
	queue_redraw()

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
