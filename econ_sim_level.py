#!/usr/bin/env python3
"""
弹珠放置游戏 - 分关卡经济模拟器
专门追踪每个关卡内的球币升级（6个弹珠升级项）消耗节奏。
"""
import math

GOLD_COIN_RATIO = 0.2
BALL_COIN_RATIO = 1.0

# 目标: 第1关30min, 第2关1h, 第3关几小时, 全部关卡~1个月
# 初始球币收入约0.3/s, 30min累计约540, 但随升级增长到~2000+
# 需要 base 足够高让第1关持续30分钟
# 第1关30min内球币收入约: 前5min~2891(实测), 后续收入加速
# 30min总球币预估: ~30000-50000
LEVEL_THRESHOLD_BASE = 1800
LEVEL_THRESHOLD_GROWTH = 5.5

GLOBAL_UPGRADES = [
    {"id": "drop_cooldown",  "baseCost": 5,           "growth": 2.2,   "max": 15},
    {"id": "base_value",     "baseCost": 50,          "growth": 2.0,   "max": 30},
    {"id": "peg_gold",       "baseCost": 1000,        "growth": 2.1,   "max": 20},
    {"id": "coin_magnet",    "baseCost": 3000,        "growth": 2.2,   "max": 20},
    {"id": "crit_chance",    "baseCost": 10000,       "growth": 2.3,   "max": 20},
    {"id": "slot_base",      "baseCost": 30000,       "growth": 2.2,   "max": 15},
    {"id": "multi_drop",     "baseCost": 80000,       "growth": 2.5,   "max": 8},
    {"id": "crit_mult",      "baseCost": 200000,      "growth": 2.3,   "max": 20},
    {"id": "extra_ball",     "baseCost": 500000,      "growth": 3.0,   "max": 5},
    {"id": "sky_drop",       "baseCost": 1500000,     "growth": 2.4,   "max": 12},
    {"id": "heavy_landing",  "baseCost": 5000000,     "growth": 2.3,   "max": 20},
    {"id": "combo_storm",    "baseCost": 15000000,    "growth": 2.2,   "max": 15},
    {"id": "slot_fortune",   "baseCost": 50000000,    "growth": 2.5,   "max": 12},
    {"id": "prestige_boost", "baseCost": 200000000,   "growth": 2.4,   "max": 10},
    {"id": "earning_amp",    "baseCost": 800000000,   "growth": 2.3,   "max": 15},
]

BALL_UPGRADES = [
    {"id": "ball_auto_drop",  "baseCost": 20,       "growth": 2.2,  "max": 15},
    {"id": "ball_base_value", "baseCost": 300,      "growth": 2.0,  "max": 25},
    {"id": "ball_multiplier", "baseCost": 1000,     "growth": 2.4,  "max": 18},
    {"id": "ball_crit_boost", "baseCost": 5000,     "growth": 2.3,  "max": 15},
    {"id": "ball_peg_chain",  "baseCost": 50000,    "growth": 2.2,  "max": 15},
    {"id": "ball_elasticity", "baseCost": 500000,   "growth": 2.3,  "max": 12},
]

def upgrade_cost(u, level):
    if level >= u["max"]:
        return float('inf')
    return math.ceil(u["baseCost"] * (u["growth"] ** level))

