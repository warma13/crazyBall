# 弹钉流派

> 更新时间: 2026-03-29 18:15:00  
> 版本: v2.1.0  
> 状态: **设计稿**（未实装）

---

## 概述

围绕**撞钉**设计的三个派系，每派系 4 个效果，派系内效果互相增强。

- 删除 `双重撞击 (double_hit)`（与黄金弹钉重复）
- 保留 `黄金弹钉 (peg_gold)`
- 新增 18 个弹钉效果，共 19 个
- `反弹护盾 (rebound_shield)` 不属于弹钉流派，归入通用效果

效果总数变化: 21 → 38（删 1 + 新增 18）

| 派系 | 核心理念 | 4 个效果 |
|------|---------|---------|
| **频率派** | 撞更多钉 | 弹钉磁场、弹钉减速、弹钉火花、弹钉弹射 |
| **收益派** | 每次撞钉赚更多 | 黄金弹钉、弹钉共鸣、弹钉连锁、弹钉宝石 |
| **协作派** | 多球互动增益 | 弹钉充能、弹钉印记、弹钉共振、弹钉波动 |

| 增强系 | 前置条件 | 6 个效果 |
|--------|---------|---------|
| **黄金弹钉增强** | 需解锁黄金弹钉 | 黄金积累、黄金暴击、黄金连击、黄金余烬、黄金丰收、黄金光环 |

| 独立效果 | 说明 |
|---------|------|
| **弹钉增值** `peg_value` | 撞钉增加球基础价值，不依赖任何前置 |

派系间也有联动：频率派撞得越多 → 收益派每个效果触发越多 → 协作派在多球下放大所有收益。黄金弹钉增强系深化单个核心效果的收益上限。

---

## 频率派 — 撞更多钉

> 核心循环：磁场让球碰到更多钉 → 减速让球滞留更久 → 火花让每次撞钉等效多撞 → 弹射让球弹得更远覆盖更大范围 → 再次触发磁场

### 弹钉磁场 `peg_magnet`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.80 * (1 - 0.95^lv)` | +4% | +32% | +51% | +63% | cost(4, 1.8) |

- **触发**: 碰撞检测时
- **效果**: 弹钉碰撞半径增大 `value` 比例
- **渐进上限 80%**
- **增强**: 范围越大 → 减速/火花/弹射触发次数越多

```lua
local pegR = CONFIG.PEG_RADIUS * (1 + pegMagnetVal)
```

### 弹钉减速 `peg_slow`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.50 * (1 - 0.95^lv)` | 3% | 20% | 32% | 39% | cost(4, 1.7) |

- **触发**: 每次撞钉后
- **效果**: 球速降低 `value` 比例，在弹钉区域滞留更久
- **渐进上限 50%**
- **增强**: 速度越慢 → 磁场捕获范围内停留越久 → 火花触发更密集

```lua
ball.vx = ball.vx * (1 - pegSlowVal)
ball.vy = ball.vy * (1 - pegSlowVal)
```

### 弹钉火花 `peg_spark`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.50 * (1 - 0.95^lv)` | 3% | 20% | 32% | 39% | cost(5, 1.9) |

- **触发**: 每次撞钉时概率判定
- **效果**: 概率向最近的 1 颗钉产生火花，等同于球也撞了那颗钉（触发所有撞钉效果）
- **渐进上限 50%**
- **不连锁**: 火花命中的钉不再触发火花
- **增强**: 火花命中也触发减速/磁场判定 → 等效多一次完整撞钉

```lua
if math.random() < pegSparkVal then
    local nearest = findNearestPeg(peg, allPegs)
    if nearest then triggerPegHit(ball, nearest, true) end
end
```

### 弹钉弹射 `peg_launch`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.80 * (1 - 0.95^lv)` | +4% | +32% | +51% | +63% | cost(4, 1.8) |

- **触发**: 每次撞钉后
- **效果**: 球撞钉后弹跳力增强 `value` 比例，弹得更远覆盖更大范围
- **渐进上限 80%**
- **增强**: 弹得越远 → 经过更多钉子区域 → 磁场捕获更多碰撞

```lua
-- 撞钉后弹跳处理
ball.vx = ball.vx * (1 + pegLaunchVal)
ball.vy = ball.vy * (1 + pegLaunchVal)
-- 注意：减速和弹射同时生效时，先弹射再减速
-- 净效果 = (1 + launch) * (1 - slow)
```

