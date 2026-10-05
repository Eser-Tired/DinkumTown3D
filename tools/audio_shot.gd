extends Node
## 音效试听导出 —— 把运行时合成的短音效写成 wav，用播放器直接听
##
## 用法：
##   Godot --headless --path . --scene res://tools/audio_shot.tscn -- --dir res://_audio_preview/
##
## 【为什么要这个工具】音效是代码算出来的 PCM，改完既没法"看"也没法在自检里断言
## （断言只能证明它非静音，证明不了好不好听）。导出成 wav 才能真的验收，
## 也才能和旧版 A/B 对比。目前导出：脚步 4 个变体 + 旧版脚步 1 个（对照用）。

const AudioS := preload("res://scripts/audio.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := _arg_str(args, "--dir", "res://_audio_preview/")
	# save_to_wav 对不存在的目录是【静默失败】的：不报错也不落文件
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var a: Node = AudioS.new()
	a.rng.seed = 20260921       # 固定种子：导出的变体每次一样，方便对比
	add_child(a)

	for i in 4:
		var v: AudioStreamWAV = a._syn_step()
		print("new_step_%d  %s" % [i + 1, _stats(v)])
		_save(v, abs_dir.path_join("step_new_%d.wav" % (i + 1)))

	var old := _step_old(a)
	print("old_step    %s" % _stats(old))
	_save(old, abs_dir.path_join("step_old.wav"))

	print("==== AUDIO SHOT DONE dir=%s ====" % abs_dir)
	get_tree().quit(0)


## 旧版脚步音效 —— 只用于 A/B 对比，游戏里已经不再使用。
## 原文是"沙砾噪声 + 78Hz 闷响"的 0.11 秒长尾摩擦声。
func _step_old(a: Node) -> AudioStreamWAV:
	var sr: int = AudioS.SR_HI
	var n: int = int(float(sr) * 0.11)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var ph := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var w: float = a.rng.randf_range(-1.0, 1.0)
		lp += 0.22 * (w - lp)
		var grit: float = w - lp
		ph += TAU * (78.0 + 26.0 * exp(-t * 30.0)) / float(sr)
		var thud: float = sin(ph) * exp(-t * 30.0) * 0.75
		buf[i] = (grit * 0.55 + thud) * exp(-t * 22.0)
		i += 1
	return a._make_stream(a._norm(buf, 0.80), sr, false, false)


## 时长 / 峰值 / 过零率（整段 + 前 1/3 段）。
## 过零率是个粗糙的"亮度"指标：噪声成分越多、频率越高，过零越频繁，听起来越"脆"。
## 【为什么要分段】只看整段会被低频闷响稀释——旧版整段 2190、新版曾只有 53，
## 但那 53 里到底还有没有噪声段看不出来。前 1/3 段的过零率才反映"起手那一下有多脆"。
func _stats(s: AudioStreamWAV) -> String:
	var d: PackedByteArray = s.data
	var count := d.size() / 2
	if count <= 0:
		return "空"
	var peak := 0.0
	var sq := 0.0
	var zc := 0
	var zc_head := 0
	var head := count / 3
	var prev := 0.0
	var i := 0
	while i < count:
		var v := float(d.decode_s16(i * 2)) / 32768.0
		peak = maxf(peak, absf(v))
		sq += v * v
		if (v >= 0.0) != (prev >= 0.0):
			zc += 1
			if i < head:
				zc_head += 1
		prev = v
		i += 1
	var dur := float(count) / float(s.mix_rate)
	return "时长=%.3fs 峰值=%.2f RMS=%.3f 过零=%d(前段%d)" % [dur, peak, sqrt(sq / float(count)), zc, zc_head]


func _save(s: AudioStreamWAV, path: String) -> void:
	var e: int = s.save_to_wav(path)
	if e != OK:
		print("FAIL 写出 %s 失败 err=%d" % [path, e])


func _arg_str(args: PackedStringArray, key: String, def: String) -> String:
	var i: int = args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def
