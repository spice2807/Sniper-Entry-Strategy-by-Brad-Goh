# Brad Goh's Sniper Entry: The Rules, Written Out

Everything the EA does, in plain English.

## 1. His rules (as he teaches them)
1. A **break of structure** sets the direction and the range.
2. Wait for a **liquidity sweep**: price runs a swing / equal low (high) and rejects. No sweep, no trade.
3. **Order block** = the full high-to-low of the origin candle of the move.
4. **Fair value gap** = 3-candle gap in the move, inside or near the order block. No FVG → use the order block.
5. Wait for price to come back. **Aggressive** = enter on the touch. **Conservative** = wait for a lower-timeframe shift. Stop beyond the zone, **target 2R**. Advanced: stop beyond the entry candle when it swept liquidity.

## 2. Our definitions (the parts the video doesn't pin down — OUR CALL, not his words)
- **Swing** = Backtest the Hype qualified swing: a 2+ candle push with an anchor candle, confirmed when price closes past the anchor close. Swing price = the extreme of the whole push.
- **Sequence:** break of structure first → the pullback sweeps a swing / equal low inside the range (wick through, close back within 3 candles; a used level can't be swept again) → **displacement** (a body ≥ 1× ATR14 closing beyond the origin candle, within 12 candles) → the setup arms one candle later.
- **Order block** = the last opposite candle before the move, full high to low.
- **FVG** must overlap the order block or sit within 0.5× ATR of it, minimum size 0.10× ATR; the largest one wins. **First touch only** — if price already revisited the zone before the order exists, the setup is skipped.
- **Stop buffer** 0.10× ATR beyond the zone. **Minimum stop** (v1.02): skip the trade if the stop is under 1 pip (FX), 0.30 (gold) or 2.0 points (NAS100).
- Setups expire after **48 candles**. Fills only **07:00 London → 11:30 New York** (real DST). Max **2 filled trades per day per market**, 1 open trade at a time. Friday close 16:50 New York.
- **V3:** a 1-minute structure shift inside the zone, entry at the next 1-minute open.
- **V4:** the touch candle must wick past the latest 5-minute swing and close back; entry at the next 5-minute open, stop beyond that candle.
- **V5:** the 1-hour trend must agree when the setup arms AND until the fill.
- **1R** = the money lost if the first stop is hit, from the real fill and lot size.
- **Costs:** real spread + commission + swap.

## 3. Prop-firm simulation (inside the EA)
One virtual $100K account · 1% of balance per trade · Phase 1 +8%, Phase 2 +5% · funded payout at +5% (80% split, account reset to $100K) · 10% max loss on equity · daily 5% protection (a trade isn't taken if it could push the day past −5%) · $500 per challenge.
