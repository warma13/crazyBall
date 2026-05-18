# 升级系统

> 更新时间: 2026-03-29  
> 版本: v3.0.0

---

## 概述

所有升级统一归入**抽取效果池** (`DRAW_EFFECTS`)，通过宝石抽取获得，所有效果**无限可升级**，数值由公式驱动。

共 **46 种效果**，按管线归属和功能分为以下类别：

| 类别 | 数量 | 管线模块 | 说明 |
|------|------|---------|------|
| 球属性效果 | 4 | BallEffects | 球创建时的价值、半径，每帧物理修改 |
| 球落袋效果 | 5 | BallEffects | 落袋时的冲击/聚财/暴击计算 |
| 球行为效果 | 1 | BallEffects | 幸运弹跳（不走公式模板） |
| 乘区强化效果 | **8** | BallEffects / Settlement | **NEW** 强化结算管线各独立乘区 |
| 口袋效果 | 2 | Settlement | 口袋祝福、金币磁铁 |
| 连击效果 | 1 | Settlement | 连击风暴 |
| 弹钉频率派 | 4 | PegEffects | 增加撞钉次数/碰撞范围 |
| 弹钉收益派 | 5 | PegEffects | 每次撞钉赚更多金币 |
| 弹钉协作派 | 4 | PegEffects | 多球互动增益 |
| 独立弹钉效果 | 1 | PegEffects | 弹钉增值 |
| 黄金弹钉增强 | 6 | PegEffects | 需解锁黄金弹钉 |
| 球型专属效果 | 7 | BallEffects / PegEffects / Physics | 各球强化 |
| 功能型效果 | 3 | main.lua / Physics | 天降/自动/多球 |

---

## 架构：三管线分工

```
球创建 ──────────────────────────────────────────────── 落袋结算
  │                                                      │
  ├─ BallEffects.GetBallValue()   球价值(+打磨+精炼)       ├─ Settlement.OnBallLanded()
  ├─ BallEffects.GetBallRadius()  球半径                  │   ├─ Step 1:  确定口袋
  │                                                      │   ├─ Step 2:  口袋祝福
  │  每帧物理循环                                         │   ├─ Step 3:  口袋连珠 ← NEW
  ├─ BallEffects.GetGravity()     重力                    │   ├─ Step 4:  BallEffects.GetLandingMult(+重力落袋)
  ├─ BallEffects.GetDamping()     弹跳衰减                │   ├─ Step 5:  基础收益 = value × mult
  ├─ BallEffects.ApplyLuckyBounce() 幸运弹跳              │   ├─ Step 6:  PegEffects.OnBallLanded() 共鸣/丰收
  │                                                      │   ├─ Step 7:  聚财(+意外之财)
  │  撞钉碰撞                                             │   ├─ Step 8:  金币磁铁
  └─ PegEffects.OnPegHit()                               │   ├─ Step 9:  暴击(+暴击之力)
      ├─ Phase 1: 球价值修改                               │   ├─ Step 10: 连击风暴(+连击狂热)
      ├─ Phase 2: 黄金弹钉产金                             │   ├─ Step 11: 收益放大 ← NEW
      ├─ Phase 3: 即时收益                                 │   ├─ Step 12: 入账
      └─ Phase 4: 物理修改                                │   └─ Step 13: 飘字
                                                         └─ Settlement.Update(dt) 连击计时器
```

**关键解耦**：Settlement 不知道球类型的存在，只通过 BallEffects 接口获取"这颗球的落袋属性是什么"。

---

## BallEffects 公式引擎

所有球属性通过**统一公式模板（两层六槽位）**计算：

```
内层 = base × (1+Σ加算基础) × Π(1+乘算基础_i) × Π直乘基础_i + 额外基础
最终 = 内层 × (1+Σ加算最终) × Π(1+乘算最终_i) × Π直乘最终_i
```

