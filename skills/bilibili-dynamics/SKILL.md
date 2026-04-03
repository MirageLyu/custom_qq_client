---
name: bilibili_dynamics
version: 1.0.0
description: 查询原神、崩坏星穹铁道、绝区零的B站官方动态
author: qq-client
---

# B站游戏动态查询

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

## 如何格式化回复

`latest --format json` 的输出已经是摘要结构，优先使用以下字段组织回复：

1. **游戏名称**: 顶层 `game`
2. **发布时间**: `items[].published_at`
3. **动态类型**: `items[].dynamic_type_label`
4. **标题**: `items[].title`
5. **正文摘要**: `items[].text`
6. **互动数据**: `items[].stats.likes` / `comments` / `forwards`
7. **动态链接**: `items[].url`
8. **错误信息**: 顶层 `error`，如果非空则如实告知用户查询失败

回复格式示例：

```
【原神】最新动态

1. [视频] 《原神》角色预告-「法尔伽：骑士精神」
   发布时间：2026-02-24 12:00
   点赞 46万 | 评论 2.2万
   链接：https://t.bilibili.com/xxx

2. [图文] #原神# 版本更新预告
   发布时间：2026-03-21 12:00
   点赞 1.8万 | 评论 978
   链接：https://t.bilibili.com/xxx
```

## 注意事项

- 每次最多展示最近 5 条动态，避免消息过长
- 如果用户没有指定游戏，展示所有三款游戏各 2 条最新动态
- 默认会过滤抽奖/开奖等低价值转发；只有在用户明确要求历史或转发内容时，才加上 `--include-forwards`
- 如果命令执行失败，告诉用户稍后重试
