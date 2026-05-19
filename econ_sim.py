#!/usr/bin/env python3
"""
弹珠放置游戏 - 经济模拟器
模拟玩家从零开始的升级进度，输出时间线和曲线数据。
"""
import math, json

# ============================================================
# 当前配置 (从 Config/Idle.lua 镜像)
# ============================================================

GOLD_COIN_RATIO = 0.2
BALL_COIN_RATIO = 1.0

LEVEL_THRESHOLD_BASE = 100
LEVEL_THRESHOLD_GROWTH = 2.2

# -- 全局升级 (金币消费) --
# 目标: Tier1 @ 20s, Tier2 @ 5min, Tier3 @ 30min, Tier4 @ 4h, Tier5 @ 2d
# 全部满级需 ~30d
GLOBAL_UPGRADES = [
    # Tier 1  - 前20s~2min解锁
    {"id": "drop_cooldown",  "baseCost": 1,         "growth": 2.2,   "max": 15},
    {"id": "base_value",     "baseCost": 3,         "growth": 2.0,   "max": 30},
    {"id": "peg_gold",       "baseCost": 8,         "growth": 2.1,   "max": 20},
    # Tier 2  - 5~10min解锁
    {"id": "coin_magnet",    "baseCost": 120,       "growth": 2.2,   "max": 20},
    {"id": "crit_chance",    "baseCost": 500,       "growth": 2.3,   "max": 20},
    # Tier 3  - 30min~2h解锁
    {"id": "slot_base",      "baseCost": 5000,      "growth": 2.2,   "max": 15},
    {"id": "multi_drop",     "baseCost": 15000,     "growth": 2.5,   "max": 8},
    {"id": "crit_mult",      "baseCost": 40000,     "growth": 2.3,   "max": 20},
    # Tier 4  - 4~12h解锁
    {"id": "extra_ball",     "baseCost": 300000,    "growth": 3.0,   "max": 5},
    {"id": "sky_drop",       "baseCost": 800000,    "growth": 2.4,   "max": 12},
    {"id": "heavy_landing",  "baseCost": 2000000,   "growth": 2.3,   "max": 20},
    {"id": "combo_storm",    "baseCost": 5000000,   "growth": 2.2,   "max": 15},
    # Tier 5  - 2~7d解锁
    {"id": "slot_fortune",   "baseCost": 30000000,  "growth": 2.5,   "max": 12},
    {"id": "prestige_boost", "baseCost": 100000000, "growth": 2.4,   "max": 10},
    {"id": "earning_amp",    "baseCost": 300000000, "growth": 2.3,   "max": 15},
]

# -- 弹珠升级 (球币消费) --
# 目标: 首次购买 ~1min; 每关升级消耗持续增长
BALL_UPGRADES = [
    {"id": "ball_auto_drop",  "baseCost": 18,   "growth": 2.2,  "max": 15},
    {"id": "ball_base_value", "baseCost": 15,   "growth": 2.0,  "max": 25},
    {"id": "ball_multiplier", "baseCost": 50,   "growth": 2.4,  "max": 18},
    {"id": "ball_crit_boost", "baseCost": 35,   "growth": 2.3,  "max": 15},
    {"id": "ball_peg_chain",  "baseCost": 30,   "growth": 2.2,  "max": 15},
    {"id": "ball_elasticity", "baseCost": 40,   "growth": 2.3,  "max": 12},
]

def upgrade_cost(u, level):
    if level >= u["max"]:
        return float('inf')
    return math.ceil(u["baseCost"] * (u["growth"] ** level))


# ============================================================
# 收益模型
# ============================================================