| 槽位 | 函数 | 叠加方式 | 适用场景 |
|------|------|---------|---------|
| `addBase` | `sumEffects(...)` | 多效果求和 → ×(1+sum) 一次 | 同类增益，收益递减 |
| `multBase` | `listEffects(...)` | 各效果独立 ×(1+v) | 不同来源，收益递增 |
| `directBase` | `listEffects(...)` | 各效果独立 ×v | 直接倍率 |
| `flatExtra` | 数值 | 内层末尾加法 | 固定额外值 |
| `addFinal` | `sumEffects(...)` | 外层加算 | 最终百分比加成 |
| `multFinal` | `listEffects(...)` | 外层乘算 | 最终独立乘算 |
| `directFinal` | `listEffects(...)` | 外层直乘 | 最终直接倍率 |

新增效果只需在对应 `Get*()` 函数的槽位声明中追加 id，无需改 Settlement/Physics。

---

## 抽取机制

- 货币: **宝石**
- 基础费用: `DRAW_COST = 3` 宝石
- 费用递增: `3 × 1.4^(已抽次数)`
- 数据结构: `drawnEffects = { [effectId] = level }` (level >= 1 表示已拥有)

---

## 数值公式

| 公式类型 | 函数 | 说明 |
|---------|------|------|
| 百分比 | `pctFormula(base, growth)` | `base × growth^(lv-1)`，无上限 |
| 整数 | `intFormula(base, growth)` | `floor(base × growth^(lv-1))` |
| 有上限百分比 | `cappedFormula(base, growth, cap)` | `min(cap, base × growth^(lv-1))` |
| 渐进上限 | `gradualFormula(cap, decay)` | `cap × (1 - decay^lv)`，趋近 cap 永不到达 |
| 升级费用 | `costFormula(base, growth)` | `floor(base × growth^(lv-1))` |

---

## 一、球属性效果 (BallEffects)

这些效果通过 BallEffects 公式引擎计算，影响球的创建属性和每帧物理。

### 增值 `multi_value`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.10, 1.22) | +10% | +22% | +67% | cost(4, 1.8) |

- **管线**: `BallEffects.GetBallValue()` → addBase 槽位
- **作用**: 球的基础价值 ×(1+value)，同时影响投放成本和落袋收益
- **公式**: `floor((baseValue × level × (1 + multi_value) + ball_polish) × (1 + ball_refine))`

### 巨型弹珠 `big_ball`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.15, 1.20) | +15% | +31% | +77% | cost(4, 1.8) |

- **管线**: `BallEffects.GetBallRadius()` → addBase 槽位
- **作用**: 球半径 ×(1+value)，碰撞范围增大
- **公式**: `floor(BALL_RADIUS × (1 + big_ball))`

### 加速 `speed_up`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.15, 1.20) | +15% | +31% | +77% | cost(3, 1.7) |

- **管线**: `BallEffects.GetGravity()` → addBase 槽位
- **作用**: 重力 ×(1+value)，球下落更快
- **公式**: `GRAVITY × (1 + speed_up) × Π(1 + impact.gravityMult-1)`

### 额外弹珠 `extra_ball`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(1, 1.18) | +1 | +1 | +4 | cost(6, 2.0) |

- **管线**: `Physics.DropMultipleBalls()` 直接读取
- **作用**: 投放数量 +floor(value)，每颗消耗金币
- **公式**: `总数 = 1 + multi_drop + extra_ball`

---

## 二、球落袋效果 (BallEffects → Settlement 调用)

这些效果在球落袋时由 Settlement 调用 BallEffects 接口获取，Settlement 不知道球类型。

### 暴击光环 `critical`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| capped(0.05, 1.15, 0.60) | 5%×2倍 | 8%×2倍 | 20%×3倍 | cost(4, 1.8) |

- **管线**: `BallEffects.RollCrit()` → 概率叠加到球自带暴击之上
- **作用**: 全局暴击概率，暴击时收益翻倍
- **倍率**: `2 + floor(lv / 5)` (每5级+1倍)
- **与钻石球**: 概率叠加，取较高倍率

### 钻石强化 `diamond_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 钻石球(暴击) | capped(0.05, 1.15, 0.60) | +5%×2倍 | +8%×3倍 | cost(6, 1.9) |

- **管线**: `BallEffects.RollCrit()` → 钻石球专属概率/倍率加成
- **作用**: 钻石球暴击概率 +value，暴击倍率 `2 + floor(lv/5)`
- **前提**: 需使用钻石球

### 翡翠强化 `emerald_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 翡翠球(聚财) | pct(0.08, 1.22) | +8% | +17% | cost(7, 1.9) |

