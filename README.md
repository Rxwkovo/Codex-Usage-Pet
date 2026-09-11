# 码团 · Codex Usage Pet

薄荷色的桌面小伙伴，分别显示 Codex **五小时与一周剩余额度**。

![手绘风格码团，额度为演示数据](preview.png)

## v2.1.2：完整叶片、自然表情与舒展动作

修复伸懒腰时叶尖被切图截断的问题，补画双手举高与轻轻侧伸的姿势。顶点停留比例可在设置中调整，默认占整段动作的 18%。表情保留身体原有面板的底色和纹理，只替换五官，减少整块脸贴上去的感觉。

挥手和伸懒腰各增加到 16 帧，其余动作保留原版 8 帧，共 72 张身体动作帧。角色继续使用完整手绘风格图片播放。素材由内置 imagegen 生成，不是人工手绘或 Canva 导出的作品。

走路、坐下、躺下、伸懒腰、挥手和缩团均能保持当前额度表情。新画的动作专属表情匹配每帧的脸部方向，眨眼独立触发，睡觉使用当前情绪的闭眼版本。详见 [更新日志](CHANGELOG.md)。

[查看新版伸懒腰逐帧效果](preview-stretch-v2.1.2.png) · [全部动作与四种额度表情](preview-actions-v2.1.2.png)

动作之间保留可配置短过渡；坐下、躺下仍有进入、停留和起身过程，散步会在桌面真实移动。图稿存在轻微逐帧线条变化。

| 坐下 | 躺下 | 缩团 |
| --- | --- | --- |
| ![坐下](preview-sit.png) | ![躺下](preview-sleep.png) | ![缩团](preview-compact.png) |

## 下载和使用

在 [Releases](https://github.com/Rxwkovo/Codex-Usage-Pet/releases/latest) 下载 EXE，退出旧版后双击启动。需要 Windows 10/11、系统自带 Windows PowerShell 5.1 和 .NET Framework；在线额度需要本机安装 Codex 并使用 ChatGPT 账户登录。

- **右下角系统托盘**：右键可显示码团、打开设置或退出。双击图标展开码团；图标可能位于托盘折叠菜单。
- **单击**：摸摸码团；拖动可调整位置，靠近主屏工作区边缘时吸附。
- **右键码团 → 设置…**：修改动作、缩团、动效、眨眼、外观、互动和额度参数。也可直接点播动作。
- 默认每段随机动作结束后等待 **60–120 秒**；睡醒可连播伸懒腰，默认开启，可单独关闭。整段连播结束后再计时。
- 默认空闲 **15 秒**后收起手脚和额度面板，缩至正常大小的 **42%**。鼠标移入、有效额度变化或动作开始时展开；至少保持 **8 秒**。
- 额度决定各动作与缩团中的情绪；眨眼和动作分别控制，睡觉保留当前情绪的闭眼版本。

v2.1 解压到 `%LOCALAPPDATA%\CodexUsagePet\2.1.2`，首次运行优先迁移 v2.1.1，并按版本顺序回退查找旧设置 的位置、大小、频率等适用设置。重复启动 EXE 不会重复创建宠物。退出后删除 EXE 和对应版本目录即可卸载；没有开机自启。

`preferences.json` 保存外观和行为偏好，`settings.json` 保存位置；设置保存后立即生效，取消不应用修改。支持恢复默认，最小/最大值及刷新/过期时间有输入校验。手绘版移除了旧版逐个控制关节、叶片和视线的几何参数，动作形状由图稿决定；保留时长、间隔、概率、步距、短过渡、呼吸、眨眼、字体、大小、透明度、气泡和专注时长等有效设置。

## 额度与网络

通过 Codex 官方 App Server 的 `account/rateLimits/read` 只读获取额度。按返回的 300 / 10080 分钟分类，不假设 primary 一定是五小时。优先选择 `rateLimitsByLimitId.codex`。CLI 与桌面登录不同账户时，以 CLI 数据为准。

默认取两档剩余额度的较小值：≥50% 开心；>20% 平静；>0% 担忧；0% 难过。这是宠物的表现规则，可在设置中调整。缺失、过期或同步失败的数据使用中性表情，缓存不冒充实时额度；到达重置时间后等待在线同步。

默认每 60 秒后台读取一次，可手动刷新。先尝试不使用 HTTP/HTTPS/ALL_PROXY 的直连（12 秒超时），失败后用原有网络配置重试（25 秒超时）。这不会切换系统 VPN，也不能保证在受限网络中绕过连接阻断。

不读取聊天内容、不直接读取密钥、不调用模型、不使用额度重置券。仅将两档百分比、重置时间、同步时间与路线保存在 `usage.json`。缓存与个人设置均被 `.gitignore` 排除。

## 开发

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\usage.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\mood.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\preferences.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\sprite.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1 -Smoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

`-Preview` 使用演示额度，不查询账户。`-PreviewAction sit` 等参数可导出动作预览，`-PreviewCompact` 导出缩团。EXE 的 `--smoke` 检查实际走动、缩团、展开和托盘退出，完成后自动关闭。PowerShell 文件须保存为 UTF-8 BOM。

启动器源码为 `launcher.cs`；构建仅打包明确列出的程序、图片素材、说明和许可证，不包含个人设置、额度缓存或日志。

灵感来自 [MeteorNOX 的 DeepSeek Balance Whale Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)，未复制其代码或素材。MIT License。