def calc_income_rate(glevels, blevels):
    """分离计算：球升级→球币，全局升级→金币"""
    # === 共享：投球速率 ===
    lv = glevels.get("drop_cooldown", 0)
    drop_cd = max(0.5, 3.5 / (1 + 0.15 * lv))
    balls_per_drop = 1 + glevels.get("extra_ball", 0)
    multi_drop_pct = glevels.get("multi_drop", 0) * 0.06
    avg_balls = balls_per_drop * (1 + multi_drop_pct)
    sky_lv = glevels.get("sky_drop", 0)
    sky_bps = 0
    if sky_lv > 0:
        sky_bps = 1.0 / max(1.0, 8.0 / (1 + 0.12 * sky_lv))
    auto_lv = blevels.get("ball_auto_drop", 0)
    auto_bps = 0
    if auto_lv > 0:
        auto_bps = 1.0 / max(0.8, 5.0 / (1 + 0.18 * auto_lv))
    manual_dps = 1.0 / drop_cd
    total_bps = manual_dps * avg_balls + sky_bps + auto_bps
    avg_pegs = 8

    # === 球币路径：只受弹珠升级影响 ===
    ball_base_val = 1 + blevels.get("ball_base_value", 0) * 0.5
    ball_mult = 1.0 + blevels.get("ball_multiplier", 0) * 0.08
    ball_coin_value = ball_base_val * ball_mult
    # ball_peg_chain（弹珠升级）
    peg_chain_rate = blevels.get("ball_peg_chain", 0) * 0.02
    chain_factor = 1.0 + avg_pegs * peg_chain_rate
    # ball_crit_boost（弹珠升级）：独立暴击，固定2倍
    ball_crit_pct = min(0.60, blevels.get("ball_crit_boost", 0) * 1.0 / 100)
    ball_crit_factor = 1.0 + ball_crit_pct * (2.0 - 1.0)
    bc_per_ball = ball_coin_value * chain_factor * ball_crit_factor
    ball_coin_rate = total_bps * bc_per_ball

    # === 金币路径：只受全局升级影响 ===
    gold_base_val = 1 + glevels.get("base_value", 0) * 0.5
    gold_coin_value = gold_base_val
    coin_magnet = 1.0 + glevels.get("coin_magnet", 0) * 0.03
    heavy_landing = 1.0 + glevels.get("heavy_landing", 0) * 0.04
    earning_amp = 1.0 + glevels.get("earning_amp", 0) * 0.05
    # crit_chance + crit_mult（全局升级）
    crit_pct = min(0.60, glevels.get("crit_chance", 0) * 1.5 / 100)
    crit_mult = 2.0 + glevels.get("crit_mult", 0) * 0.12
    crit_factor = 1.0 + crit_pct * (crit_mult - 1.0)
    # combo_storm（全局升级）
    combo_lv = glevels.get("combo_storm", 0)
    combo_factor = 1.0
    if combo_lv > 0:
        combo_factor = 1.0 + 2 * combo_lv * 0.03
    # slot_fortune（全局升级）
    fortune_lv = glevels.get("slot_fortune", 0)
    fortune_factor = 1.0
    if fortune_lv > 0:
        fortune_pct = min(0.40, fortune_lv * 0.03)
        fortune_mult = 2 + fortune_lv // 6
        fortune_factor = 1.0 + fortune_pct * (fortune_mult - 1)
    # peg_gold（全局升级 → 只加金币）
    peg_gold_per_ball = glevels.get("peg_gold", 0) * 0.5 * avg_pegs
    gc_per_ball = gold_coin_value * coin_magnet * heavy_landing * crit_factor * combo_factor * fortune_factor * earning_amp + peg_gold_per_ball
    gold_coin_rate = total_bps * gc_per_ball

    return gold_coin_rate, ball_coin_rate

def level_threshold(level):
    """解锁第level+1关需要的累计球币"""
    if level <= 0:
        return 0
    return math.ceil(LEVEL_THRESHOLD_BASE * (LEVEL_THRESHOLD_GROWTH ** (level - 1)))

def format_time(s):
    if s < 60: return f"{s:.0f}s"
    if s < 3600: return f"{s/60:.1f}min"
    if s < 86400: return f"{s/3600:.1f}h"
    return f"{s/86400:.1f}d"