**频率派内部循环**:
```
磁场(碰到更多钉) → 减速(停留更久) → 火花(每次多撞一颗)
      ↑                                      ↓
      ←←←←← 弹射(弹得更远覆盖更广) ←←←←←←←←←
```

---

## 收益派 — 每次撞钉赚更多

> 核心循环：黄金弹钉给即时金币 → 连锁奖励快速撞钉 → 共鸣将撞钉次数转化为落袋倍率 → 宝石补充抽取资源 → 升级更多效果

### 黄金弹钉 `peg_gold`（已有）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| int(1, 1.35) | +1 | +10 | +106 | cost(3, 1.7) |

- **触发**: 每次撞钉
- **效果**: 直接获得 `value` 金币，即时入账
- **增强**: 频率派撞得越多 → 触发次数越多；连锁加速撞钉 → 触发更密集

### 弹钉共鸣 `peg_resonance`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| pct(0.03, 1.20) | +3%/钉 | +14%/钉 | +95%/钉 | cost(4, 1.8) |

- **触发**: 落袋结算时
- **效果**: 落袋收益乘以 `(1 + value * pegHits)`
- **增强**: 频率派增加 pegHits → 共鸣倍率指数级增长；连锁让更多撞钉被计数

```lua
earning = math.floor(earning * (1 + resonanceVal * ball.pegHits))
```

### 弹钉连锁 `peg_chain`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| pct(0.10, 1.22) | +10% | +55% | +332% | cost(5, 1.9) |

- **触发**: 0.3 秒内连续撞多颗钉时
- **效果**: 第 2 颗起每颗额外获得 `floor(chainCount * value * ball.value)` 金币
- **增强**: 减速让球慢下来反而不利连锁；但弹射+磁场让球快速穿过密集区 → 高连锁数

```lua
if timeSinceLastPeg < 0.3 then
    ball.chainCount = (ball.chainCount or 0) + 1
    if ball.chainCount >= 2 then
        State.AddEarnings(math.floor(ball.chainCount * pegChainVal * ball.value))
    end
else
    ball.chainCount = 1
end
```

### 弹钉宝石 `peg_gem`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.25 * (1 - 0.95^lv)` | 1% | 10% | 16% | 20% | cost(6, 2.0) |

- **触发**: 每次撞钉时概率判定
- **效果**: 概率掉落 1 颗宝石
- **渐进上限 25%**
- **增强**: 频率派撞得越多 → 宝石期望产出越高 → 更多抽取 → 升级更多效果

```lua
if math.random() < pegGemVal then
    gameState.gems = gameState.gems + 1
end
```

**收益派内部循环**:
```
黄金弹钉(即时金币) + 连锁(快速撞钉奖金) → 金币升级球/口袋
              ↕                                    ↓
共鸣(撞钉数→落袋倍率) ← 撞得越多倍率越高     更高球价值
              ↕                                    ↓
宝石(撞钉→抽取资源) → 升级更多效果 → 收益再提升
```

---

## 协作派 — 多球互动增益

> 核心循环：充能让球A为球B铺路 → 印记让后续球撞标记钉获得倍率 → 共振按球数放大所有收益 → 波动推球撞更多钉形成连锁反应

### 弹钉充能 `peg_charge`

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| pct(0.20, 1.20) | +20% | +103% | +630% | cost(5, 1.9) |

- **触发**: 球撞钉时检测该钉是否已被其他球充能
- **效果**: 球 A 撞过的钉进入充能状态（3 秒，发光），球 B 撞到充能钉获得 `floor(ball.value * value)` 金币
- **充能消耗**: 触发后消失
- **增强**: 多球在场 → 充能被触发概率更高；波动推球撞向充能钉

```lua
if peg.chargedBy and peg.chargedBy ~= ball.id then
    State.AddEarnings(math.floor(ball.value * pegChargeVal))
    peg.chargedBy = nil
else
    peg.chargedBy = ball.id
    peg.chargeTimer = 3.0
end
```

### 弹钉印记 `peg_mark`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| pct(0.15, 1.18) | +15% | +53% | +195% | cost(5, 1.9) |

