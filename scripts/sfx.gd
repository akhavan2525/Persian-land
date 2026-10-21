extends Node
## Sound effects and voice lines. `Sfx.play("sword")` picks a random variant (sword_0, sword_1...),
## `Sfx.play_at("sword", pos)` makes it quieter the farther it is from the camera.

const DIR := "res://assets/sfx/"
const VOICE_DIR := "res://assets/voice/"
const POOL := 18

var listener: Node3D = null       # the camera rig; set by the world
var muted := false
var _streams := {}                # base name -> [AudioStream]
var _players: Array[AudioStreamPlayer] = []
var _last := {}                   # base name -> time last played
var _voice: AudioStreamPlayer
var _voices := {}                 # voice line name -> [AudioStream] (select_0, select_1... become "select")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = 2.0
	add_child(_voice)
	_load_dir(DIR, ".wav", _streams)
	_load_dir(VOICE_DIR, ".ogg", _voices)


## Groups numbered variants: sword_0, sword_1 -> "sword".
func _load_dir(dir: String, ext: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.ends_with(ext):
			continue
		var name := f.get_basename()
		var base := name
		var parts := name.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			base = parts[0]
		if not into.has(base):
			into[base] = []
		var s = load(dir + f)
		if s and not into[base].has(s):
			into[base].append(s)


func play(name: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if muted or not _streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -10.0)) < 0.06:
		return     # a dozen clashes in the same frame only need one sound
	_last[name] = now
	var p := _free_player()
	if p == null:
		return
	var list: Array = _streams[name]
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Battle sounds fade with distance from the camera and stay silent far off screen.
func play_at(name: String, pos: Vector3, volume_db := 0.0) -> void:
	if listener == null or not is_instance_valid(listener):
		play(name, volume_db)
		return
	var d := Vector2(pos.x - listener.global_position.x, pos.z - listener.global_position.z).length()
	if d > 70.0:
		return
	play(name, volume_db - d * 0.35)


## Persian voice lines (assets/voice/<name>_N.ogg), one at a time. An urgent line
## (a power, an attack on the keep, the end of the war) cuts off unit chatter.
func voice(name: String, urgent := false) -> void:
	if muted or not _voices.has(name):
		return
	if _voice.playing and not urgent:
		return
	var list: Array = _voices[name]
	var pick: AudioStream = list[randi() % list.size()]
	if list.size() > 1 and pick == _voice.stream:
		pick = list[(list.find(pick) + 1) % list.size()]   # do not repeat the same line twice in a row
	_voice.stream = pick
	_voice.play()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null
