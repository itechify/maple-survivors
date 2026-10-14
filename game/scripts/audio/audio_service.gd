class_name AudioService
extends Node
## Background music and pooled sound effects from the asset cache (autoload "Sfx"; docs/ARCHITECTURE.md 4.2).
##
## Paths are WZ paths of Sound_DX8 nodes: `play_bgm("Sound.wz/Bgm01.img/CavaBien")` (or a map's info/bgm value
## "Bgm01/CavaBien"), `play("Sound.wz/Game.img/PickUpItem")`. BGM loops and cross-fades; SFX use a fixed pool of
## players (MAX_VOICES; the oldest voice is stolen when all are busy). Volumes come from the "Settings" autoload
## (master x bgm / master x sfx, linear) and are applied to the "BGM" and "SFX" buses, created on first use.

## Simultaneous one-shot voices.
const MAX_VOICES := 16
## Default BGM fade time in seconds. tier C: ours.
const DEFAULT_FADE := 0.8
const BGM_BUS := "BGM"
const SFX_BUS := "SFX"

## Source of sounds; defaults to the "Assets" autoload.
var library: AssetLibrary

## WZ path of the current BGM ("" when silent).
var current_bgm := ""

var _bgm: Array[AudioStreamPlayer] = []
var _bgm_active := 0
var _fade_t := 0.0
var _fade_len := 0.0
var _voices: Array[AudioStreamPlayer] = []
var _voice_started: PackedInt64Array = []
var _play_seq := 0


func _ready() -> void:
	_ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BGM_BUS
		p.volume_db = -80.0
		add_child(p)
		_bgm.append(p)
	for i in MAX_VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = SFX_BUS
		add_child(v)
		_voices.append(v)
	_voice_started.resize(MAX_VOICES)
	var settings := _settings()
	if settings != null:
		settings.changed.connect(apply_volumes)
	apply_volumes()
	set_process(false)


## Starts (or keeps playing) a looping BGM with a cross-fade. Accepts a WZ path or a map "BgmXX/Name" value.
func play_bgm(path: String, fade: float = DEFAULT_FADE) -> bool:
	if not path.contains(".img/") and path.contains("/"):
		path = AssetLibrary.bgm_path(path)
	if path == current_bgm and _bgm[_bgm_active].playing:
		return true
	var stream := _lib().sound(path) if _lib() != null else null
	if stream == null:
		return false
	stream = stream.duplicate()
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)
	_bgm_active = 1 - _bgm_active
	var p := _bgm[_bgm_active]
	p.stream = stream
	p.volume_db = -80.0 if fade > 0.0 else 0.0
	p.play()
	current_bgm = path
	_start_fade(fade)
	return true


## Fades the BGM out and stops it.
func stop_bgm(fade: float = DEFAULT_FADE) -> void:
	current_bgm = ""
	_bgm_active = 1 - _bgm_active
	_bgm[_bgm_active].stop()
	_start_fade(fade)


## Plays a one-shot sound at `volume` (linear 0..1, times the SFX volume). Returns false when it is not in the cache.
func play(path: String, volume: float = 1.0) -> bool:
	var stream := _lib().sound(path) if _lib() != null else null
	if stream == null or _voices.is_empty():
		return false
	var busy := PackedByteArray()
	busy.resize(_voices.size())
	for i in _voices.size():
		busy[i] = 1 if _voices[i].playing else 0
	var best := pick_voice(busy, _voice_started)
	var v := _voices[best]
	v.stream = stream
	v.volume_db = linear_to_db(maxf(volume, 0.0001))
	_play_seq += 1
	_voice_started[best] = _play_seq
	v.play()
	return true


## The voice to use: the first idle one, else the one started longest ago (`started` = play sequence numbers).
static func pick_voice(busy: PackedByteArray, started: PackedInt64Array) -> int:
	var best := 0
	var oldest := 9223372036854775807
	for i in busy.size():
		if busy[i] == 0:
			return i
		if started[i] < oldest:
			oldest = started[i]
			best = i
	return best


## True while the current BGM player is playing.
func bgm_playing() -> bool:
	return not _bgm.is_empty() and _bgm[_bgm_active].playing


## Playback position (s) of the current BGM.
func bgm_position() -> float:
	return _bgm[_bgm_active].get_playback_position() if bgm_playing() else 0.0


## Number of SFX voices currently playing.
func voices_playing() -> int:
	var n := 0
	for v in _voices:
		if v.playing:
			n += 1
	return n


## Re-applies master/bgm/sfx volumes from Settings to the buses.
func apply_volumes() -> void:
	_ensure_buses()
	var s := _settings()
	var mv := s.master_volume if s != null else 1.0
	var bgm := s.bgm_volume if s != null else 0.8
	var sfx := s.sfx_volume if s != null else 0.9
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BGM_BUS), linear_to_db(maxf(mv * bgm, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(maxf(mv * sfx, 0.0001)))


func _process(delta: float) -> void:
	_fade_t += delta
	var k := 1.0 if _fade_len <= 0.0 else clampf(_fade_t / _fade_len, 0.0, 1.0)
	var incoming := _bgm[_bgm_active]
	var outgoing := _bgm[1 - _bgm_active]
	if incoming.playing:
		incoming.volume_db = linear_to_db(maxf(k, 0.0001))
	if outgoing.playing:
		outgoing.volume_db = linear_to_db(maxf(1.0 - k, 0.0001))
	if k >= 1.0:
		outgoing.stop()
		set_process(false)


func _start_fade(fade: float) -> void:
	_fade_t = 0.0
	_fade_len = maxf(fade, 0.0)
	set_process(true)
	if _fade_len <= 0.0:
		_process(0.0)


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library


func _settings() -> GameSettings:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Settings") as GameSettings


static func _ensure_buses() -> void:
	for bus_name in [BGM_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