- **触发**: 球撞钉时，该钉获得印记；其他球撞到印记钉时触发
- **效果**: 球 A 撞过的钉被印记（5 秒，视觉标记），球 B 撞到印记钉时该次撞钉的所有收益（黄金弹钉、连锁等）乘以 `(1 + value)`
- **印记不消耗**: 持续到时间结束，多球可反复触发
- **与充能的区别**: 充能给独立金币且触发消失；印记放大撞钉收益且持续存在

```lua
if peg.markedBy and peg.markedBy ~= ball.id then
    -- 本次撞钉所有即时收益 × (1 + markVal)
    pegHitBonus = math.floor(pegHitBonus * (1 + pegMarkVal))
end
peg.markedBy = ball.id
peg.markTimer = 5.0
```

### 弹钉共振 `peg_sync`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| pct(0.04, 1.22) | +4%/球 | +22%/球 | +132%/球 | cost(6, 2.0) |

- **触发**: 每次撞钉时
- **效果**: 场上每多一颗球（不含自身），撞钉即时收益增加 `value` 比例
- **计算**: `bonus = floor(pegHitBonus * value * (ballCount - 1))`
- **增强**: 天降弹珠/多球投放 → 场上球数越多 → 共振加成越高

```lua
local otherBalls = #gameState.balls - 1
if otherBalls > 0 and pegSyncVal > 0 then
    pegHitBonus = math.floor(pegHitBonus * (1 + pegSyncVal * otherBalls))
end
```

### 弹钉波动 `peg_wave`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `200 * (1 - 0.95^lv)` | 10 px/s | 80 px/s | 128 px/s | 157 px/s | cost(5, 1.9) |

- **触发**: 每次撞钉时
- **效果**: 撞钉产生冲击波，对半径 40px 内的其他球施加 `value` px/s 的推力，方向朝向最近的未撞钉
- **渐进上限 200 px/s**
- **增强**: 推动其他球撞钉 → 触发那些球的充能/印记/共振 → 产生连锁反应

```lua
for _, other in ipairs(gameState.balls) do
    if other ~= ball then
        local dist = distance(ball, other)
        if dist < 40 then
            local nearestPeg = findNearestUnhitPeg(other, allPegs)
            if nearestPeg then
                local dir = normalize(nearestPeg.pos - other.pos)
                other.vx = other.vx + dir.x * pegWaveVal
                other.vy = other.vy + dir.y * pegWaveVal
            end
        end
    end
end
```

**协作派内部循环**:
```
充能(球A充钉→球B获金币) + 印记(球A标记→球B收益放大)
              ↕                         ↕
共振(球越多收益越高) ←→ 波动(撞钉推动其他球撞钉)
              ↓                         ↓
         更多球触发充能/印记 ← 波动推球撞向标记/充能钉
```

---

## 三派系联动

```
频率派(撞更多钉) ──→ 收益派(每次撞钉赚更多)
      ↑                       ↓
      │                  金币/宝石升级
      │                       ↓
协作派(多球放大) ←── 天降/多球投放(更多球在场)
      │
      └──→ 波动推球撞钉 → 频率派受益
```

---

## 黄金弹钉增强 — 深化撞钉产金

> 前置条件：必须已解锁黄金弹钉 `peg_gold` 才能在抽取池中出现。
>
> 核心循环：积累提升球价值 → 暴击放大单次产出 → 连击奖励密集撞钉 → 余烬延长产金时间 → 丰收在落袋时结算总产出奖金 → 光环扩大触发范围

### 黄金积累 `gold_stack`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| int(1, 1.20) | +1/钉 | +5/钉 | +31/钉 | cost(4, 1.8) |

- **触发**: 每次撞钉后
- **效果**: 该球的黄金弹钉基础产出值临时增加 `value`，持续到该球落袋或消失
- **累计**: 撞 N 颗钉后，黄金弹钉产出 = `pegGoldVal + N * goldStackVal`
- **增强**: 撞得越多 → 后续每次撞钉的黄金弹钉产出越高；暴击/连击/余烬基于增长后的产出计算

```lua
ball.goldStackBonus = (ball.goldStackBonus or 0) + goldStackVal
-- 黄金弹钉产出时
local goldEarning = pegGoldVal + ball.goldStackBonus
-- 例：peg_gold Lv.10(+5)，gold_stack Lv.10(+5/钉)，撞了20颗
-- → 第21颗产出 = 5 + 20*5 = 105
```

### 黄金暴击 `gold_crit`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.30 * (1 - 0.95^lv)` | 2% | 12% | 19% | 24% | cost(5, 1.9) |