def calc_income_rate(glevels, blevels):
    """计算每秒金币/球币产出"""
    # --- 掉落间隔 ---
    lv = glevels.get("drop_cooldown", 0)
    drop_cd = max(0.5, 3.5 / (1 + 0.15 * lv))

    # --- 弹珠基础价值 ---
    base_val = 1 + glevels.get("base_value", 0) * 0.5        # 降低: 每级+0.5 (原+1)
    ball_base = blevels.get("ball_base_value", 0) * 0.5       # 降低: 每级+0.5 (原+1)
    total_base = base_val + ball_base

    # --- 撞钉奖励（每次弹珠约撞8钉）---
    avg_pegs = 8
    peg_gold_per_ball = glevels.get("peg_gold", 0) * 0.5 * avg_pegs  # 降低: 每级+0.5/钉 (原+1)

    # --- 倍率 ---
    ball_mult = 1.0 + blevels.get("ball_multiplier", 0) * 0.08     # 降低: 每级+8% (原15%)
    coin_magnet = 1.0 + glevels.get("coin_magnet", 0) * 0.03       # 降低: 每级+3% (原5%)
    heavy_landing = 1.0 + glevels.get("heavy_landing", 0) * 0.04   # 降低: 每级+4% (原6%)
    earning_amp = 1.0 + glevels.get("earning_amp", 0) * 0.05       # 降低: 每级+5% (原8%)

    # --- 暴击 ---
    crit_pct = min(0.60, (glevels.get("crit_chance", 0) * 1.5 + blevels.get("ball_crit_boost", 0) * 1.0) / 100)  # 降低暴击率
    crit_mult = 2.0 + glevels.get("crit_mult", 0) * 0.12    # 降低: 每级+0.12x (原0.2x)
    crit_factor = 1.0 + crit_pct * (crit_mult - 1.0)

    # --- 撞钉递增（平均每球8钉） ---
    peg_chain_rate = blevels.get("ball_peg_chain", 0) * 0.02   # 降低: 每级+2%/钉 (原3%)
    chain_factor = 1.0 + avg_pegs * peg_chain_rate

    # --- 连击风暴（简化：假设平均2连击加成） ---
    combo_lv = glevels.get("combo_storm", 0)
    combo_factor = 1.0
    if combo_lv > 0:
        avg_combo = 2
        combo_factor = 1.0 + avg_combo * combo_lv * 0.03     # 降低: 每级+3%/次 (原5%)

    # --- 口袋祝福（期望值） ---
    fortune_lv = glevels.get("slot_fortune", 0)
    fortune_factor = 1.0
    if fortune_lv > 0:
        fortune_pct = min(0.40, fortune_lv * 0.03)            # 降低: 每级3%概率 (原4%), cap 40% (原50%)
        fortune_mult = 2 + fortune_lv // 6                     # 更慢的翻倍增长
        fortune_factor = 1.0 + fortune_pct * (fortune_mult - 1)

    # --- 落袋收益 ---
    landing_value = total_base * ball_mult * coin_magnet * heavy_landing * crit_factor * chain_factor * combo_factor * fortune_factor * earning_amp

    # --- 每次投放的球数 ---
    balls_per_drop = 1 + glevels.get("extra_ball", 0) * 1
    multi_drop_pct = glevels.get("multi_drop", 0) * 0.06       # 降低: 每级+6% (原8%)
    avg_balls = balls_per_drop * (1 + multi_drop_pct)

    # --- 天降弹珠（额外投放） ---
    sky_lv = glevels.get("sky_drop", 0)
    sky_balls_per_sec = 0
    if sky_lv > 0:
        sky_interval = max(1.0, 8.0 / (1 + 0.12 * sky_lv))
        sky_balls_per_sec = 1.0 / sky_interval

    # --- 自动掉落（球币投放） ---
    auto_lv = blevels.get("ball_auto_drop", 0)
    auto_balls_per_sec = 0
    if auto_lv > 0:
        auto_interval = max(0.8, 5.0 / (1 + 0.18 * auto_lv))
        auto_balls_per_sec = 1.0 / auto_interval

    # --- 总投放率 ---
    manual_drops_per_sec = 1.0 / drop_cd
    total_balls_per_sec = manual_drops_per_sec * avg_balls + sky_balls_per_sec + auto_balls_per_sec

    # --- 每球总收益 ---
    per_ball_total = landing_value + peg_gold_per_ball

    # --- 每秒总收益(原始) ---
    raw_income = total_balls_per_sec * per_ball_total

    gold_per_sec = raw_income * GOLD_COIN_RATIO
    ball_coin_per_sec = raw_income * BALL_COIN_RATIO

    return gold_per_sec, ball_coin_per_sec


