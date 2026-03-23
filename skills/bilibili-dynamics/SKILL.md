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
C:\Users\Administrator\.openclaw\bin\qq-client.exe -c C:\Users\Administrator\Documents\Projects\qq-client\config.toml fetch --all --show-all --format json
```

### 查询指定游戏的最新动态

```bash
C:\Users\Administrator\.openclaw\bin\qq-client.exe -c C:\Users\Administrator\Documents\Projects\qq-client\config.toml fetch --uid <UID> --show-all --format json
```

将 `<UID>` 替换为上表中对应的 B站UID。

### 查询多页历史动态

```bash
C:\Users\Administrator\.openclaw\bin\qq-client.exe -c C:\Users\Administrator\Documents\Projects\qq-client\config.toml fetch --uid <UID> --show-all --format json --pages 3
```

### 查看数据库统计

```bash
C:\Users\Administrator\.openclaw\bin\qq-client.exe -c C:\Users\Administrator\Documents\Projects\qq-client\config.toml stats
```

## 如何格式化回复

从 JSON 输出中提取以下字段，为用户组织简洁的回复：

1. **作者名称**: `modules.module_author.name`
2. **发布时间**: `modules.module_author.pub_ts`（Unix 时间戳，转换为可读时间）
3. **动态类型**: `type` 字段（DYNAMIC_TYPE_AV=视频, DYNAMIC_TYPE_DRAW=图文, DYNAMIC_TYPE_WORD=纯文字, DYNAMIC_TYPE_FORWARD=转发）
4. **文字内容**: `modules.module_dynamic.desc.text`
5. **图片**: `modules.module_dynamic.major.draw.items[].src`
6. **视频**: `modules.module_dynamic.major.archive`（标题、封面、BV号）
7. **互动数据**: `modules.module_stat`（点赞、评论、转发）
8. **动态链接**: `https://t.bilibili.com/{id_str}`

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
- 转发类动态（抽奖开奖等）可以简略展示，标注"[转发/抽奖]"
- 如果命令执行失败，告诉用户稍后重试