- **触发**: 黄金弹钉产出金币时概率判定
- **效果**: 概率使本次黄金弹钉产出变为 **3 倍**
- **渐进上限 30%**
- **增强**: 频率派撞得越多 → 暴击触发次数期望越高；丰收统计暴击后的金额

```lua
local goldEarning = pegGoldVal
if math.random() < goldCritVal then
    goldEarning = goldEarning * 3
    -- 视觉：金色暴击文字
end
State.AddEarnings(goldEarning)
ball.totalGoldEarned = (ball.totalGoldEarned or 0) + goldEarning
```

### 黄金连击 `gold_streak`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.50 * (1 - 0.95^lv)` | 3%/连 | 20%/连 | 32%/连 | 39%/连 | cost(5, 1.9) |

- **触发**: 0.5 秒内连续撞钉时，从第 2 颗起生效
- **效果**: 连续撞钉计数 streakCount，黄金弹钉产出乘以 `(1 + value * streakCount)`
- **渐进上限 50%/连**（每一连增加的比例上限）
- **断连重置**: 超过 0.5 秒未撞钉则 streakCount 归零
- **与弹钉连锁的区别**: 连锁(peg_chain) 给独立金币；连击(gold_streak) 放大黄金弹钉本身的产出

```lua
if timeSinceLastPeg < 0.5 then
    ball.streakCount = (ball.streakCount or 0) + 1
else
    ball.streakCount = 0
end
local streakMult = 1 + goldStreakVal * ball.streakCount
goldEarning = math.floor(goldEarning * streakMult)
```

### 黄金余烬 `gold_ember`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.40 * (1 - 0.95^lv)` | 2% | 16% | 26% | 31% | cost(5, 1.9) |

- **触发**: 每次黄金弹钉产出后
- **效果**: 产出后 2 秒内，每 0.5 秒额外获得 `floor(本次黄金产出 * value)` 金币（共 4 次）
- **渐进上限 40%**（单次余烬占原产出的比例上限）
- **可叠加**: 多次撞钉的余烬独立计时，互不覆盖
- **增强**: 暴击后的高额产出 → 余烬也按暴击后金额计算

```lua
-- 撞钉产出后挂载余烬
table.insert(ball.embers, {
    amount = math.floor(goldEarning * goldEmberVal),
    ticksLeft = 4,
    timer = 0,
})
-- Update 中每 0.5 秒结算
for _, ember in ipairs(ball.embers) do
    ember.timer = ember.timer + dt
    if ember.timer >= 0.5 then
        ember.timer = ember.timer - 0.5
        State.AddEarnings(ember.amount)
        ball.totalGoldEarned = (ball.totalGoldEarned or 0) + ember.amount
        ember.ticksLeft = ember.ticksLeft - 1
    end
end
```

### 黄金丰收 `gold_harvest`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.50 * (1 - 0.95^lv)` | 3% | 20% | 32% | 39% | cost(6, 2.0) |

- **触发**: 该球落袋时（一次性结算）
- **效果**: 获得 `floor(ball.totalGoldEarned * value)` 额外金币
- **渐进上限 50%**
- **统计范围**: `totalGoldEarned` 包含黄金弹钉、暴击、连击加成、余烬的所有金币
- **增强**: 其他 5 个增强效果推高 totalGoldEarned → 丰收奖金越大

```lua
-- 落袋结算时
if ball.totalGoldEarned and ball.totalGoldEarned > 0 then
    local harvestBonus = math.floor(ball.totalGoldEarned * goldHarvestVal)
    State.AddEarnings(harvestBonus)
end
```

### 黄金光环 `gold_aura`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | Lv.30 | 费用公式 |
|---------|------|-------|-------|-------|---------|
| `0.50 * (1 - 0.95^lv)` | 3% | 20% | 32% | 39% | cost(5, 1.9) |

- **触发**: 每次撞钉时
- **效果**: 被撞钉半径 30px 内的其他钉也触发黄金弹钉效果，产出为正常值的 `value` 比例
- **渐进上限 50%**
- **不递归**: 光环触发的钉不再触发光环
- **增强**: 等效增加撞钉次数 → 连击更容易维持 → 积累更快 → 余烬/丰收基数更大

