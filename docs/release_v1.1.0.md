# v1.1.0：完整素材、自然动作与 Windows / Android 安装包

本版本提供资源内嵌的 Windows 单文件 EXE，以及使用固定专属发布密钥签名的 Android APK。模型、动画、材质和贴图均已随包交付，无需安装 Godot 或额外下载素材。

## 下载与安装

| 附件 | 平台 | 大小 |
|---|---|---|
| `DinkumTown3D-Windows-x64.exe` | Windows 10/11 x64 | 约 137.8 MiB |
| `DinkumTown3D-Android.apk` | arm64-v8a / x86_64 | 约 83.6 MiB |
| `SHA256SUMS.txt` | SHA-256 校验值 | 文本 |
| `BUILD_INFO.json` | 源码提交、签名指纹及验收记录 | JSON |

- Windows：下载 EXE 后直接双击，资源已经内嵌。EXE 未做商业代码签名，首次运行可能出现 SmartScreen 提示。
- 安卓：允许浏览器 / 文件管理器安装未知应用，再安装 APK；横屏游玩。使用 Mobile/Vulkan 渲染器，建议 Android 9 及以上、兼容 Vulkan 的 64 位设备。此要求参考 [Godot 官方硬件说明](https://docs.godotengine.org/en/stable/about/system_requirements.html)，手机帧率尚未实测。
- **旧版安卓不能覆盖升级：** v1.0.0 的密钥已丢失，本次按用户确认换用固定专属发布密钥。必须卸载旧版后安装，卸载通常会删除旧存档；后续版本沿用此次密钥。包名仍为 `com.dinkumtown3d.app`，versionCode 为 2。
- 校验文件：PowerShell 中执行 `Get-FileHash 文件路径 -Algorithm SHA256`，与 `SHA256SUMS.txt` 对照。

## 本版内容

- Quaternius 自然模型与更密的植被；冒险者、鹿、雄鹿和狐狸的骨骼模型与动画。
- Kenney 的房屋、家具和道具，全部第三方源素材为 CC0，许可随包交付。
- 修复停步后残留姿势、步态循环跳脚、顶墙原地跑和动物转弯滑行；步频跟随实际位移。
- 界面文字根据分辨率放大、加粗并自动排布；触控支持横竖屏布局。
- 保留采集、建造、农耕、狩猎、物理交互、昼夜季节、游泳潜水与槽位存档。
- 安卓 Mobile 渲染器关闭其不支持的 SSAO；菜单版本号统一读取项目版本。

操作及从源码运行、重新打包步骤见 [README](https://github.com/Eser-Tired/DinkumTown3D/blob/v1.1.0/README.md)。

## 验收与限制

| 项目 | 结果 |
|---|---|
| 战斗 / 水域 / UI | 102 / 38 / 1907 项，fails=0 |
| 存读档往返 | fails=0 |
| 触控 8 种分辨率 | 全部 bad=0 |
| 两个平台运行资源 | 各 119 场景、19 独立贴图、147 贴图表面完整；9 份许可与声明完整 |
| Windows EXE | 实际启动与菜单截图通过 |
| 导出资源冒烟检查 | 桌面 Forward+ 与 Mobile 渲染均通过菜单→新游戏→实际移动；截图已人工检查 |
| APK | Release 模板；v2 / v3 签名验证通过，两个 64 位 ABI 均存在 |

没有连接安卓真机；本机模拟器缺少硬件加速且软件启动失败，因此**未完成安卓安装、真机画面、性能、发热与触控实机验收**。Mobile 预览是在 Windows 上加载 APK 的实际游戏资源完成，不能代替安卓设备测试。部分逻辑自检仍有退出时 ObjectDB 清理警告。

引擎：Godot 4.7.2，MIT 许可；引擎与依赖声明及 CC0 素材许可已随包保留。构建目录不进入源码 Git，安装包作为此 Release 附件发布。
