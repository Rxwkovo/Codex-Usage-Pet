# 码团 · Codex Pet

薄荷色的小代码精灵，分别显示 Codex **5 小时与一周剩余用量**。灵感来自 [MeteorNOX 的 DeepSeek Balance Whale Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)。外观和实现为全新绘制，没有复制原项目素材或代码。

![码团外观，图中为示例数据](preview.png)

## v1.1：码团会自己休息了

空闲 14–28 秒后随机散步、坐下、侧躺打盹或伸懒腰，不连续重复同一个动作。散步约 8 秒、坐下 12 秒、打盹 18 秒、伸懒腰 5 秒；动作结束自然恢复站立。散步会在屏幕工作区内向左或向右走一小段，鼠标靠近即停下，点击可叫醒，拖动和打开菜单会停止当前动作。专注计时期间不会随机散步。

右键可以点播动作，也可以关闭随机待机。安静模式会暂停自动动作；手动点播动作会恢复灵动模式。

文字统一使用微软雅黑；用量数字为 15 号半粗体。文字与宠物分开布局，小号宠物也保留清晰的文字大小；增加像素对齐与文字背景对比度。

| 坐下陪伴 | 侧躺休息 |
| --- | --- |
| ![坐下](preview-sit.png) | ![侧躺](preview-sleep.png) |

Windows 10/11 桌面小宠物。下载仓库 ZIP 并解压，双击「启动码团.vbs」启动。界面使用系统自带的 Windows PowerShell 5.1 和 WPF。用量功能需要已安装 Codex 桌面版或 PATH 中的 codex.exe，并使用 ChatGPT 账户登录。

- 单击：摸摸、弹性回弹、随机台词。
- 拖动：调整位置，靠近主屏工作区四边时吸附。
- 右键：大小、置顶、安静模式、25 分钟专注、用量页面和退出。
- 位置、大小、模式保存在同目录 settings.json。
- 安静模式关闭悬浮和眨眼动画。
- 30 帧节奏的悬浮呼吸、叶芽摇摆、自然闭眼动画；触碰弹性回弹、气泡淡入和用量条平滑过渡。
- 随机待机动作：散步、坐下、躺下、伸懒腰；支持右键点播和开关，偏好随设置保存。
- 五小时和一周分别显示剩余百分比、进度条，悬停文字查看本地时间的重置时刻。
- 每 60 秒后台读取一次；右键可手动刷新。按接口返回的 300 / 10080 分钟分类，不假设 primary 一定是五小时。
- 缺少某一档时显示「暂无数据」，不会把缺失数据当作 0%。网络异常保留缓存并标明时间；到达重置时刻后等待同步，不自行假设额度已恢复。

这是独立桌面伴侣，不是嵌入 Codex 内部的插件。通过 [官方 App Server](https://developers.openai.com/codex/app-server) 的 `account/rateLimits/read` 读取当前 CLI 登录账户的额度，不读取会话、不直接读取密钥、不调用模型、不消耗额度重置券。CLI 与桌面若登录不同账户，以 CLI 的数据为准。界面显示的是订阅额度剩余比例，不是 API 余额。

查询在独立隐藏进程运行，不阻塞拖拽。先尝试不使用 HTTP/HTTPS/ALL_PROXY 的直连（12 秒超时），失败后使用原环境的网络配置重试（25 秒超时）。界面标明「直连」「系统网络」或「缓存」。这不会切换系统 VPN；如果网络使用 VPN 隧道，直连请求仍可能经过隧道。关闭 VPN 后能否在线取到数据取决于本地网络能否访问官方服务，软件不能保证绕过网络阻断。

仅将两档百分比、重置时间、网络路线和同步状态写入本地 usage.json，不保存完整账户响应。该缓存与个人设置均被 .gitignore 排除。

专注结束只在宠物上提醒，不播放声音。退出后专注计时不保留。未设置开机自启。吸附限主屏工作区；暂不提供跨屏吸附或 Codex 工作状态联动。

如系统不支持 VBS，在此文件夹的 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1
```

删除整个文件夹即可卸载；先右键退出宠物。

## 开发验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\usage.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\behavior.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1 -Preview
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1 -Preview -PreviewAction sleep
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\pet.ps1 -Smoke
```

预览参数使用明确标注的示例数据，不发起用量查询。请保持 pet.ps1 为 UTF-8 BOM 编码，以兼容 Windows PowerShell 的中文文本。

MIT License。欢迎改造自己的小宠物。
