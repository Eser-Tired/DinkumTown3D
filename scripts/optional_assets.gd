extends RefCounted
## 授权美术只在本地安装；缺包的源码检出仍能使用程序化外观运行与验收。

const DIRECTORY := "res://local_assets/emace/"
static var _scenes: Dictionary = {}


static func instantiate(kind: String) -> Node3D:
	if not kind in ["hut", "crate"] or OS.get_cmdline_user_args().has("--no-emace"):
		return null
	var path := DIRECTORY + kind + ".scn"
	if not ResourceLoader.exists(path):
		return null
	if not _scenes.has(kind):
		var scene := load(path) as PackedScene
		if scene == null:
			return null
		_scenes[kind] = scene
	return _scenes[kind].instantiate() as Node3D