def simulate(max_time=90*24*3600):
    glevels = {u["id"]: 0 for u in GLOBAL_UPGRADES}
    blevels = {u["id"]: 0 for u in BALL_UPGRADES}
    gold = 0.0
    ball_coins = 0.0
    time = 0.0
    current_level = 1
    level_ball_earned = 0.0  # 当关累计球币（用于解锁判定）

    g_lookup = {u["id"]: u for u in GLOBAL_UPGRADES}
    b_lookup = {u["id"]: u for u in BALL_UPGRADES}

    # 追踪每关的球升级购买记录
    # level_buy_log[level] = [(time_in_level, upgrade_id, new_lv, cost), ...]
    level_buy_log = {1: []}
    level_start_time = {1: 0.0}
    level_end_time = {}

    # 追踪球升级总购买数
    ball_total_spent = 0.0
    ball_buys_in_level = {1: 0}
    ball_spent_in_level = {1: 0.0}
    ball_last_buy_time_in_level = {1: 0.0}

    iteration = 0
    max_iter = 800000

    while time < max_time and iteration < max_iter:
        iteration += 1
        gold_rate, bc_rate = calc_income_rate(glevels, blevels)
        if gold_rate <= 0 and bc_rate <= 0:
            gold_rate = 0.2
            bc_rate = 1.0

        # 找最便宜的可买升级
        best_wait = float('inf')
        best_type = None
        best_id = None

        for u in GLOBAL_UPGRADES:
            lv = glevels[u["id"]]
            cost = upgrade_cost(u, lv)
            if cost == float('inf'): continue
            need = max(0, cost - gold)
            wait = need / gold_rate if gold_rate > 0 else float('inf')
            if wait < best_wait:
                best_wait = wait
                best_type = "global"
                best_id = u["id"]

        for u in BALL_UPGRADES:
            lv = blevels[u["id"]]
            cost = upgrade_cost(u, lv)
            if cost == float('inf'): continue
            need = max(0, cost - ball_coins)
            wait = need / bc_rate if bc_rate > 0 else float('inf')
            if wait < best_wait:
                best_wait = wait
                best_type = "ball"
                best_id = u["id"]

        if best_wait == float('inf'):
            break

        time += best_wait
        gold += gold_rate * best_wait
        ball_coins += bc_rate * best_wait
        level_ball_earned += bc_rate * best_wait

        if time > max_time:
            break

        # 购买
        if best_type == "global":
            u = g_lookup[best_id]
            cost = upgrade_cost(u, glevels[best_id])
            gold -= cost
            glevels[best_id] += 1
        else:
            u = b_lookup[best_id]
            cost = upgrade_cost(u, blevels[best_id])
            ball_coins -= cost
            blevels[best_id] += 1
            ball_total_spent += cost

            # 记录到当前关卡
            if current_level not in level_buy_log:
                level_buy_log[current_level] = []
            level_buy_log[current_level].append((time, best_id, blevels[best_id], cost))
            ball_buys_in_level[current_level] = ball_buys_in_level.get(current_level, 0) + 1
            ball_spent_in_level[current_level] = ball_spent_in_level.get(current_level, 0) + cost
            ball_last_buy_time_in_level[current_level] = time

        # 检查关卡推进
        while True:
            threshold = level_threshold(current_level)
            if level_ball_earned >= threshold:
                level_end_time[current_level] = time
                level_ball_earned -= threshold
                current_level += 1
                level_start_time[current_level] = time
                if current_level not in level_buy_log:
                    level_buy_log[current_level] = []
                    ball_buys_in_level[current_level] = 0
                    ball_spent_in_level[current_level] = 0
                    ball_last_buy_time_in_level[current_level] = time
            else:
                break

    return (level_start_time, level_end_time, level_buy_log,
            ball_buys_in_level, ball_spent_in_level, ball_last_buy_time_in_level,
            blevels, glevels, current_level)