- **管线**: `BallEffects.GetFortuneBonusRatio()` → addBase 槽位
- **作用**: 聚财奖金比例 +value
- **公式**: `bonusRatio(0.2) × (1 + emerald_boost) + windfall`，落袋时 `earning += floor(ball.value × ratio)`

### 陨石强化 `meteor_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 陨石球(冲击) | pct(0.12, 1.22) | +12% | +26% | cost(8, 2.0) |

- **管线**: `BallEffects.GetLandingMult()` → multBase 槽位（与 impact.multBonus 求和）
- **作用**: 落袋倍率加成 +value，Lv.3+ 附带震屏
- **公式**: `1.0 × (1 + heavy_landing) × (1 + impact.multBonus(0.3) + meteor_boost)`
- **副作用**: 震屏强度 = `min(1.5, 0.2 + lv × 0.12)`

### 铜球强化 `copper_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 铜球(弹力) | pct(0.10, 1.20) | +10% | +20% | cost(3, 1.7) |

- **管线**: `BallEffects.GetDamping()` → addBase 槽位（仅铜球时生效）
- **作用**: 铜球弹跳衰减 ×(1+value)，使球弹得更远
- **公式**: `eff.damping(0.78) × (1 + copper_boost)`

---

## 三、球行为效果 (BallEffects)

不走公式模板的行为类效果。

### 幸运弹跳 `lucky_bounce`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| capped(0.08, 1.15, 0.70) | 8% | 13% | 32% | cost(5, 1.8) |

- **管线**: `BallEffects.ApplyLuckyBounce()` 每帧调用
- **作用**: 球接近底部时施加水平推力偏向最高倍率口袋
- **触发区域**: 距底部 60px 以内

---

## 四、乘区强化效果 (BallEffects / Settlement) — NEW

这些效果专门强化结算管线中各独立乘区，每个效果对应一个此前空缺或薄弱的乘法层。

### 弹珠打磨 `ball_polish`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(3, 1.30) | +3 | +10 | +41 | cost(4, 1.8) |

- **管线**: `BallEffects.GetBallValue()` → flatExtra 槽位
- **目标乘区**: 球价值·额外基础
- **作用**: 球价值在乘算之后固定 +value，对低价值球提升显著

### 弹珠精炼 `ball_refine`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.06, 1.20) | +6% | +12% | +31% | cost(5, 1.9) |

- **管线**: `BallEffects.GetBallValue()` → addFinal 槽位
- **目标乘区**: 球价值·最终加算
- **作用**: 球最终价值 ×(1+value)，与 multi_value 独立相乘

### 重力落袋 `heavy_landing`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.05, 1.18) | +5% | +10% | +23% | cost(5, 1.9) |

- **管线**: `BallEffects.GetLandingMult()` → addBase 槽位（通用，所有球生效）
- **目标乘区**: 落袋倍率·通用加算
- **作用**: 所有球落袋倍率 ×(1+value)，与冲击效果（multBase）独立相乘
- **公式**: `1.0 × (1 + heavy_landing) × (1 + impact + meteor_boost)`

### 口袋连珠 `slot_streak`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.08, 1.20) | +8%/次 | +17%/次 | +43%/次 | cost(5, 1.8) |

- **管线**: Settlement Step 3（口袋祝福之后，落袋倍率之前）
- **目标乘区**: 口袋·连续
- **作用**: 连续落入同一口袋时，每次 mult ×(1 + value × (streakCount-1))
- **状态**: `gameState.lastLandingSlot` / `gameState.slotStreakCount`
- **飘字**: 2连珠起显示 "N连珠"

### 意外之财 `windfall`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.15, 0.95) | +1% | +5% | +10% | cost(5, 1.9) |

- **管线**: `BallEffects.GetFortuneBonusRatio()` → flatExtra 槽位（通用，所有球生效）
- **目标乘区**: 聚财·通用
- **作用**: 所有球获得聚财效果（非聚财球也可触发额外奖金），聚财球则在原有基础上叠加
- **公式**: 非聚财球 `ratio = windfall`；聚财球 `ratio = bonusRatio × (1 + emerald_boost) + windfall`

