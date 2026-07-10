class_name JuiceAudio
extends Node
# Synthesized cues rendered into AudioStreamWAV buffers at startup — no
# asset files, fully reproducible (the two-top generate_audio.py idea,
# moved in-process). Strictly cosmetic: nothing here touches the sim.

const RATE := 22050
var streams := {}
var players: Array = []
var muted := false

func _ready() -> void:
	_gen_all()
	for i in range(8):
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

func play(name: String) -> void:
	if muted or not streams.has(name):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.play()
			return
	players[0].stream = streams[name]
	players[0].play()

func _gen_all() -> void:
	streams["jump"] = _cue([[300.0, 520.0, 0.09, "square", 0.30, 0.0]])
	streams["land"] = _cue([[120.0, 80.0, 0.06, "tri", 0.35, 0.0]])
	streams["cushion"] = _cue([[200.0, 720.0, 0.16, "square", 0.35, 0.0]])
	streams["place"] = _cue([[900.0, 700.0, 0.05, "square", 0.25, 0.0]])
	streams["rotate"] = _cue([[500.0, 640.0, 0.05, "square", 0.20, 0.0]])
	streams["tick"] = _cue([[660.0, 660.0, 0.05, "square", 0.25, 0.0]])
	streams["go"] = _cue([[520.0, 780.0, 0.14, "square", 0.35, 0.0]])
	streams["die"] = _cue([[240.0, 50.0, 0.30, "fan", 0.45, 0.0], [0.0, 0.0, 0.22, "noise", 0.30, 0.0]])
	streams["swat"] = _cue([[660.0, 660.0, 0.07, "square", 0.35, 0.0], [990.0, 990.0, 0.10, "square", 0.35, 0.08]])
	streams["finish"] = _cue([[523.0, 523.0, 0.10, "square", 0.30, 0.0], [659.0, 659.0, 0.10, "square", 0.30, 0.08], [784.0, 784.0, 0.10, "square", 0.30, 0.16]])
	streams["too_easy"] = _cue([[330.0, 300.0, 0.18, "tri", 0.35, 0.0], [260.0, 230.0, 0.26, "tri", 0.35, 0.16]])
	streams["win"] = _cue([[523.0, 523.0, 0.12, "square", 0.30, 0.0], [659.0, 659.0, 0.12, "square", 0.30, 0.10], [784.0, 784.0, 0.12, "square", 0.30, 0.20], [1046.0, 1046.0, 0.12, "square", 0.30, 0.30], [784.0, 784.0, 0.12, "square", 0.30, 0.40], [1046.0, 1046.0, 0.16, "square", 0.30, 0.50]])
	streams["lose"] = _cue([[392.0, 369.0, 0.20, "fan", 0.30, 0.0], [330.0, 310.0, 0.20, "fan", 0.30, 0.16], [262.0, 246.0, 0.20, "fan", 0.30, 0.32], [196.0, 184.0, 0.26, "fan", 0.30, 0.48]])
	streams["ui"] = _cue([[800.0, 800.0, 0.04, "square", 0.20, 0.0]])

func _cue(segs: Array) -> AudioStreamWAV:
	var total := 0.0
	for s in segs:
		total = maxf(total, s[5] + s[2])
	var n := int(total * RATE) + 32
	var mix := PackedFloat32Array()
	mix.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for s in segs:
		var f0: float = s[0]
		var f1: float = maxf(s[1], 1.0)
		var dur: float = s[2]
		var kind: String = s[3]
		var vol: float = s[4]
		var at := int(s[5] * RATE)
		var seg_n := int(dur * RATE)
		var phase := 0.0
		for i in range(seg_n):
			var tt := float(i) / seg_n
			var f := f0 * pow(f1 / maxf(f0, 1.0), tt)
			phase += f / RATE
			var v := 0.0
			match kind:
				"square":
					v = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				"fan":
					v = fmod(phase, 1.0) * 2.0 - 1.0
				"tri":
					v = absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
				"noise":
					v = rng.randf_range(-1.0, 1.0)
			var env := minf(1.0, i / (0.002 * RATE)) * (1.0 - tt)
			if at + i < n:
				mix[at + i] += v * vol * env
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var q := int(clampf(mix[i], -1.0, 1.0) * 32000.0)
		data[i * 2] = q & 0xFF
		data[i * 2 + 1] = (q >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