# ============================================================
# 事件驱动模拟
# ============================================================

def simulate(max_time=30*24*3600, verbose=True):
    """模拟玩家的升级进度"""
    glevels = {u["id"]: 0 for u in GLOBAL_UPGRADES}
    blevels = {u["id"]: 0 for u in BALL_UPGRADES}
    gold = 0.0
    ball_coins = 0.0
    time = 0.0

    # 关卡系统
    current_level = 1
    level_ball_coins = 0.0  # 当前关累积球币

    g_lookup = {u["id"]: u for u in GLOBAL_UPGRADES}
    b_lookup = {u["id"]: u for u in BALL_UPGRADES}

    events = []  # (time, event_type, detail)

    # 里程碑
    tier_first = {}  # tier -> first unlock time
    level_times = {}
    upgrade_first_buy = {}  # id -> time of first purchase

    iteration = 0
    max_iter = 500000

    while time < max_time and iteration < max_iter:
        iteration += 1
        gold_rate, bc_rate = calc_income_rate(glevels, blevels)

        if gold_rate <= 0 and bc_rate <= 0:
            gold_rate = 0.2  # 初始手动最低收入
            bc_rate = 1.0

        # 找最便宜的可买升级
        best_wait = float('inf')
        best_type = None
        best_id = None

        for u in GLOBAL_UPGRADES:
            lv = glevels[u["id"]]
            cost = upgrade_cost(u, lv)
            if cost == float('inf'):
                continue
            need = max(0, cost - gold)
            wait = need / gold_rate if gold_rate > 0 else float('inf')
            if wait < best_wait:
                best_wait = wait
                best_type = "global"
                best_id = u["id"]

        for u in BALL_UPGRADES:
            lv = blevels[u["id"]]
            cost = upgrade_cost(u, lv)
            if cost == float('inf'):
                continue
            need = max(0, cost - ball_coins)
            wait = need / bc_rate if bc_rate > 0 else float('inf')
            if wait < best_wait:
                best_wait = wait
                best_type = "ball"
                best_id = u["id"]

        if best_wait == float('inf'):
            break

        # 推进时间
        time += best_wait
        gold += gold_rate * best_wait
        ball_coins += bc_rate * best_wait
        level_ball_coins += bc_rate * best_wait

        if time > max_time:
            break

        # 购买
        if best_type == "global":
            u = g_lookup[best_id]
            cost = upgrade_cost(u, glevels[best_id])
            gold -= cost
            glevels[best_id] += 1
            lv = glevels[best_id]
            events.append((time, "global", best_id, lv, cost))
            if best_id not in upgrade_first_buy:
                upgrade_first_buy[best_id] = time
                # 记录tier首次解锁
                tier_idx = GLOBAL_UPGRADES.index(u)
                if tier_idx < 3:
                    tier = 1
                elif tier_idx < 5:
                    tier = 2
                elif tier_idx < 8:
                    tier = 3
                elif tier_idx < 12:
                    tier = 4
                else:
                    tier = 5
                if tier not in tier_first:
                    tier_first[tier] = time
        else:
            u = b_lookup[best_id]
            cost = upgrade_cost(u, blevels[best_id])
            ball_coins -= cost
            blevels[best_id] += 1
            lv = blevels[best_id]
            events.append((time, "ball", best_id, lv, cost))
            if best_id not in upgrade_first_buy:
                upgrade_first_buy[best_id] = time

        # 检查关卡推进
        while True:
            threshold = LEVEL_THRESHOLD_BASE * (LEVEL_THRESHOLD_GROWTH ** (current_level - 1))
            if level_ball_coins >= threshold:
                level_ball_coins -= threshold
                current_level += 1
                level_times[current_level] = time
            else:
                break

    return events, tier_first, level_times, upgrade_first_buy, glevels, blevels