### 暴击之力 `crit_power`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.50, 1.15) | +0.5倍 | +0.87倍 | +2.0倍 | cost(6, 2.0) |

- **管线**: `BallEffects.RollCrit()` → critMult 直接加法
- **目标乘区**: 暴击·倍率独立加成
- **作用**: 暴击倍率 +value（不影响暴击概率），与钻石强化/暴击光环的倍率叠加
- **公式**: `critMult = max(2, 等级阶梯倍率) + crit_power`

### 连击狂热 `combo_frenzy`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.20, 1.18) | +20% | +39% | +92% | cost(5, 1.9) |

- **管线**: Settlement Step 10（连击风暴内部）
- **目标乘区**: 连击·增长率加速
- **作用**: 连击增长率 ×(1+value)，comboBonus 变为 `comboBonus × (1 + combo_frenzy)`
- **公式**: `earning × (1 + comboBonus × (1 + combo_frenzy) × (comboCount - 1))`

### 收益放大 `earning_amp`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.05, 1.18) | +5% | +10% | +23% | cost(8, 2.0) |

- **管线**: Settlement Step 11（连击风暴之后，入账之前）
- **目标乘区**: 最终收益乘区
- **作用**: 最终收益 ×(1+value)，在所有其他加成之后独立再乘
- **设计意图**: 费用最高的效果，但对所有收益等比放大

---

## 五、口袋与结算效果 (Settlement)

这些效果直接在 Settlement 管线中读取和应用。

### 口袋祝福 `slot_fortune`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| capped(0.05, 1.12, 0.50) | 5%×2倍 | 7%×2倍 | 15%×3倍 | cost(6, 1.9) |

- **管线**: Settlement Step 2
- **作用**: 概率触发口袋倍率翻倍
- **倍率**: `2 + floor(lv / 5)` (每5级+1倍)

### 金币磁铁 `coin_magnet`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.08, 1.20) | +8% | +16% | +42% | cost(3, 1.8) |

- **管线**: Settlement Step 8
- **作用**: 落袋最终收益 ×(1+value)
- **位置**: 在聚财、冲击之后，暴击之前

### 连击风暴 `combo`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.05, 1.18) | 2s+5%/次 | 3s+9%/次 | 4s+21%/次 | cost(4, 1.8) |

- **管线**: Settlement Step 10 + `Settlement.Update(dt)` 倒计时
- **作用**: 时间窗口内连续落袋，每次收益递增
- **窗口**: `min(12, 2 + floor(lv / 2))` 秒
- **公式**: `earning × (1 + value × (1 + combo_frenzy) × (comboCount - 1))`（连击狂热加速增长率）

---

## 六、弹钉频率派 (PegEffects · 撞更多钉)

### 弹钉磁场 `peg_magnet`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.80, 0.95) | +4% | +18% | +33% | cost(4, 1.8) |

- **管线**: `PegEffects.GetPegCollisionRadius()`（Physics 碰撞检测前调用）
- **作用**: 弹钉碰撞判定半径 ×(1+value)

### 弹钉减速 `peg_slow`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.50, 0.95) | -5% | -18% | -33% | cost(4, 1.7) |

- **管线**: `PegEffects.OnPegHit()` Phase 4
- **作用**: 撞钉后球速 ×(1-value)，更容易撞到下方的钉

### 弹钉火花 `peg_spark`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.50, 0.95) | 5% | 18% | 33% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 3 尾部
- **作用**: 概率触发最近一颗钉，递归一次（isSpark=true 防无限递归）

### 弹钉弹射 `peg_launch`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.80, 0.95) | +4% | +18% | +33% | cost(4, 1.8) |

- **管线**: `PegEffects.OnPegHit()` Phase 4
- **作用**: 撞钉弹跳速度 ×(1+value)，球飞得更远撞更多钉

---

## 七、弹钉收益派 (PegEffects · 撞钉赚更多)

### 弹钉共鸣 `peg_resonance`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.03, 1.20) | +3%/钉 | +6%/钉 | +19%/钉 | cost(4, 1.8) |

- **管线**: `PegEffects.OnBallLanded()` (Settlement Step 6 调用)
- **作用**: 落袋收益 ×(1 + value × pegHits)，撞钉越多收益越高

