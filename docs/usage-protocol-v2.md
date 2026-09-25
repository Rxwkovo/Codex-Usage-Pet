# 额度同步协议 v2

`GET /usage` 在原有五个字段之外增加 `protocolVersion` 和 `policy`。这是一次只增加字段的兼容升级：旧客户端继续读取原字段，新客户端可以按服务端声明的有效期和情绪阈值判定状态。

```json
{
  "protocolVersion": 2,
  "policy": {
    "refreshSeconds": 60,
    "staleSeconds": 120,
    "clockSkewToleranceSeconds": 5,
    "happyMinRemaining": 50,
    "worriedMaxRemaining": 20,
    "exhaustedMaxRemaining": 0
  },
  "status": "ok",
  "updatedAt": 1789278000,
  "serverTime": 1789278010,
  "fiveHour": {"remaining": 76, "resetsAt": 1789281600},
  "weekly": {"remaining": 24, "resetsAt": 1789882800}
}
```

`policy` 由桌面端已经校验的当前设置生成，是客户端判断新鲜度和情绪的唯一策略来源。额度缓存里即使出现同名字段也不能覆盖它。刷新、新鲜度和情绪阈值允许有限小数；`updatedAt`、`serverTime` 和 `resetsAt` 必须是数值类型的整数 Unix 秒，字符串、布尔值和小数时间戳均视为无效。

客户端以收到响应时的 `serverTime` 校正电脑与手机的时钟差，并用经过校正的当前时间执行以下判定：

1. `status` 不是 `ok`、任一窗口缺失、`updatedAt` 的年龄大于或等于 `staleSeconds`、`updatedAt` 超前超过 `clockSkewToleranceSeconds`，或任一 `resetsAt` 已到期时，状态为 `unknown`。
2. 其余情况取五小时与一周窗口中较低的 `remaining`，再依次与 `exhaustedMaxRemaining`、`worriedMaxRemaining` 和 `happyMinRemaining` 比较，得到 `exhausted`、`worried`、`calm` 或 `happy`。
3. 服务端也执行同样的窗口、重置时间与新鲜度检查；失效快照仍返回白名单字段，但 `status` 为 `stale`。

新客户端连接旧服务时，如果 `protocolVersion` 或完整、合法的 `policy` 缺失，整组使用上面列出的 v2 默认值。合法范围为：刷新 30–600 秒；过期 60–3600 秒且至少比刷新多 30 秒；开心阈值 1–100；担忧阈值 0–99 且低于开心阈值；时钟容差固定 5 秒；耗尽阈值固定 0。旧客户端连接 v2 服务时忽略新增的两个顶层字段，原有 `status`、`updatedAt`、`serverTime`、`fiveHour` 和 `weekly` 的类型及含义不变。

协议只传递额度和时间信息。服务端从本地文件读取后重新构造白名单响应，不转发凭据、配对令牌、聊天内容或未知字段。