```lua
local nearbyPegs = findPegsInRadius(peg, allPegs, 30)
for _, nearby in ipairs(nearbyPegs) do
    if not nearby.hitThisFrame then
        local auraGold = math.floor(pegGoldVal * goldAuraVal)
        State.AddEarnings(auraGold)
        ball.totalGoldEarned = (ball.totalGoldEarned or 0) + auraGold
        -- 光环触发也计入 pegHits（影响共鸣）
        ball.pegHits = ball.pegHits + 1
    end
end
```

**黄金增强内部循环**:
```
光环(扩大触发范围) → 连击(密集撞钉递增) → 暴击(概率3倍)
      ↑                                      ↓
      │              积累(球价值提升)          ↓
      │                   ↑                   ↓
      ←←←←← 丰收(落袋结算总产出) ←←← 余烬(持续产金)
```

---

## 独立弹钉效果

### 弹钉增值 `peg_value`（新增）

| 数值公式 | Lv.1 | Lv.10 | Lv.20 | 费用公式 |
|---------|------|-------|-------|---------|
| int(1, 1.20) | +1/钉 | +5/钉 | +31/钉 | cost(4, 1.8) |

- **触发**: 每次撞钉时
- **效果**: 该球基础价值（ball.value）临时增加 `value`，持续到该球落袋或消失
- **累计**: 撞 N 颗钉 → ball.value 增加 `N * value`
- **无前置条件**: 不依赖任何效果即可抽到
- **增强**: 球价值越高 → 落袋收益、共鸣、连锁等按 ball.value 计算的效果全部提升

```lua
ball.value = ball.value + pegValueVal
-- 例：铜球(3) 撞20颗钉，Lv.10 → 3 + 20*5 = 103
-- 落袋时 earning = 103 × slotMult（而非原始的 3 × slotMult）
```

---

## 删除的效果

### 双重撞击 `double_hit`（删除）

- **删除原因**: 与黄金弹钉重复
- **替换为**: 弹钉共鸣 `peg_resonance`
- **存档迁移**: `drawnEffects["double_hit"]` 等级转移至 `peg_resonance`

```lua
if data.drawnEffects and data.drawnEffects["double_hit"] then
    data.drawnEffects["peg_resonance"] = data.drawnEffects["double_hit"]
    data.drawnEffects["double_hit"] = nil
end
```

---

## 落袋结算顺序

```
撞钉时触发（按顺序）:
  1. pegHits++                          ← 计数
  2. 弹钉增值: ball.value += N           ← 球价值提升（影响落袋收益、共鸣、连锁等）
  3. 黄金积累: goldStackBonus += N       ← 增加该球后续黄金弹钉基础产出
  4. 黄金弹钉: +(pegGoldVal + bonus) 金币 ← 即时基础产出（含积累加成）
  5. 黄金暴击: 概率 ×3                   ← 放大黄金弹钉
  6. 黄金连击: 连续撞钉递增倍率           ← 放大黄金弹钉
  7. 黄金光环: 附近钉也产金               ← 扩展黄金弹钉
  8. 黄金余烬: 挂载 2 秒持续产金          ← 延迟（Update 中结算）
  9. 记录 totalGoldEarned                ← 丰收用
  10. 弹钉连锁: 连续撞钉额外金币           ← 即时
  11. 弹钉充能: 撞到充能钉额外金币         ← 即时
  12. 弹钉印记: 撞到印记钉时放大上述收益   ← 乘算
  13. 弹钉共振: 按场上球数放大上述收益      ← 乘算
  14. 弹钉宝石: 概率掉宝石                ← 独立
  15. 弹钉火花: 概率触发相邻钉(重走1-14)   ← 递归一次
  16. 球自带效果: 点金/灼烧               ← 独立
  17. 弹钉减速: 降低球速                  ← 物理
  18. 弹钉弹射: 增强弹跳                  ← 物理
  19. 弹钉波动: 推动附近球                ← 物理

落袋时触发:
  1. earning = ball.value × slotMult          ← ball.value 已含弹钉增值加成
  2. earning × (1 + resonanceVal × pegHits)   ← 弹钉共鸣
  3. earning += ball.value × bonusRatio        ← 聚财
  4. earning × (1 + magnetBonus)               ← 金币磁铁
  5. earning × (1 + comboBonus)                ← 连击风暴
  6. earning × critMult                        ← 暴击
  7. 黄金丰收: +floor(totalGoldEarned × val)  ← 黄金增强结算
```