### 弹钉连锁 `peg_chain`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.10, 1.22) | +10%/连 | +22%/连 | +67%/连 | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 3
- **作用**: 0.3s 内连续撞钉，每连一次 +value×球价值 即时入账
- **计数**: `ball.chainCount`，超过 0.3s 间隔归零

### 弹钉宝石 `peg_gem`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.25, 0.95) | 1% | 5% | 10% | cost(6, 2.0) |

- **管线**: `PegEffects.OnPegHit()` Phase 3
- **作用**: 撞钉概率掉落 1 颗宝石（抽取货币）

### 弹钉增值 `peg_value`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(1, 1.20) | +1 | +2 | +5 | cost(4, 1.8) |

- **管线**: `PegEffects.OnPegHit()` Phase 1
- **作用**: 每次撞钉增加球的 value +value（永久，落袋时按最终 value 结算）

### 黄金弹钉 `peg_gold`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(1, 1.35) | +1 | +3 | +10 | cost(3, 1.7) |

- **管线**: `PegEffects.OnPegHit()` Phase 2
- **作用**: 撞钉直接获得金币，是黄金增强效果链的基础
- **前置**: 6 个黄金增强效果都 `requires = "peg_gold"`

---

## 八、弹钉协作派 (PegEffects · 多球互动)

### 弹钉充能 `peg_charge`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.20, 1.20) | +20% | +41% | +103% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 3
- **作用**: A 球撞钉标记充能（3s），B 球再撞该钉触发奖金 = floor(球价值 × value)
- **状态**: `peg.chargedBy` / `peg.chargeTimer`

### 弹钉印记 `peg_mark`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.15, 1.18) | +15% | +28% | +66% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 3（在 chain/charge/sync 之后）
- **作用**: A 球撞钉标记印记（5s），B 球再撞该钉时放大本次所有即时收益(pegHitBonus) × value
- **状态**: `peg.markedBy` / `peg.markTimer`

### 弹钉共振 `peg_sync`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| pct(0.04, 1.22) | +4%/球 | +9%/球 | +27%/球 | cost(6, 2.0) |

- **管线**: `PegEffects.OnPegHit()` Phase 3
- **作用**: 场上每多 1 颗球，本次 pegHitBonus × (value × 其他球数)

### 弹钉波动 `peg_wave`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(200, 0.95) | 10px/s | 64px/s | 103px/s | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 4
- **作用**: 撞钉时推动 40px 内的其他球向最近的钉子运动

---

## 九、黄金弹钉增强 (PegEffects · 需解锁黄金弹钉)

所有黄金增强效果的 `requires = "peg_gold"`，未拥有黄金弹钉时不会出现在抽取池中。

### 黄金积累 `gold_stack`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(1, 1.20) | +1 | +2 | +5 | cost(4, 1.8) |

- **管线**: `PegEffects.OnPegHit()` Phase 2（黄金产金前）
- **作用**: 每次撞钉增加 `ball.goldStackBonus` +value，滚雪球式增长黄金产出

### 黄金暴击 `gold_crit`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.30, 0.95) | 1% | 6% | 10% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 2（黄金产出后）
- **作用**: 概率使本次黄金产出 ×3

### 黄金连击 `gold_streak`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.50, 0.95) | 5% | 18% | 33% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 2（黄金暴击后）
- **作用**: 0.5s 内连续撞钉，黄金产出 ×(1 + value × streakCount)

### 黄金余烬 `gold_ember`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.40, 0.95) | 4% | 14% | 26% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 2 + `PegEffects.Update(dt)` tick
- **作用**: 黄金产出后 2s 内每 0.5s 持续产金，金额 = floor(goldEarning × value)
- **tick**: 4 次 × 0.5s = 2s

### 黄金丰收 `gold_harvest`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.50, 0.95) | 5% | 18% | 33% | cost(6, 2.0) |

- **管线**: `PegEffects.OnBallLanded()` (Settlement Step 6 调用)
- **作用**: 落袋时额外获得 `floor(ball.totalGoldEarned × value)` 金币

### 黄金光环 `gold_aura`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| gradual(0.50, 0.95) | 5% | 18% | 33% | cost(5, 1.9) |