def format_time(seconds):
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        return f"{seconds/60:.1f}min"
    elif seconds < 86400:
        return f"{seconds/3600:.1f}h"
    else:
        return f"{seconds/86400:.1f}d"


def main():
    print("=" * 70)
    print("弹珠放置游戏 经济模拟 - 当前配置")
    print("=" * 70)

    events, tier_first, level_times, first_buy, glevels, blevels = simulate()

    # --- Tier 首次解锁时间 ---
    print("\n📊 全局升级 Tier 首次解锁:")
    for tier in sorted(tier_first.keys()):
        print(f"  Tier {tier}: {format_time(tier_first[tier])}")

    # --- 关卡解锁时间 ---
    print(f"\n📊 关卡解锁时间线 (共解锁到 Level {max(level_times.keys()) if level_times else 1}):")
    for lv in sorted(level_times.keys()):
        if lv <= 20 or lv % 5 == 0:
            print(f"  Level {lv:3d}: {format_time(level_times[lv])}")

    # --- 各升级首次购买 ---
    print("\n📊 全局升级首次购买时间:")
    for u in GLOBAL_UPGRADES:
        t = first_buy.get(u["id"], None)
        ts = format_time(t) if t else "未解锁"
        print(f"  {u['id']:20s}: {ts:>10s}  (baseCost={u['baseCost']})")

    print("\n📊 弹珠升级首次购买时间:")
    for u in BALL_UPGRADES:
        t = first_buy.get(u["id"], None)
        ts = format_time(t) if t else "未解锁"
        print(f"  {u['id']:20s}: {ts:>10s}  (baseCost={u['baseCost']})")

    # --- 收入曲线 (关键时间点) ---
    print("\n📊 收入曲线 (模拟关键时间点的收入率):")
    checkpoints = [10, 20, 30, 60, 120, 300, 600, 1800, 3600, 7200, 14400, 28800, 86400,
                   3*86400, 7*86400, 14*86400, 30*86400]

    # 重新跑一次简化模拟来获取各时间点的收入
    glevels2 = {u["id"]: 0 for u in GLOBAL_UPGRADES}
    blevels2 = {u["id"]: 0 for u in BALL_UPGRADES}
    cp_idx = 0
    prev_time = 0

    print(f"  {'Time':>10s}  {'Gold/s':>10s}  {'BallCoin/s':>12s}  {'Gold/min':>10s}")
    print(f"  {'-'*10}  {'-'*10}  {'-'*12}  {'-'*10}")

    for ev_time, ev_type, ev_id, ev_lv, ev_cost in events:
        # 在事件之前检查里程碑
        while cp_idx < len(checkpoints) and checkpoints[cp_idx] <= ev_time:
            cp = checkpoints[cp_idx]
            g_rate, b_rate = calc_income_rate(glevels2, blevels2)
            print(f"  {format_time(cp):>10s}  {g_rate:>10.1f}  {b_rate:>12.1f}  {g_rate*60:>10.1f}")
            cp_idx += 1

        # 应用事件
        if ev_type == "global":
            glevels2[ev_id] = ev_lv
        else:
            blevels2[ev_id] = ev_lv

    # 剩余检查点
    while cp_idx < len(checkpoints):
        cp = checkpoints[cp_idx]
        g_rate, b_rate = calc_income_rate(glevels2, blevels2)
        print(f"  {format_time(cp):>10s}  {g_rate:>10.1f}  {b_rate:>12.1f}  {g_rate*60:>10.1f}")
        cp_idx += 1

    # --- 最终等级 ---
    print("\n📊 模拟结束时各升级等级:")
    print("  全局升级:")
    for u in GLOBAL_UPGRADES:
        print(f"    {u['id']:20s}: Lv {glevels[u['id']]:3d} / {u['max']}")
    print("  弹珠升级:")
    for u in BALL_UPGRADES:
        print(f"    {u['id']:20s}: Lv {blevels[u['id']]:3d} / {u['max']}")

    print("\n" + "=" * 70)


if __name__ == "__main__":
    main()
