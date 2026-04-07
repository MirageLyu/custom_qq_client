---
name: bilibili_dynamics
version: 1.1.1
description: 查询原神、崩坏星穹铁道、绝区零的B站官方动态（杂志条富文本）
author: qq-client
---

# B站游戏动态查询

**硬性规则**：`latest` 子命令**必须**使用 `--format json`（从 1.1.1 起不传 format 时默认已是 json）。若使用 `--format text`，工具会输出含 `【游戏名】最新动态` 的旧版纯文本，**禁止**把该旧版文本直接贴给用户；遇到 text 输出应重新执行并带 `json`。

你可以使用 `qq-client` 命令行工具查询米哈游旗下三款游戏的B站官方账号最新动态。

## 何时使用

当用户提到以下任何内容时，使用此技能：
- 查看/查询 动态、最新消息、最新更新
- 原神、Genshin
- 崩坏星穹铁道、星铁、StarRail、HSR
- 绝区零、ZZZ、Zenless Zone Zero
- B站动态、bilibili
- 游戏公告、版本更新

## 账号对照表

| 游戏 | B站UID | 关键词 |
|------|--------|--------|
| 原神 | 401742377 | 原神, genshin |
| 崩坏星穹铁道 | 1340190821 | 星铁, 星穹铁道, starrail, hsr |
| 绝区零 | 1636034895 | 绝区零, zzz |

## 如何执行

### 查询所有游戏的最新动态

```bash
qq-client --config /app/config.toml latest --all --count 2 --format json
```

### 查询指定游戏的最新动态

```bash
qq-client --config /app/config.toml latest --game <游戏名> --count 5 --format json
```

将 `<游戏名>` 替换为 `原神`、`星铁`、`绝区零`、`genshin`、`hsr`、`zzz` 之一。

### 查询多页历史动态

```bash
qq-client --config /app/config.toml latest --game <游戏名> --count 5 --format json --pages 3 --include-forwards
```

### 查看数据库统计

```bash
qq-client --config /app/config.toml stats
```

---

## 回复版式：「杂志条」（必须遵守）

**禁止**使用以下旧版排版（即使用户看起来「整齐」也不行）：以 `【原神/星铁/绝区零】最新动态` 开头、或仅有「图文动态 | 日期 + 点赞行 + 链接」而无 `┃🟡/🟣/🟠` 色条与 ≤20 字自撰标题、或无 `thumbnail_url` 时的图行。

每条动态按下面结构输出，**顺序固定**：

1. **色条标记**（纯文本模拟杂志左侧色条，与账号 `game` 对应）  
   - 原神：`┃🟡`  
   - 崩坏星穹铁道：`┃🟣`  
   - 绝区零：`┃🟠`  

2. **缩略图**（若 `thumbnail_url` 非空）  
   - 使用 Markdown 图片语法一行展示：  
     `![thumb](<thumbnail_url>)`  
   - 若平台不支持 Markdown 图，则退化为单独一行：`图：<thumbnail_url>`  

3. **一句话标题（≤20 个汉字）** — **必须由你根据 `headline_source` 现场撰写**，禁止照抄整段正文。  
   - 只写一条动态的核心信息：版本、角色、活动、维护等。  
   - 不要引号包裹；不要换行；不要超过 20 个汉字（标点可酌情 1～2 个）。  

4. **类型与数据**（一行，极简）  
   - 格式：`类型 · 👍数字 · 💬数字 · 时间`  
   - 时间用 `published_at` 或省略秒。  

5. **链接**（单独一行）  
   - `链接：<url>`  

6. **多条动态**：每条之间空一行，不要长段落堆砌。

### 生成 ≤20 字标题的 Prompt 约束（内化执行）

对每条 `items[]`，把 `headline_source` 当作**唯一**依据（其中已含类型、标题、正文摘要；转发含「转发原文」）：

- 输出**一条**中文短语，**≤20 个汉字**，像杂志封面标题。  
- 禁止抄录原文超过 8 个连续汉字；要**归纳**而非复制。  
- 禁止「据悉」「据了解」等废话；禁止 emoji 出现在标题里（色条已有 emoji）。  
- 若内容仅为抽奖/转发无实质信息，标题写：`官方转发提醒`（6 字）或类似极短说明。  

### JSON 字段说明（除标题外尽量用原始字段）

| 字段 | 用途 |
|------|------|
| 顶层 `game` | 决定色条颜色 |
| `items[].thumbnail_url` | 图/视频封面 URL；可能为空 |
| `items[].headline_source` | **仅用于你脑内生成标题**，不要整段贴给用户 |
| `items[].dynamic_type_label` | 类型展示 |
| `items[].published_at` | 时间 |
| `items[].stats` | 点赞/评论/转发 |
| `items[].url` | 动态链接 |
| 顶层 `error` | 非空则如实告知失败 |

### 输出示例（结构示意，标题为模型生成）

```
┃🟡
![thumb](https://i0.hdslb.com/...)
4.7 版本前瞻定档本周五
视频动态 · 👍12.3万 · 💬8900 · 2026-04-06 20:00
链接：https://t.bilibili.com/xxxxx

┃🟣
图：https://i0.hdslb.com/...
星铁 3.2 维护公告
图文动态 · 👍2.1万 · 💬1200 · 2026-04-05 10:00
链接：https://t.bilibili.com/yyyyy
```

## 注意事项

- 每次最多展示最近 5 条动态，避免消息过长  
- 用户未指定游戏时，三款游戏各 2 条（或按命令 `--count`）  
- 默认过滤抽奖类低价值转发；仅当用户明确要求时用 `--include-forwards`  
- 若命令失败，告知用户稍后重试  
- **不要**把 `headline_source` 原文发给用户；用户只需看到**你生成的短标题** + 图 + 链接  
