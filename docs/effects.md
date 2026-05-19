# 效果大全

> 更新时间: 2026-03-29
> 版本: v5.0.0
> 效果总数: **76**

所有效果通过宝石抽取获得，无限可升级，数值由公式驱动。

---

## 目录

| # | 类别 | 数量 | 效果列表 |
|---|------|------|---------|
| 1 | [球属性效果](#1-球属性效果) | 4 | 增值、巨型弹珠、加速、额外弹珠 |
| 2 | [球落袋效果](#2-球落袋效果) | 5 | 暴击光环、钻石强化、翡翠强化、陨石强化、铜球强化 |
| 3 | [球行为效果](#3-球行为效果) | 1 | 幸运弹跳 |
| 4 | [乘区强化效果](#4-乘区强化效果) | 8 | 弹珠打磨、弹珠精炼、重力落袋、口袋连珠、意外之财、暴击之力、连击狂热、收益放大 |
| 5 | [口袋与结算效果](#5-口袋与结算效果) | 3 | 口袋祝福、金币磁铁、连击风暴 |
| 6 | [弹钉频率派](#6-弹钉频率派) | 4 | 弹钉磁场、弹钉减速、弹钉火花、弹钉弹射 |
| 7 | [弹钉收益派](#7-弹钉收益派) | 5 | 弹钉共鸣、弹钉连锁、弹钉宝石、弹钉增值、黄金弹钉 |
| 8 | [弹钉协作派](#8-弹钉协作派) | 4 | 弹钉充能、弹钉印记、弹钉共振、弹钉波动 |
| 9 | [黄金弹钉增强](#9-黄金弹钉增强) | 6 | 黄金积累、黄金暴击、黄金连击、黄金余烬、黄金丰收、黄金光环 |
| 10 | [球型专属效果](#10-球型专属效果) | 3 | 金球强化、红宝石强化、银球强化 |
| 11 | [功能型效果](#11-功能型效果) | 3 | 天降弹珠、自动投放、多球投放 |
| 12 | [流派A：时间掌控](#12-流派a时间掌控) | 4 | 时间收割、绝境爆发、时间结晶、急速心流 |
| 13 | [流派B：连锁反应](#13-流派b连锁反应) | 4 | 连锁闪电、回响打击、级联奖励、超载爆发 |
| 14 | [流派C：口袋大师](#14-流派c口袋大师) | 4 | 口袋轮转、口袋大奖、口袋回响、热门口袋 |
| 15 | [流派D：灼烧蔓延](#15-流派d灼烧蔓延) | 4 | 灼烧蔓延、灼烧余温、灼烧高潮、灼烧淬炼 |
| 16 | [流派E：分裂风暴](#16-流派e分裂风暴) | 4 | 分裂传承、分裂狂潮、分裂新星、分裂活力 |
| 17 | [流派F：巨力碾压](#17-流派f巨力碾压) | 4 | 巨力碾压、引力之井、成长动能、碾压震颤 |
| 18 | [连击补强](#18-连击补强) | 2 | 连击延续、连击爆发 |
| 19 | [聚财补强](#19-聚财补强) | 2 | 聚财积累、聚财共享 |
| 20 | [暴击补强](#20-暴击补强) | 2 | 暴击连锁、暴击震荡 |

---

## 数值公式说明

| 公式 | 写法 | 含义 |
|------|------|------|
| pct(base, growth) | `base × growth^(lv-1)` | 百分比，无上限 |
| int(base, growth) | `floor(base × growth^(lv-1))` | 整数，无上限 |
| capped(base, growth, cap) | `min(cap, base × growth^(lv-1))` | 百分比，有硬上限 |
| gradual(cap, decay) | `cap × (1 - decay^lv)` | 渐进趋近上限，永不到达 |
| cost(base, growth) | `floor(base × growth^(lv-1))` | 升级费用（宝石） |

---

## 1. 球属性效果

影响球的创建属性和每帧物理，由 BallEffects 公式引擎计算。

### 增值 `multi_value`

> 所有球基础价值提升

| 项 | 值 |
|----|-----|
| 数值 | pct(0.10, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | +10% / +22% / +67% |
| 费用 | cost(4, 1.8) |
| 管线位置 | BallEffects.GetBallValue() → addBase |
| 公式 | `floor((baseValue × level × (1 + multi_value) + ball_polish) × (1 + ball_refine))` |

---

### 巨型弹珠 `big_ball`

> 球半径增大，碰撞范围增大

| 项 | 值 |
|----|-----|
| 数值 | pct(0.15, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +15% / +31% / +77% |
| 费用 | cost(4, 1.8) |
| 管线位置 | BallEffects.GetBallRadius() → addBase |
| 公式 | `floor(BALL_RADIUS × (1 + big_ball))` |

---

### 加速 `speed_up`

> 重力增大，球下落更快

| 项 | 值 |
|----|-----|
| 数值 | pct(0.15, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +15% / +31% / +77% |
| 费用 | cost(3, 1.7) |
| 管线位置 | BallEffects.GetGravity() → addBase |
| 公式 | `GRAVITY × (1 + speed_up) × Π(1 + impact.gravityMult - 1)` |

---

### 额外弹珠 `extra_ball`

> 每次投放增加额外球数

| 项 | 值 |
|----|-----|
| 数值 | int(1, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +1 / +1 / +4 |
| 费用 | cost(6, 2.0) |
| 管线位置 | Physics.DropMultipleBalls() 直接读取 |
| 公式 | `总数 = 1 + multi_drop + extra_ball` |

---

## 2. 球落袋效果

球落袋时由 Settlement 调用 BallEffects 接口获取。

### 暴击光环 `critical`

> 全局暴击概率，暴击时收益翻倍

| 项 | 值 |
|----|-----|
| 数值 | capped(0.05, 1.15, 0.60) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 8% / 20% |
| 费用 | cost(4, 1.8) |
| 管线位置 | BallEffects.RollCrit() → 概率叠加 |
| 暴击倍率 | `2 + floor(lv / 5)` |
| 与钻石球 | 概率叠加，取较高倍率 |

---

### 钻石强化 `diamond_boost`

> 钻石球暴击概率和倍率额外提升

| 项 | 值 |
|----|-----|
| 对应球 | 钻石球（暴击） |
| 数值 | capped(0.05, 1.15, 0.60) |
| Lv.1 / Lv.5 | +5%×2倍 / +8%×3倍 |
| 费用 | cost(6, 1.9) |
| 管线位置 | BallEffects.RollCrit() → 钻石球专属加成 |
| 暴击倍率 | `2 + floor(lv / 5)` |
| 前提 | 需使用钻石球 |

---

### 翡翠强化 `emerald_boost`

> 翡翠球聚财奖金比例提升

| 项 | 值 |
|----|-----|
| 对应球 | 翡翠球（聚财） |
| 数值 | pct(0.08, 1.22) |
| Lv.1 / Lv.5 | +8% / +17% |
| 费用 | cost(7, 1.9) |
| 管线位置 | BallEffects.GetFortuneBonusRatio() → addBase |
| 公式 | `bonusRatio(0.2) × (1 + emerald_boost) + windfall` |

---

### 陨石强化 `meteor_boost`

> 陨石球冲击倍率提升，高级附带震屏

| 项 | 值 |
|----|-----|
| 对应球 | 陨石球（冲击） |
| 数值 | pct(0.12, 1.22) |
| Lv.1 / Lv.5 | +12% / +26% |
| 费用 | cost(8, 2.0) |
| 管线位置 | BallEffects.GetLandingMult() → multBase（与 impact.multBonus 求和） |
| 公式 | `1.0 × (1 + heavy_landing) × (1 + impact.multBonus(0.3) + meteor_boost)` |
| 副作用 | Lv.3+ 震屏，强度 = `min(1.5, 0.2 + lv × 0.12)` |

---

### 铜球强化 `copper_boost`

> 铜球弹跳衰减更小，弹得更远

| 项 | 值 |
|----|-----|
| 对应球 | 铜球（弹力） |
| 数值 | pct(0.10, 1.20) |
| Lv.1 / Lv.5 | +10% / +20% |
| 费用 | cost(3, 1.7) |
| 管线位置 | BallEffects.GetDamping() → addBase（仅铜球） |
| 公式 | `eff.damping(0.78) × (1 + copper_boost)` |

---

## 3. 球行为效果

不走公式模板的行为类效果。

### 幸运弹跳 `lucky_bounce`

> 球接近底部时偏向高倍率口袋

| 项 | 值 |
|----|-----|
| 数值 | capped(0.08, 1.15, 0.70) |
| Lv.1 / Lv.5 / Lv.10 | 8% / 13% / 32% |
| 费用 | cost(5, 1.8) |
| 管线位置 | BallEffects.ApplyLuckyBounce() 每帧调用 |
| 触发区域 | 距底部 60px 以内 |

---

## 4. 乘区强化效果

强化结算管线中各独立乘区，每个效果对应一个此前空缺或薄弱的乘法层。

### 弹珠打磨 `ball_polish`

> 球价值在乘算之后固定加值，对低价值球提升显著

| 项 | 值 |
|----|-----|
| 数值 | int(3, 1.30) |
| Lv.1 / Lv.5 / Lv.10 | +3 / +10 / +41 |
| 费用 | cost(4, 1.8) |
| 管线位置 | BallEffects.GetBallValue() → flatExtra |
| 目标乘区 | 球价值·额外基础 |

---

### 弹珠精炼 `ball_refine`

> 球最终价值百分比加成，与增值独立相乘

| 项 | 值 |
|----|-----|
| 数值 | pct(0.06, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +6% / +12% / +31% |
| 费用 | cost(5, 1.9) |
| 管线位置 | BallEffects.GetBallValue() → addFinal |
| 目标乘区 | 球价值·最终加算 |

---

### 重力落袋 `heavy_landing`

> 所有球落袋倍率通用加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +5% / +10% / +23% |
| 费用 | cost(5, 1.9) |
| 管线位置 | BallEffects.GetLandingMult() → addBase（通用） |
| 目标乘区 | 落袋倍率·通用加算 |
| 公式 | `1.0 × (1 + heavy_landing) × (1 + impact + meteor_boost)` |

---

### 口袋连珠 `slot_streak`

> 连续落入同一口袋时逐次叠加倍率

| 项 | 值 |
|----|-----|
| 数值 | pct(0.08, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +8%/次 / +17%/次 / +43%/次 |
| 费用 | cost(5, 1.8) |
| 管线位置 | Settlement Step 3 |
| 目标乘区 | 口袋·连续 |
| 公式 | `mult × (1 + value × (streakCount - 1))` |
| 状态跟踪 | `gameState.lastLandingSlot` / `gameState.slotStreakCount` |
| 飘字 | 2连珠起显示 "N连珠" |

---

### 意外之财 `windfall`

> 所有球获得聚财效果，聚财球额外叠加

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.15, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | +1% / +5% / +10% |
| 费用 | cost(5, 1.9) |
| 管线位置 | BallEffects.GetFortuneBonusRatio() → flatExtra（通用） |
| 目标乘区 | 聚财·通用 |
| 公式 | 非聚财球 `ratio = windfall`；聚财球 `ratio = bonusRatio × (1 + emerald_boost) + windfall` |

---

### 暴击之力 `crit_power`

> 暴击倍率直接加值，不影响概率

| 项 | 值 |
|----|-----|
| 数值 | pct(0.50, 1.15) |
| Lv.1 / Lv.5 / Lv.10 | +0.5倍 / +0.87倍 / +2.0倍 |
| 费用 | cost(6, 2.0) |
| 管线位置 | BallEffects.RollCrit() → critMult 加法 |
| 目标乘区 | 暴击·倍率独立加成 |
| 公式 | `critMult = max(2, 等级阶梯倍率) + crit_power` |

---

### 连击狂热 `combo_frenzy`

> 加速连击增长率

| 项 | 值 |
|----|-----|
| 数值 | pct(0.20, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +20% / +39% / +92% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 10（连击风暴内部） |
| 目标乘区 | 连击·增长率 |
| 公式 | `earning × (1 + comboBonus × (1 + combo_frenzy) × (comboCount - 1))` |

---

### 收益放大 `earning_amp`

> 所有加成之后的最终乘区，等比放大全部收益

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +5% / +10% / +23% |
| 费用 | cost(8, 2.0) |
| 管线位置 | Settlement Step 11 |
| 目标乘区 | 最终收益乘区 |
| 设计意图 | 费用最高，但对所有收益等比放大 |

---

## 5. 口袋与结算效果

直接在 Settlement 管线中读取和应用。

### 口袋祝福 `slot_fortune`

> 概率触发口袋倍率翻倍

| 项 | 值 |
|----|-----|
| 数值 | capped(0.05, 1.12, 0.50) |
| Lv.1 / Lv.5 / Lv.10 | 5%×2倍 / 7%×2倍 / 15%×3倍 |
| 费用 | cost(6, 1.9) |
| 管线位置 | Settlement Step 2 |
| 倍率 | `2 + floor(lv / 5)` |

---

### 金币磁铁 `coin_magnet`

> 落袋最终收益百分比加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.08, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +8% / +16% / +42% |
| 费用 | cost(3, 1.8) |
| 管线位置 | Settlement Step 8（聚财之后，暴击之前） |

---

### 连击风暴 `combo`

> 时间窗口内连续落袋，收益逐次递增

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | 2s+5%/次 / 3s+9%/次 / 4s+21%/次 |
| 费用 | cost(4, 1.8) |
| 管线位置 | Settlement Step 10 + Settlement.Update(dt) 倒计时 |
| 窗口时长 | `min(12, 2 + floor(lv / 2))` 秒 |
| 公式 | `earning × (1 + value × (1 + combo_frenzy) × (comboCount - 1))` |

---

## 6. 弹钉频率派

增加撞钉次数和碰撞范围，让球撞到更多钉子。

### 弹钉磁场 `peg_magnet`

> 弹钉碰撞判定半径增大

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.80, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | +4% / +18% / +33% |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.GetPegCollisionRadius() |

---

### 弹钉减速 `peg_slow`

> 撞钉后球速降低，更容易撞到下方的钉

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | -5% / -18% / -33% |
| 费用 | cost(4, 1.7) |
| 管线位置 | PegEffects.OnPegHit() Phase 4 |

---

### 弹钉火花 `peg_spark`

> 撞钉概率触发最近一颗钉，递归一次

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 18% / 33% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3 尾部 |
| 防递归 | isSpark=true 防无限递归 |

---

### 弹钉弹射 `peg_launch`

> 撞钉弹跳速度增大，球飞得更远撞更多钉

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.80, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | +4% / +18% / +33% |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 4 |

---

## 7. 弹钉收益派

每次撞钉产出更多金币或宝石。

### 弹钉共鸣 `peg_resonance`

> 落袋收益按撞钉次数加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.03, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +3%/钉 / +6%/钉 / +19%/钉 |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnBallLanded()（Settlement Step 6 调用） |
| 公式 | `earning × (1 + value × pegHits)` |

---

### 弹钉连锁 `peg_chain`

> 短时间内连续撞钉，每连一次即时入账

| 项 | 值 |
|----|-----|
| 数值 | pct(0.10, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | +10%/连 / +22%/连 / +67%/连 |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3 |
| 窗口 | 0.3s 内连续撞钉 |
| 公式 | 即时入账 `floor(球价值 × value × chainCount)` |

---

### 弹钉宝石 `peg_gem`

> 撞钉概率掉落宝石

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.25, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 1% / 5% / 10% |
| 费用 | cost(6, 2.0) |
| 管线位置 | PegEffects.OnPegHit() Phase 3 |
| 产出 | 每次 1 颗宝石 |

---

### 弹钉增值 `peg_value`

> 每次撞钉永久增加球价值

| 项 | 值 |
|----|-----|
| 数值 | int(1, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +1 / +2 / +5 |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 1 |
| 说明 | 永久增加，落袋时按最终 value 结算 |

---

### 黄金弹钉 `peg_gold`

> 撞钉直接获得金币，6 个黄金增强效果的前置

| 项 | 值 |
|----|-----|
| 数值 | int(1, 1.35) |
| Lv.1 / Lv.5 / Lv.10 | +1 / +3 / +10 |
| 费用 | cost(3, 1.7) |
| 管线位置 | PegEffects.OnPegHit() Phase 2 |
| 前置 | 6 个黄金增强效果的 `requires = "peg_gold"` |

---

## 8. 弹钉协作派

多球在场时的互动增益。

### 弹钉充能 `peg_charge`

> A 球撞钉充能，B 球再撞触发奖金

| 项 | 值 |
|----|-----|
| 数值 | pct(0.20, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +20% / +41% / +103% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3 |
| 充能时长 | 3 秒 |
| 公式 | 奖金 = `floor(球价值 × value)` |
| 状态 | `peg.chargedBy` / `peg.chargeTimer` |

---

### 弹钉印记 `peg_mark`

> A 球标记弹钉，B 球撞该钉时放大即时收益

| 项 | 值 |
|----|-----|
| 数值 | pct(0.15, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +15% / +28% / +66% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（chain/charge/sync 之后） |
| 印记时长 | 5 秒 |
| 公式 | `pegHitBonus × value` |
| 状态 | `peg.markedBy` / `peg.markTimer` |

---

### 弹钉共振 `peg_sync`

> 场上球数越多，撞钉收益越高

| 项 | 值 |
|----|-----|
| 数值 | pct(0.04, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | +4%/球 / +9%/球 / +27%/球 |
| 费用 | cost(6, 2.0) |
| 管线位置 | PegEffects.OnPegHit() Phase 3 |
| 公式 | `pegHitBonus × (value × 其他球数)` |

---

### 弹钉波动 `peg_wave`

> 撞钉时推动附近球向最近的钉子运动

| 项 | 值 |
|----|-----|
| 数值 | gradual(200, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 10px/s / 64px/s / 103px/s |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 4 |
| 范围 | 40px 内的其他球 |

---

## 9. 黄金弹钉增强

所有效果需要先拥有黄金弹钉（`requires = "peg_gold"`）。

### 黄金积累 `gold_stack`

> 撞钉滚雪球式增长黄金产出

| 项 | 值 |
|----|-----|
| 数值 | int(1, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +1 / +2 / +5 |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 2（黄金产金前） |
| 说明 | 每次撞钉增加 `ball.goldStackBonus` |

---

### 黄金暴击 `gold_crit`

> 概率使本次黄金产出 ×3

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.30, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 1% / 6% / 10% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 2（黄金产出后） |
| 暴击倍率 | ×3 |

---

### 黄金连击 `gold_streak`

> 短时间内连续撞钉，黄金产出逐次增大

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 18% / 33% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 2（黄金暴击后） |
| 窗口 | 0.5s 内连续撞钉 |
| 公式 | `黄金产出 × (1 + value × streakCount)` |

---

### 黄金余烬 `gold_ember`

> 黄金产出后持续 2 秒产金

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.40, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 4% / 14% / 26% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 2 + PegEffects.Update(dt) |
| 持续 | 4 次 × 0.5s = 2s |
| 公式 | 每 tick `floor(goldEarning × value)` |

---

### 黄金丰收 `gold_harvest`

> 落袋时按累计黄金产出额外获得金币

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 18% / 33% |
| 费用 | cost(6, 2.0) |
| 管线位置 | PegEffects.OnBallLanded()（Settlement Step 6 调用） |
| 公式 | `floor(ball.totalGoldEarned × value)` |

---

### 黄金光环 `gold_aura`

> 撞钉时附近钉子也产金

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 18% / 33% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 2（黄金产金后） |
| 范围 | 30px 半径内每颗邻钉 |
| 公式 | 每颗邻钉 `floor(goldEarning × value)` |

---

## 10. 球型专属效果

各球类型的专属强化效果。

### 银球强化 `silver_boost`

> 多维度强化银球分裂能力

| 项 | 值 |
|----|-----|
| 对应球 | 银球（分裂） |
| 数值 | level 本身 |
| 费用 | cost(4, 1.8) |
| 管线位置 | Physics.UpdateBalls() 碰撞循环 |
| Lv.1 | 阈值 -1 |
| Lv.3+ | 可重复分裂，最大次数 = `1 + floor(lv / 3)` |
| Lv.5+ | 分裂球数 = `1 + floor(lv / 5)` |
| 阈值公式 | `max(1, threshold - min(lv, 3))` |

---

### 金球强化 `gold_boost`

> 金球点金撞钉金币加成

| 项 | 值 |
|----|-----|
| 对应球 | 金球（点金） |
| 数值 | int(1, 1.35) |
| Lv.1 / Lv.5 | +1 / +3 |
| 费用 | cost(5, 1.8) |
| 管线位置 | PegEffects.OnPegHit() → _applyBallPegEffects() |
| 公式 | `eff.pegBonus(1) + gold_boost` |

---

### 红宝石强化 `ruby_boost`

> 红宝石球灼烧撞钉金币乘法加成

| 项 | 值 |
|----|-----|
| 对应球 | 红宝石球（灼烧） |
| 数值 | pct(1.5, 1.25) |
| Lv.1 / Lv.5 | ×1.5 / ×3.6 |
| 费用 | cost(7, 1.9) |
| 管线位置 | PegEffects.OnPegHit() → _applyBallPegEffects() |
| 公式 | `eff.pegBonus(2) × ruby_boost` |
| 说明 | 乘法加成，高等级爆炸式增长 |

---

## 11. 功能型效果

控制球的自动投放和产出节奏。

### 天降弹珠 `sky_drop`

> 定时从顶部随机掉落免费铁球

| 项 | 值 |
|----|-----|
| 数值 | `max(0.5, 6.0 × 0.85^(lv-1))` |
| Lv.1 / Lv.5 / Lv.10 | 6.0s / 3.1s / 1.2s |
| 费用 | cost(3, 1.7) |
| 管线位置 | main.lua HandleUpdate() → Physics.DropSkyBall() |
| 初始 | 游戏默认拥有 Lv.1 |

---

### 自动投放 `auto_drop`

> 定时自动投放当前选中球（消耗金币）

| 项 | 值 |
|----|-----|
| 数值 | `max(0.4, 3.0 × 0.82^(lv-1))` |
| Lv.1 / Lv.5 / Lv.10 | 3.0s / 1.3s / 0.4s |
| 费用 | cost(4, 1.8) |
| 管线位置 | main.lua HandleUpdate() → Physics.DropMultipleBalls() |
| 说明 | 受多球/额外弹珠影响 |

---

### 多球投放 `multi_drop`

> 每次投放额外球数

| 项 | 值 |
|----|-----|
| 数值 | int(1, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +1球 / +1球 / +4球 |
| 费用 | cost(5, 2.0) |
| 管线位置 | Physics.DropMultipleBalls() 直接读取 |
| 公式 | `总数 = 1 + multi_drop + extra_ball` |

---

## 12. 流派A：时间掌控

围绕轮次倒计时的效果，奖励高效过关和时间管理。

### 时间收割 `time_harvest`

> 每次撞钉延长倒计时

| 项 | 值 |
|----|-----|
| 数值 | pct(0.02, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +0.02s / +0.04s / +0.10s |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（灼烧后） |
| 上限 | 不超过 TIME_LIMIT × 2 |
| 说明 | 每次撞钉给倒计时续命，高撞钉频率流派受益最大 |

---

### 绝境爆发 `last_stand`

> 倒计时 ≤10s 时全部收益加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.10, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +10% / +19% / +44% |
| 费用 | cost(6, 2.0) |
| 管线位置 | Settlement Step 11.5 |
| 条件 | `roundTimeLeft <= 10` |
| 公式 | `earning × (1 + value)` |
| 说明 | 与时间收割反向搭配——收割延长时间推迟触发，绝境提高剩余时间内收益 |

---

### 时间结晶 `time_crystal`

> 过关时剩余秒数转化为额外金币

| 项 | 值 |
|----|-----|
| 数值 | pct(0.03, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | ×0.03 / ×0.07 / ×0.20 |
| 费用 | cost(5, 1.9) |
| 管线位置 | main.lua OnRoundSuccess()（gem 奖励前） |
| 公式 | `floor(remainingSeconds × value × avgSlotMult)` |
| 说明 | 奖励快速过关，剩余时间越多奖金越高 |

---

### 急速心流 `haste`

> 轮次前 15s 内收益加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.08, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +8% / +15% / +35% |
| 费用 | cost(4, 1.8) |
| 管线位置 | Settlement Step 11.6 |
| 条件 | `TIME_LIMIT - roundTimeLeft <= 15` |
| 公式 | `earning × (1 + value)` |
| 说明 | 与绝境爆发互补——开局加速 + 末尾爆发 |

---

## 13. 流派B：连锁反应

基于撞钉次数的爆发性收益增长。

### 连锁闪电 `chain_lightning`

> 撞钉时概率闪电击中最近一颗钉

| 项 | 值 |
|----|-----|
| 数值 | pct(0.15, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | 15% / 31% / 77% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（火花前） |
| 选择策略 | 最近且偏上方（加权距离 = dist + abs(dy) × 0.5） |
| 防递归 | isSpark=true，只触发一次 |
| 与弹钉火花区别 | 闪电概率更高、选择偏上方；火花概率低、选择纯最近 |

---

### 回响打击 `echo_hit`

> 撞钉 ≥10 次后，每次撞钉获得球价值百分比金币

| 项 | 值 |
|----|-----|
| 数值 | pct(0.06, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | +6% / +13% / +40% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（宝石后） |
| 条件 | `ball.pegHits >= 10` |
| 公式 | 即时入账 `floor(ball.value × value)` |
| 说明 | 奖励长途弹球，与弹钉增值/弹钉减速协作佳 |

---

### 级联奖励 `cascade_bonus`

> 每 5 次撞钉层数 +1，落袋时按层数加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.04, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +4%/层 / +8%/层 / +21%/层 |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 6.5 |
| 公式 | `earning × (1 + value × floor(pegHits / 5))` |
| 说明 | 类似弹钉共鸣但按层数跳跃增长 |

---

### 超载爆发 `overcharge`

> 撞钉次数超过阈值时，一次性 ×3 收益

| 项 | 值 |
|----|-----|
| 数值 | int(15, 1.25)（阈值随升级降低） |
| Lv.1 / Lv.5 / Lv.10 | 阈值 15 / 7 / 2 |
| 费用 | cost(6, 2.0) |
| 管线位置 | Settlement Step 9.5 |
| 条件 | `pegHits >= threshold` 且本次未触发过 |
| 公式 | `earning × 3` |
| 一次性 | 每次落袋只触发一次（`ball.overcharged = true`） |

---

## 14. 流派C：口袋大师

基于口袋使用模式的策略性收益。

### 口袋轮转 `slot_cycle`

> 连续落入不同口袋时，按连续不同口袋数加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.12, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +12%/个 / +25%/个 / +62%/个 |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 3.5 |
| 公式 | `earning × (1 + value × distinctCount)` |
| 状态 | `slotCycleHistory`（轮次重置） |
| 说明 | 与口袋连珠互斥——连珠奖励同一口袋，轮转奖励不同口袋 |

---

### 口袋大奖 `slot_jackpot`

> 本轮访问所有口袋后，下一次落袋获得爆发倍率

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | ×2.05 / ×2.10 / ×2.23 |
| 费用 | cost(7, 2.0) |
| 管线位置 | Settlement Step 3.6 |
| 触发 | 全部口袋覆盖 → `slotJackpotReady = true` → 下次落袋 `× (2 + value)` → 重置 |
| 状态 | `slotVisitedThisRound`、`slotJackpotReady`（轮次重置） |

---

### 口袋回响 `slot_echo`

> 落袋时给左右相邻口袋添加临时加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.10, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +10% / +21% / +51% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 2.5（读取）+ Step 3.7（写入） |
| 持续 | 3.0 秒 |
| 公式 | 临时加成 `earning × (1 + echoBonus)`，相邻口袋 = 当前 ±1 |
| 衰减 | PegEffects.Update(dt) 中计时器衰减 |

---

### 热门口袋 `hot_slot`

> 本轮落入最多的口袋获得额外加成

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +5% / +10% / +23% |
| 费用 | cost(4, 1.8) |
| 管线位置 | Settlement Step 2.6 |
| 条件 | 当前口袋是本轮落入次数最多的口袋 |
| 公式 | `earning × (1 + value)` |
| 状态 | `slotHitCountThisRound`（轮次重置） |

---

## 15. 流派D：灼烧蔓延

围绕红宝石球灼烧机制的衍生效果，需先拥有 `ruby_boost`。

### 灼烧蔓延 `burn_spread`

> 灼烧球撞钉时概率点燃附近的钉

| 项 | 值 |
|----|-----|
| 前置 | `ruby_boost` |
| 数值 | gradual(0.40, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 4% / 14% / 26% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（灼烧系列） |
| 范围 | 30px 内最近未燃烧的钉 |
| 状态 | 被点燃钉: `burning=true`, `burnTimer=3s`, `burnGold=ball.value×0.5` |

---

### 灼烧余温 `burn_linger`

> 撞到燃烧中的钉时获得额外金币

| 项 | 值 |
|----|-----|
| 前置 | `ruby_boost` |
| 数值 | pct(0.08, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +8% / +16% / +42% |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（灼烧蔓延后） |
| 公式 | 即时入账 `floor(peg.burnGold × value)` |
| 追踪 | `ball.burnEarned` / `ball.burnCount`（用于灼烧高潮） |

---

### 灼烧高潮 `burn_climax`

> 灼烧次数超过阈值时，落袋额外获得灼烧收益的 50%

| 项 | 值 |
|----|-----|
| 前置 | `ruby_boost` |
| 数值 | int(8, 1.22)（阈值随升级降低） |
| Lv.1 / Lv.5 / Lv.10 | 阈值 8 / 5 / 2 |
| 费用 | cost(6, 2.0) |
| 管线位置 | Settlement Step 9.6 |
| 条件 | `ball.burnCount >= threshold` |
| 公式 | `earning += floor(ball.burnEarned × 0.5)` |

---

### 灼烧淬炼 `burn_empower`

> 灼烧球每次撞钉永久增加球价值

| 项 | 值 |
|----|-----|
| 前置 | `ruby_boost` |
| 数值 | pct(0.03, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +3% / +6% / +16% |
| 费用 | cost(5, 1.9) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（灼烧余温后） |
| 公式 | `ball.value += floor(ball.value × value)` |
| 条件 | 仅灼烧球（isBlaze） |
| 追踪 | `ball.burnCount` 递增 |

---

## 16. 流派E：分裂风暴

围绕银球分裂机制的衍生效果，需先拥有 `silver_boost`。

### 分裂传承 `split_inherit`

> 分裂子球继承母球的弹钉增值

| 项 | 值 |
|----|-----|
| 前置 | `silver_boost` |
| 数值 | pct(0.50, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | 50% / 93% / 100%+ |
| 费用 | cost(5, 1.9) |
| 管线位置 | Physics.UpdateBalls() 分裂块 |
| 公式 | `inheritedValue = baseValue + floor(addedValue × value)` |
| 说明 | 与弹钉增值 `peg_value` 协作核心——增值越高传承越多 |

---

### 分裂狂潮 `split_frenzy`

> 每个存活的分裂球增加落袋收益

| 项 | 值 |
|----|-----|
| 前置 | `silver_boost` |
| 数值 | pct(0.10, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +10%/球 / +21%/球 / +51%/球 |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 9.7 |
| 公式 | `earning × (1 + value × splitBallCount)` |
| 说明 | 场上分裂球越多收益越高，奖励银球强化后的多次分裂 |

---

### 分裂新星 `split_nova`

> 分裂瞬间对范围内弹钉造成金币伤害

| 项 | 值 |
|----|-----|
| 前置 | `silver_boost` |
| 数值 | pct(0.20, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | 20% / 44% / 134% |
| 费用 | cost(6, 2.0) |
| 管线位置 | Physics.UpdateBalls() 分裂块 |
| 范围 | `ball.radius + 20` 像素 |
| 公式 | 范围内每颗钉 `floor(ball.value × value)` 即时入账 |
| 视觉 | 被击中钉子闪烁（`hitTimer = PEG_HIT_DURATION`） |

---

## 17. 流派F：巨力碾压

围绕球体积增长的力量型效果。

### 巨力碾压 `mass_impact`

> 球半径越大，落袋倍率越高

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +5%/10%增长 / +10%/10%增长 / +23%/10%增长 |
| 费用 | cost(5, 1.9) |
| 管线位置 | BallEffects.GetLandingMult() → addBase |
| 公式 | `massBonus = value × ((radius / baseRadius - 1) × 10)` |
| 说明 | 与巨型弹珠 `big_ball` 和成长动能协作——球越大倍率越高 |

---

### 引力之井 `gravity_well`

> 大球吸引周围小球飞向最近弹钉

| 项 | 值 |
|----|-----|
| 数值 | gradual(60, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 范围 3px / 19px / 31px |
| 费用 | cost(5, 1.9) |
| 管线位置 | Physics.UpdateBalls()（幸运弹跳前） |
| 条件 | 球半径 > BALL_RADIUS（只有增大了的球才产生引力） |
| 力学 | 找最近弹钉，施加方向力 `speed × (1 - dist/range)`，远处弱近处强 |

---

### 成长动能 `growth_momentum`

> 每次撞钉球半径小幅增大

| 项 | 值 |
|----|-----|
| 数值 | pct(0.01, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +1% / +2% / +5% |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 4（波动后） |
| 上限 | 最大 `baseRadius × 2` |
| 公式 | `ball.radius += baseRadius × value` |
| 说明 | 与巨力碾压/巨型弹珠组合——每次撞钉生长，落袋时按体积获得倍率 |

---

### 分裂活力 `split_vitality`

> 长寿分裂球获得额外落袋收益

| 项 | 值 |
|----|-----|
| 前置 | `silver_boost` |
| 数值 | int(5, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | 阈值5 / 阈值3 / 阈值2 |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 9.8 |
| 条件 | `ball.hasSplit and ball.pegHits >= value` |
| 公式 | `earning × 1.5` |
| 说明 | 奖励"活得久"的分裂球，搭配 peg_slow/peg_launch 延长分裂球路径 |

---

### 碾压震颤 `mass_quake`

> 大球落袋时全场弹钉产金

| 项 | 值 |
|----|-----|
| 数值 | pct(0.02, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | 2% / 4% / 10% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 11.8 |
| 条件 | `ball.radius >= baseRadius × 1.5` |
| 公式 | 每颗钉 `floor(ball.value × value)` 即时入账 |
| 说明 | 需要 big_ball + growth_momentum 双重投资稳定触发，全场事件 |

---

## 18. 连击补强

强化连击流派的维护和爆发能力。

### 连击延续 `combo_extend`

> 撞钉延长连击窗口

| 项 | 值 |
|----|-----|
| 数值 | pct(0.10, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +0.10s / +0.19s / +0.44s |
| 费用 | cost(4, 1.8) |
| 管线位置 | PegEffects.OnPegHit() Phase 3（灼烧后、时间收割前） |
| 条件 | `comboTimer > 0`（连击窗口已开启） |
| 公式 | `comboTimer += value` |
| 说明 | 解决连击窗口只在落袋时刷新的痛点，撞钉也能续命连击 |

---

### 连击爆发 `combo_burst`

> 连击达到阈值时落袋收益翻倍

| 项 | 值 |
|----|-----|
| 数值 | int(10, 1.22) |
| Lv.1 / Lv.5 / Lv.10 | 阈值10 / 阈值5 / 阈值3 |
| 费用 | cost(6, 2.0) |
| 管线位置 | Settlement Step 10.5（连击计算后） |
| 限制 | 每轮最多触发 3 次 |
| 公式 | `earning × 2` |
| 说明 | 与 combo_frenzy 形成"持续增长 vs 阈值爆发"双重收益 |

---

## 19. 聚财补强

强化聚财流派的滚雪球和辐射能力。

### 聚财积累 `fortune_stack`

> 每次聚财落袋永久提升本轮聚财比例

| 项 | 值 |
|----|-----|
| 数值 | pct(0.02, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | +2% / +4% / +10% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 7.5（聚财奖金计算后） |
| 状态 | `gameState.fortuneStackBonus`（轮次重置） |
| 公式 | 下次聚财 `fortuneRatio += fortuneStackBonus` |
| 说明 | 聚财越多越强，10 次聚财落袋后额外 +20%（Lv.1） |

---

### 聚财共享 `fortune_share`

> 聚财球落袋后短时间内其他球也享受聚财

| 项 | 值 |
|----|-----|
| 数值 | gradual(0.50, 0.95) |
| Lv.1 / Lv.5 / Lv.10 | 比例2% / 11% / 20% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 7.6（聚财球落袋时设置）+ Step 7（非聚财球读取） |
| 状态 | `fortuneShareTimer`（3s 倒计时）, `fortuneShareRatio`（快照） |
| 公式 | 非聚财球 `fortuneRatio += shareVal × snapshotRatio` |
| 说明 | 翡翠球 = 团队辅助，鼓励混编而非纯翡翠球编队 |

---

## 20. 暴击补强

强化暴击流派的策略深度和范围效果。

### 暴击连锁 `crit_streak`

> 连续暴击时倍率递增

| 项 | 值 |
|----|-----|
| 数值 | pct(0.30, 1.18) |
| Lv.1 / Lv.5 / Lv.10 | +0.30/次 / +0.58/次 / +1.33/次 |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 9.1（暴击判定后） |
| 状态 | `gameState.critStreakCount`（不暴击时归零） |
| 公式 | `critMult += value × (streakCount - 1)` |
| 说明 | 第2次暴击 +0.3 倍率，第3次 +0.6，赌性十足 |

---

### 暴击震荡 `crit_shock`

> 暴击时对周围弹钉产生金币冲击

| 项 | 值 |
|----|-----|
| 数值 | pct(0.05, 1.20) |
| Lv.1 / Lv.5 / Lv.10 | 5% / 10% / 26% |
| 费用 | cost(5, 1.9) |
| 管线位置 | Settlement Step 9.2（暴击确认后） |
| 范围 | 30px 内弹钉 |
| 公式 | 每颗钉 `floor(ball.value × value)` 即时入账 |
| 说明 | 暴击不仅倍率高，还有范围辐射，与暴击之力高倍率协同 |

---

## 附录：快速索引

按 ID 字母排序，快速查找效果。

| ID | 名称 | 类别 | 公式 | 费用 |
|----|------|------|------|------|
| `auto_drop` | 自动投放 | 功能型 | 自定义 | cost(4, 1.8) |
| `ball_polish` | 弹珠打磨 | 乘区强化 | int(3, 1.30) | cost(4, 1.8) |
| `ball_refine` | 弹珠精炼 | 乘区强化 | pct(0.06, 1.20) | cost(5, 1.9) |
| `big_ball` | 巨型弹珠 | 球属性 | pct(0.15, 1.20) | cost(4, 1.8) |
| `burn_climax` | 灼烧高潮 | 流派D | int(8, 1.22) | cost(6, 2.0) |
| `burn_empower` | 灼烧淬炼 | 流派D | pct(0.03, 1.20) | cost(5, 1.9) |
| `burn_linger` | 灼烧余温 | 流派D | pct(0.08, 1.20) | cost(4, 1.8) |
| `burn_spread` | 灼烧蔓延 | 流派D | gradual(0.40, 0.95) | cost(5, 1.9) |
| `cascade_bonus` | 级联奖励 | 流派B | pct(0.04, 1.20) | cost(5, 1.9) |
| `chain_lightning` | 连锁闪电 | 流派B | pct(0.15, 1.20) | cost(5, 1.9) |
| `coin_magnet` | 金币磁铁 | 结算 | pct(0.08, 1.20) | cost(3, 1.8) |
| `combo` | 连击风暴 | 结算 | pct(0.05, 1.18) | cost(4, 1.8) |
| `combo_burst` | 连击爆发 | 连击补强 | int(10, 1.22) | cost(6, 2.0) |
| `combo_extend` | 连击延续 | 连击补强 | pct(0.10, 1.18) | cost(4, 1.8) |
| `combo_frenzy` | 连击狂热 | 乘区强化 | pct(0.20, 1.18) | cost(5, 1.9) |
| `copper_boost` | 铜球强化 | 球落袋 | pct(0.10, 1.20) | cost(3, 1.7) |
| `crit_power` | 暴击之力 | 乘区强化 | pct(0.50, 1.15) | cost(6, 2.0) |
| `crit_shock` | 暴击震荡 | 暴击补强 | pct(0.05, 1.20) | cost(5, 1.9) |
| `crit_streak` | 暴击连锁 | 暴击补强 | pct(0.30, 1.18) | cost(5, 1.9) |
| `critical` | 暴击光环 | 球落袋 | capped(0.05, 1.15, 0.60) | cost(4, 1.8) |
| `diamond_boost` | 钻石强化 | 球落袋 | capped(0.05, 1.15, 0.60) | cost(6, 1.9) |
| `earning_amp` | 收益放大 | 乘区强化 | pct(0.05, 1.18) | cost(8, 2.0) |
| `echo_hit` | 回响打击 | 流派B | pct(0.06, 1.22) | cost(5, 1.9) |
| `emerald_boost` | 翡翠强化 | 球落袋 | pct(0.08, 1.22) | cost(7, 1.9) |
| `extra_ball` | 额外弹珠 | 球属性 | int(1, 1.18) | cost(6, 2.0) |
| `fortune_share` | 聚财共享 | 聚财补强 | gradual(0.50, 0.95) | cost(5, 1.9) |
| `fortune_stack` | 聚财积累 | 聚财补强 | pct(0.02, 1.20) | cost(5, 1.9) |
| `gold_aura` | 黄金光环 | 黄金增强 | gradual(0.50, 0.95) | cost(5, 1.9) |
| `gold_boost` | 金球强化 | 球型专属 | int(1, 1.35) | cost(5, 1.8) |
| `gold_crit` | 黄金暴击 | 黄金增强 | gradual(0.30, 0.95) | cost(5, 1.9) |
| `gold_ember` | 黄金余烬 | 黄金增强 | gradual(0.40, 0.95) | cost(5, 1.9) |
| `gold_harvest` | 黄金丰收 | 黄金增强 | gradual(0.50, 0.95) | cost(6, 2.0) |
| `gold_stack` | 黄金积累 | 黄金增强 | int(1, 1.20) | cost(4, 1.8) |
| `gold_streak` | 黄金连击 | 黄金增强 | gradual(0.50, 0.95) | cost(5, 1.9) |
| `gravity_well` | 引力之井 | 流派F | gradual(60, 0.95) | cost(5, 1.9) |
| `growth_momentum` | 成长动能 | 流派F | pct(0.01, 1.20) | cost(4, 1.8) |
| `haste` | 急速心流 | 流派A | pct(0.08, 1.18) | cost(4, 1.8) |
| `heavy_landing` | 重力落袋 | 乘区强化 | pct(0.05, 1.18) | cost(5, 1.9) |
| `hot_slot` | 热门口袋 | 流派C | pct(0.05, 1.18) | cost(4, 1.8) |
| `last_stand` | 绝境爆发 | 流派A | pct(0.10, 1.18) | cost(6, 2.0) |
| `lucky_bounce` | 幸运弹跳 | 球行为 | capped(0.08, 1.15, 0.70) | cost(5, 1.8) |
| `mass_impact` | 巨力碾压 | 流派F | pct(0.05, 1.18) | cost(5, 1.9) |
| `mass_quake` | 碾压震颤 | 流派F | pct(0.02, 1.20) | cost(5, 1.9) |
| `meteor_boost` | 陨石强化 | 球落袋 | pct(0.12, 1.22) | cost(8, 2.0) |
| `multi_drop` | 多球投放 | 功能型 | int(1, 1.18) | cost(5, 2.0) |
| `multi_value` | 增值 | 球属性 | pct(0.10, 1.22) | cost(4, 1.8) |
| `overcharge` | 超载爆发 | 流派B | int(15, 1.25) | cost(6, 2.0) |
| `peg_chain` | 弹钉连锁 | 弹钉收益 | pct(0.10, 1.22) | cost(5, 1.9) |
| `peg_charge` | 弹钉充能 | 弹钉协作 | pct(0.20, 1.20) | cost(5, 1.9) |
| `peg_gem` | 弹钉宝石 | 弹钉收益 | gradual(0.25, 0.95) | cost(6, 2.0) |
| `peg_gold` | 黄金弹钉 | 弹钉收益 | int(1, 1.35) | cost(3, 1.7) |
| `peg_launch` | 弹钉弹射 | 弹钉频率 | gradual(0.80, 0.95) | cost(4, 1.8) |
| `peg_magnet` | 弹钉磁场 | 弹钉频率 | gradual(0.80, 0.95) | cost(4, 1.8) |
| `peg_mark` | 弹钉印记 | 弹钉协作 | pct(0.15, 1.18) | cost(5, 1.9) |
| `peg_resonance` | 弹钉共鸣 | 弹钉收益 | pct(0.03, 1.20) | cost(4, 1.8) |
| `peg_slow` | 弹钉减速 | 弹钉频率 | gradual(0.50, 0.95) | cost(4, 1.7) |
| `peg_spark` | 弹钉火花 | 弹钉频率 | gradual(0.50, 0.95) | cost(5, 1.9) |
| `peg_sync` | 弹钉共振 | 弹钉协作 | pct(0.04, 1.22) | cost(6, 2.0) |
| `peg_value` | 弹钉增值 | 弹钉收益 | int(1, 1.20) | cost(4, 1.8) |
| `peg_wave` | 弹钉波动 | 弹钉协作 | gradual(200, 0.95) | cost(5, 1.9) |
| `ruby_boost` | 红宝石强化 | 球型专属 | pct(1.5, 1.25) | cost(7, 1.9) |
| `silver_boost` | 银球强化 | 球型专属 | level | cost(4, 1.8) |
| `sky_drop` | 天降弹珠 | 功能型 | 自定义 | cost(3, 1.7) |
| `slot_cycle` | 口袋轮转 | 流派C | pct(0.12, 1.20) | cost(5, 1.9) |
| `slot_echo` | 口袋回响 | 流派C | pct(0.10, 1.20) | cost(5, 1.9) |
| `slot_fortune` | 口袋祝福 | 结算 | capped(0.05, 1.12, 0.50) | cost(6, 1.9) |
| `slot_jackpot` | 口袋大奖 | 流派C | pct(0.05, 1.18) | cost(7, 2.0) |
| `slot_streak` | 口袋连珠 | 乘区强化 | pct(0.08, 1.20) | cost(5, 1.8) |
| `speed_up` | 加速 | 球属性 | pct(0.15, 1.20) | cost(3, 1.7) |
| `split_frenzy` | 分裂狂潮 | 流派E | pct(0.10, 1.20) | cost(5, 1.9) |
| `split_inherit` | 分裂传承 | 流派E | pct(0.50, 1.18) | cost(5, 1.9) |
| `split_nova` | 分裂新星 | 流派E | pct(0.20, 1.22) | cost(6, 2.0) |
| `split_vitality` | 分裂活力 | 流派E | int(5, 1.20) | cost(5, 1.9) |
| `time_crystal` | 时间结晶 | 流派A | pct(0.03, 1.22) | cost(5, 1.9) |
| `time_harvest` | 时间收割 | 流派A | pct(0.02, 1.20) | cost(5, 1.9) |
| `windfall` | 意外之财 | 乘区强化 | gradual(0.15, 0.95) | cost(5, 1.9) |
