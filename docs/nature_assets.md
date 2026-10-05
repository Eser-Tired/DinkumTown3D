# 自然、人物与动物素材

本轮使用静态美术和骨骼动画，不安装 addons，不运行下载包里的脚本。新增素材均为 CC0，转换后的 Godot 场景随源码交付；新电脑无需另外安装这些包。

| 来源 | 接入范围 | 许可 |
| --- | --- | --- |
| [Stylized Nature MegaKit Standard](https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/) | 免费版全部 68 个模型转换为场景；替换树木、灌木、岩石和草丛，新增花、蕨、三叶草、蘑菇、碎石地被。树桩沿用尺寸，改用包内枯树树皮与法线材质。 | assets/quaternius/LICENSE.txt，CC0 |
| [Ultimate Modular Men](https://quaternius.com/packs/ultimatemodularcharacters.html) | Adventurer，24 个原生骨骼动画；接入待机、走路、跑步、挥砍。跳跃、游泳由原姿态适配到骨骼。 | assets/characters/LICENSE.txt，CC0 |
| [Ultimate Animated Animals](https://quaternius.com/packs/ultimateanimatedanimals.html) | Deer、Stag、Fox；走路、奔跑、受伤、死亡、重生。 | assets/animals/LICENSE.txt，CC0 |

在 Godot 商店检索人物/动物候选后，经用户授权扩大到作者官网，并允许更换动物种类。人物最终选择冒险者，动物由袋鼠/鸸鹋改为鹿/雄鹿/狐狸。15 个原有狩猎槽位按旧顺序分配，血量、掉落、存档索引不变；四足动物用连续步态，不再叠加袋鼠的跳跃脉冲。湖岸原棕榈点位改为同包松树。建筑、家具、道具和地表仍用上一轮 EmacE 素材，作物、水和 UI 保留现有实现。

免费自然包没有独立地形纹理、棕榈和树桩，也不包含房屋或动物；不能把宣传的完整版 116 个模型当成免费版的内容。68 个模型都能加载，场景按用途选取变体，散落花瓣和铺路石等也保留在资产目录中供后续布置。

## 密度和存档

固定种子 20260921：原地被实际有效实例 1253，新增 37151，总计 38404。新增地被按 28 米单元组织为 780 个 MultiMesh，65 米可见范围，不增加阻挡碰撞。镇中心、农田、通道、水域和陡坡排除；独立随机流避免占用旧世界随机数。

191 个采集点的类型、数量、位置 SHA-256 与前版一致：

`f5ffc69462f7c76e611bf1c96d51bd06bbb00315d4e8ef952928aa5eb807ebbb`

自然包纹理共享并缩至最大 1024 像素，树皮保留法线，叶片使用 alpha 裁切和轻微风动。全部新增美术约 28.1 MiB；依赖审计 127 个资源，全部在 assets/ 或 shaders/，没有临时下载路径。

## 重建

先按以上作者页面取得原始文件。自然包解压后选择 glTF 目录；人物、动物使用作者公开的 glTF（二进制文件可用 .glb 扩展名）。在项目根目录执行：

```powershell
& $Godot --headless --path . --script res://tools/nature_import.gd -- 'C:/Downloads/Nature/glTF' res://assets/quaternius/
& $Godot --headless --path . --script res://tools/nature_import.gd -- 'C:/Downloads/Adventurer' res://assets/characters/ --rigged
& $Godot --headless --path . --script res://tools/nature_import.gd -- 'C:/Downloads/Animals' res://assets/animals/ --rigged
& $Godot --headless --path . --script res://tools/art_dependencies.gd
```

只把所需的 Adventurer 或 Deer/Stag/Fox 文件放进人物/动物导入目录。保留各包 LICENSE.txt。审计器列出的 ORPHAN 是先前转换留下的未引用材质，可以移出 assets/ 归档。

## 验证和对比

`nature_check.tscn` 必须窗口模式运行。headless 的 Dummy RenderingServer 不保存 MultiMesh 变换，读回会得到零矩阵；不能拿它证明实例贴地。真实渲染验收逐一检查全图实例，并覆盖模型目录、纹理尺寸、随机性、采集身份和骨骼动画。

```powershell
& $Godot --path . res://tools/nature_check.tscn --quit-after 3000
& $Godot --path . res://tools/nature_shot.tscn --quit-after 3000 -- --dir res://asset_shots_nature/
& $Godot --path . res://tools/nature_shot.tscn --quit-after 3000 -- --no-nature --no-characters --dir res://asset_shots_nature_before/
```

`--no-nature` 仅关闭本轮自然包和新增地被，`--no-characters` 关闭新人物/动物，`--no-emace` 单独关闭上轮本地素材。截图原始输出走已忽略的 asset_shots*/，归档图放 docs/shots/。[图文验收](nature_full.html)。
