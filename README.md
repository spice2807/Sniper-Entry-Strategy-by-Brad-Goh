# Brad Goh's Sniper Entry Strategy — Coded & Backtested

**Free TradingView strategy + MT5 Expert Advisor by [Backtest the Hype](https://www.youtube.com/@backtestthehype)**

I coded Brad Goh's (The Trading Geek) sniper entry from his video *"How I Combine Liquidity Sweeps, Order Blocks and FVGs For SNIPER Entries"* — break of structure → liquidity sweep → order block → fair value gap — and backtested almost 6 years on EURUSD, NAS100 and Gold with real spreads and commission.

**Result: his main entry lost −500.7R. One rule — waiting for a 1-minute structure shift — cut that to −46R. And a prop-firm simulation still found payouts on losing versions.**

▶️ **Watch the video:** https://www.youtube.com/@backtestthehype
💬 **Free EAs + results on Telegram:** https://t.me/morbillzcapitalfx

> The strategy idea belongs to Brad Goh. The code, the exact definitions and the backtests are by Backtest the Hype. This is our mechanical reading of his model, not his official rules. For education and entertainment, not financial advice.

---

## What's in this repo

| File | What it is |
|---|---|
| `BTH_BradGoh_SMC.pine` | **TradingView strategy (v1.1).** Draws structure, sweeps, order blocks, FVGs and every trade like the position tool, plus a results panel. Visual check only — the MT5 EA is the real backtest. |
| `BTH_BradGoh_SMC_EA.mq5` | **MetaTrader 5 Expert Advisor (v1.02).** The backtest engine used in the video. All 5 test versions + a built-in prop-firm simulation. |
| `RULES.md` | The rules in plain English, no code. |

---

## The 5 versions (all 2R target, 1R = $1,000)

| Version | Entry |
|---|---|
| **V1** | Limit order at the order block, stop beyond it |
| **V2** | Limit order at the FVG (order block if none) — **Brad's main entry** |
| **V3** | Wait for a 1-minute structure shift inside the zone |
| **V4** | Touch candle must sweep liquidity, stop beyond that candle (our version of his advanced stop) |
| **V5** | V2, only in the direction of the 1-hour trend |

## Results — total R after costs

| Version | EURUSD | NAS100 | XAUUSD | All three |
|---|---|---|---|---|
| V1 OB limit | −258.8 | −103.2 | −80.2 | **−442.2** |
| V2 FVG (his main) | −289.6 | −129.8 | −81.3 | **−500.7** |
| V3 1-min shift | −26.3 | **+4.4** | −24.1 | **−46.0** |
| V4 sweep candle | −18.7 | +9.1 | −5.8 | **−15.5** (only 84 trades) |
| V5 + 1H trend | −196.0 | −46.8 | −40.5 | **−283.2** |

**Test details:** Fusion Markets · M5 · Dec 2020 → Sep 2026 · real spread + commission + swap · 1R = $1,000 · entries 07:00 London → 11:30 New York · max 2 trades/day per market.

**Data note (honest):** Fusion only keeps real tick history from ~March 2026 (EURUSD) / May 2026 (NAS100). Earlier years use ticks generated from 1-minute bars; Gold has no real ticks at all. The real-tick months show broadly the same result.

### What the data showed
- Brad's main entry (V2) was the **worst** version overall: 2,372 trades, 29.3% win rate, −500.7R. After costs you'd need about a 36% win rate just to break even.
- Tight stops are expensive: on EURUSD the median stop was ~3 pips, so costs ate ~0.18R per trade.
- **Patience helps:** waiting for the 1-minute shift (V3) cut losses by about 90%, and NAS100 V3 was the only positive full version.

### What if you traded it on a prop firm?
Simulated: 1% risk, Phase 1 +8%, Phase 2 +5%, payout at +5% (80% split), 10% max loss, $500 per challenge, restart after every result.
- **V2, all markets in one account:** 59 challenges, 4 payouts ($19,500), still **−$10,000** net.
- **EURUSD V3:** a losing strategy, but **+$6,394** net thanks to 2 payouts.
- Payouts on losing strategies come down to timing and luck. Don't treat them as an edge.

---

## How to use the TradingView strategy
1. TradingView → **Pine Editor** → delete everything, paste `BTH_BradGoh_SMC.pine` → **Save** → **Add to chart**.
2. Use a **5-minute** chart of EURUSD, NAS100 or XAUUSD.
3. Change only **TEST VERSION** (V1–V5) in the settings.

## How to use the MT5 EA
1. MT5: **File → Open Data Folder → MQL5 → Experts**, copy `BTH_BradGoh_SMC_EA.mq5` there, open in **MetaEditor**, press **Compile** (F7).
2. **Strategy Tester** (Ctrl+R): symbol EURUSD / NAS100 / XAUUSD, timeframe **M5**, modelling **Every tick based on real ticks**, dates 2021.01.01 → today.
3. **Inputs:** change only **Test version** (V1–V5). Results are in R; the prop-firm sim runs virtually inside the EA.
4. Every trade + every challenge is written to CSV in MetaTrader's **Common\Files** folder.

> ⚠️ Run it in the Strategy Tester or on demo first. Check your broker's session times (the EA uses real London/New York DST).

---

## Want to test YOUR strategy like this?
1-on-1 sessions: I walk you through my exact workflow — breaking down the rules, coding them into an indicator & EA (no coding experience needed), and reading the backtest.

👉 **Book here:** https://backtestthehype.ayomi2807.workers.dev/

## More from Backtest the Hype
- Patrick Wieland's 15-Minute ORB: https://github.com/spice2807/15-Minute-Opening-Range-Strategy-by-Patrick-Wieland
- YouTube: https://www.youtube.com/@backtestthehype

---

**Disclaimer:** Educational and entertainment content only. Not financial advice. Trading involves substantial risk of loss. Backtested performance does not guarantee future results. The strategy concept belongs to Brad Goh; this repository is an independent interpretation and is not affiliated with or endorsed by him.

© Backtest the Hype. The Pine Script is released under the Mozilla Public License 2.0.
