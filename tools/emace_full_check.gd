extends Node
## 完整素材目录、共享资源、采集身份与家具碰撞验收；缺包时执行同样的玩法断言。

const Assets := preload("res://scripts/optional_assets.gd")
const FloraS := preload("res://scripts/flora.gd")
const PropsS := preload("res://scripts/props.gd")
const CollisionS := preload("res://scripts/world_collision.gd")
var checks := 0
var fails := 0


func _ok(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		fails += 1
	print(("PASS " if condition else "FAIL ") + description)


func _ready() -> void:
	var started := Time.get_ticks_usec()
	var probe := Assets.instantiate("hut")
	var installed := probe != null
	if probe != null:
		probe.free()
	var triangles := 0
	if installed:
		for kind in Assets.KINDS:
			var model := Assets.instantiate(kind)
			_ok(model != null and ResourceLoader.get_dependencies(Assets.DIRECTORY + kind + ".scn").is_empty(), kind + "本地自包含模型")
			if model == null:
				continue
			triangles += int(model.get_meta("triangle_count"))
			if not kind in ["hut", "shop", "crate"]:
				var bounds: AABB = model.get_meta("visual_bounds")
				_ok(bounds.size.distance_to(Vector3.ONE) < 0.0001 and bounds.get_center().length() < 0.001, kind + "归一化包围盒（精度0.1毫米）")
			model.free()
		for texture in ["ground_grass", "ground_earth", "ground_normal"]:
			_ok(Assets.texture(texture) != null, texture + "地面贴图可加载")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var native_radii := [0.95, 0.7, 0.0, 1.1, 1.1, 0.0]
	var nodes := [FloraS.make_eucalyptus(rng), FloraS.make_acacia(rng), FloraS.make_bush(rng), FloraS.make_rock(rng), FloraS.make_rock(rng, 1.0, true), FloraS.make_stump()]
	print("FLORA_RNG_STATE=%d" % rng.state)
	for i in nodes.size():
		var node: Node3D = nodes[i]
		_ok(node.find_children("AssetVisual*", "Node3D", true, false).size() > 0 if installed else node.find_children("AssetVisual*", "Node3D", true, false).is_empty(), "自然物%d外观切换" % i)
		_ok(is_equal_approx(float(node.get_meta("collide_radius")), native_radii[i]), "自然物%d占地不变" % i)
		node.free()
	var fence := PropsS.make_fence(4.6)
	CollisionS.attach(fence)
	_ok(fence.get_node("Solid").get_child_count() == 5, "围栏沿用三根柱和两条横梁碰撞，没有重复模型碰撞")
	fence.free()
	var preview := PropsS.make_fence(4.6)
	_ok(preview.find_children("*", "CollisionObject3D", true, false).is_empty(), "建造预览只有外观")
	preview.free()
	var main: Node3D = load("res://scripts/main.gd").new()
	main.forced_map_seed = 20260921
	add_child(main)
	var fingerprint := ""
	for resource in main.resources:
		fingerprint += "%s:%d:%s;" % [resource.get_meta("resource"), resource.get_meta("amount"), resource.position]
	print("WORLD_RESOURCES=%d FINGERPRINT=%s" % [main.resources.size(), fingerprint.sha256_text()])
	for prop in main.physics_props:
		_ok(prop.has_node("AssetVisual") == installed and prop.find_children("*", "CollisionShape3D", true, false).size() == 1, prop.kind + "替换保留单个刚体碰撞")
	var data: Array = main._serialize_props()
	for entry in data:
		entry.erase("visual")
	main._restore_props(data)
	_ok(main.physics_props.size() == data.size(), "旧存档迁移全部道具数量不变")
	for prop in main.physics_props:
		_ok(prop.visual == "emace_" + prop.kind, "旧存档" + prop.kind + "按种类迁移")
	for h in main.houses:
		var origin: Vector2 = h.get("entrance_origin", h.pos)
		var point: Vector2 = preload("res://scripts/interior.gd").door_point(origin, h.rot, h.kind)
		var exit: Vector2 = h.get("exit_point", preload("res://scripts/interior.gd").exit_point(h.pos, h.rot, h.kind))
		_ok(point.distance_to(exit) < 3.8, h.id + "门与出口在交互范围")
	var interior: Dictionary = main.interior.ensure("full_check_hut", "hut", main.forced_map_seed)
	var shop: Dictionary = main.interior.ensure("full_check_shop", "shop", main.forced_map_seed)
	_ok(interior.can_sleep and not shop.can_sleep, "床/商店睡觉功能不变")
	for space in [interior, shop]:
		var furniture: Array = space.node.find_children("AssetVisual*", "Node3D", true, false)
		_ok(furniture.size() >= 7 if installed else furniture.is_empty(), space.kind + "家具和木结构替换")
		_ok(space.node.find_children("*", "StaticBody3D", true, false).size() == 1, space.kind + "家具没有另加碰撞体")
	main.terrain.apply_season_tint(Color(0.8, 0.9, 1.0), 1.0)
	var grass: Material = main.terrain.tintables[0]
	_ok(grass is ShaderMaterial if installed else grass is StandardMaterial3D, "草丛风动材质与缺包回退")
	_ok(bool(main.terrain.ground_mi.material_override.get_shader_parameter("use_asset_ground")) == installed, "地面贴图按安装状态启用")
	print("CATALOG_TRIANGLES=%d LOAD_MS=%.1f" % [triangles, (Time.get_ticks_usec() - started) / 1000.0])
	# 同步执行固定数量断言；中途脚本错误不会伪装成全绿。
	_ok(checks == (89 if installed else 39), "完整执行全部验收断言")
	print("==== EMACE FULL DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)