- **管线**: `PegEffects.OnPegHit()` Phase 2（黄金产金后）
- **作用**: 30px 半径内每颗邻钉额外产金 = floor(goldEarning × value)

---

## 十、球型专属效果（分布在多个管线）

### 银球强化 `silver_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 银球(分裂) | level 本身 | 阈值-1 | 阈值-3+可重复分裂+分裂2球 | cost(4, 1.8) |

- **管线**: `Physics.UpdateBalls()` 碰撞循环（分裂涉及生成新球，保留在物理层）
- **作用**: 多维度强化分裂
  - 阈值降低: `max(1, threshold - min(lv, 3))`
  - Lv.3+: 可重复分裂，最大次数 = `1 + floor(lv / 3)`
  - 分裂球数 = `1 + floor(lv / 5)`

### 金球强化 `gold_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 金球(点金) | int(1, 1.35) | +1 | +3 | cost(5, 1.8) |

- **管线**: `PegEffects.OnPegHit()` → `_applyBallPegEffects()`
- **作用**: 点金撞钉金币 = `eff.pegBonus(1) + gold_boost`

### 红宝石强化 `ruby_boost`

| 对应球 | 数值公式 | Lv.1 | Lv.5 | 费用公式 |
|-------|---------|------|------|---------|
| 红宝石球(灼烧) | pct(1.5, 1.25) | ×1.5 | ×3.6 | cost(7, 1.9) |

- **管线**: `PegEffects.OnPegHit()` → `_applyBallPegEffects()`
- **作用**: 灼烧撞钉金币 = `eff.pegBonus(2) × ruby_boost`
- **注意**: 是乘法加成，高等级爆炸式增长

---

## 十一、功能型效果

### 天降弹珠 `sky_drop`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| `max(0.5, 6.0 × 0.85^(lv-1))` | 6.0s | 3.1s | 1.2s | cost(3, 1.7) |

- **管线**: `main.lua HandleUpdate()` → 定时器 → `Physics.DropSkyBall()`
- **作用**: 定时从顶部随机掉落免费铁球

### 自动投放 `auto_drop`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| `max(0.4, 3.0 × 0.82^(lv-1))` | 3.0s | 1.3s | 0.4s | cost(4, 1.8) |

- **管线**: `main.lua HandleUpdate()` → 定时器 → `Physics.DropMultipleBalls()`
- **作用**: 定时自动投放当前选中球（消耗金币），受多球/额外弹珠影响

### 多球投放 `multi_drop`

| 数值公式 | Lv.1 | Lv.5 | Lv.10 | 费用公式 |
|---------|------|------|-------|---------|
| int(1, 1.18) | +1球 | +1球 | +4球 | cost(5, 2.0) |

- **管线**: `Physics.DropMultipleBalls()` 直接读取
- **作用**: 每次投放额外 floor(value) 颗球
- **公式**: `总数 = 1 + multi_drop + extra_ball`

---

## 附录：结算管线完整步骤

```
Settlement.OnBallLanded(ball)
  Step 1:  确定口袋   → slotIndex, slotMult, slotColor
  Step 2:  口袋祝福   → 概率 mult × fortuneMult
  Step 3:  口袋连珠   → mult × (1 + slot_streak × (streakCount-1))     ← NEW
  Step 4:  落袋倍率   → mult × BallEffects.GetLandingMult(ball)         ← 重力落袋+冲击+陨石强化
  Step 5:  基础收益   → earning = floor(ball.value × mult)
  Step 6:  弹钉效果   → earning = PegEffects.OnBallLanded(ball, earning) ← 共鸣+丰收
  Step 7:  聚财奖金   → earning += floor(ball.value × ratio)             ← 聚财+翡翠+意外之财
  Step 8:  金币磁铁   → earning = floor(earning × (1 + coin_magnet))
  Step 9:  暴击判定   → isCrit, critMult(+crit_power); earning × critMult ← 暴击之力
  Step 10: 连击风暴   → earning × (1 + combo×(1+combo_frenzy)×(count-1))  ← 连击狂热
  Step 11: 收益放大   → earning = floor(earning × (1 + earning_amp))      ← NEW
  Step 12: 入账       → State.AddEarnings(earning)
  Step 13: 飘字       → popup (暴击/连击/连珠标识)
```