def main():
    print("=" * 70)
    print("弹珠放置游戏 - 分关卡球币升级节奏分析")
    print("=" * 70)

    (level_start, level_end, buy_log,
     buys_in_lv, spent_in_lv, last_buy_in_lv,
     blevels, glevels, max_level) = simulate()

    # === 关卡时长 & 球升级活动 ===
    print(f"\n📊 关卡解锁时间线 & 球升级活动 (共 {max_level} 关):")
    print(f"  {'关卡':>4s}  {'进入时间':>10s}  {'关卡时长':>10s}  {'球升级次数':>10s}  {'球币消耗':>12s}  {'最后购买':>10s}")
    print(f"  {'-'*4}  {'-'*10}  {'-'*10}  {'-'*10}  {'-'*12}  {'-'*10}")

    for lv in range(1, min(max_level + 1, 31)):
        start = level_start.get(lv, 0)
        end = level_end.get(lv, None)
        duration = (end - start) if end else "进行中"
        buys = buys_in_lv.get(lv, 0)
        spent = spent_in_lv.get(lv, 0)
        last = last_buy_in_lv.get(lv, start)

        dur_str = format_time(duration) if isinstance(duration, (int, float)) else duration
        last_relative = last - start if last > start else 0

        print(f"  {lv:4d}  {format_time(start):>10s}  {dur_str:>10s}  {buys:>10d}  {spent:>12.0f}  {format_time(last_relative):>10s}")

    # === 第1关详细购买记录 ===
    print(f"\n📊 第1关 球升级详细购买记录:")
    if 1 in buy_log and buy_log[1]:
        print(f"  {'时间':>10s}  {'升级项':>18s}  {'等级':>6s}  {'费用':>10s}")
        print(f"  {'-'*10}  {'-'*18}  {'-'*6}  {'-'*10}")
        for t, uid, lv, cost in buy_log[1]:
            print(f"  {format_time(t):>10s}  {uid:>18s}  Lv.{lv:<3d}  {cost:>10.0f}")
    else:
        print("  无购买记录")

    # === 第2关详细购买记录 ===
    print(f"\n📊 第2关 球升级详细购买记录:")
    if 2 in buy_log and buy_log[2]:
        print(f"  {'时间':>10s}  {'相对时间':>10s}  {'升级项':>18s}  {'等级':>6s}  {'费用':>10s}")
        print(f"  {'-'*10}  {'-'*10}  {'-'*18}  {'-'*6}  {'-'*10}")
        start2 = level_start.get(2, 0)
        for t, uid, lv, cost in buy_log[2]:
            print(f"  {format_time(t):>10s}  {format_time(t - start2):>10s}  {uid:>18s}  Lv.{lv:<3d}  {cost:>10.0f}")
    else:
        print("  无购买记录")

    # === 第3关详细购买记录 ===
    print(f"\n📊 第3关 球升级详细购买记录:")
    if 3 in buy_log and buy_log[3]:
        print(f"  {'时间':>10s}  {'相对时间':>10s}  {'升级项':>18s}  {'等级':>6s}  {'费用':>10s}")
        print(f"  {'-'*10}  {'-'*10}  {'-'*18}  {'-'*6}  {'-'*10}")
        start3 = level_start.get(3, 0)
        for t, uid, lv, cost in buy_log[3][:20]:  # 只显示前20条
            print(f"  {format_time(t):>10s}  {format_time(t - start3):>10s}  {uid:>18s}  Lv.{lv:<3d}  {cost:>10.0f}")
        if len(buy_log[3]) > 20:
            print(f"  ... 还有 {len(buy_log[3])-20} 条记录")
    else:
        print("  无购买记录")

    # === 球升级最终等级 ===
    print(f"\n📊 球升级最终等级:")
    for u in BALL_UPGRADES:
        print(f"  {u['id']:20s}: Lv {blevels[u['id']]:3d} / {u['max']}")

    # === 关键问题分析 ===
    print(f"\n📊 关键分析:")
    lv1_end = level_end.get(1, None)
    if lv1_end:
        print(f"  第1关时长: {format_time(lv1_end)}  (目标: 30min)")
    lv2_end = level_end.get(2, None)
    lv2_start = level_start.get(2, 0)
    if lv2_end:
        print(f"  第2关时长: {format_time(lv2_end - lv2_start)}  (目标: 1h)")
    lv3_end = level_end.get(3, None)
    lv3_start = level_start.get(3, 0)
    if lv3_end:
        print(f"  第3关时长: {format_time(lv3_end - lv3_start)}  (目标: 几小时)")

    lv1_buys = buys_in_lv.get(1, 0)
    lv1_spent = spent_in_lv.get(1, 0)
    print(f"  第1关球升级: {lv1_buys}次购买, 消耗{lv1_spent:.0f}球币")

    # 第1关球升级最后一次购买距进关多久
    if 1 in buy_log and buy_log[1]:
        last_t = buy_log[1][-1][0]
        print(f"  第1关最后球升级: {format_time(last_t)}  (距离第1关结束还有 {format_time(lv1_end - last_t) if lv1_end else '?'})")

    # 关卡门槛
    for lv in range(1, 6):
        print(f"  Level {lv} → {lv+1} 门槛: {level_threshold(lv):.0f} 球币")

    print("\n" + "=" * 70)


if __name__ == "__main__":
    main()
