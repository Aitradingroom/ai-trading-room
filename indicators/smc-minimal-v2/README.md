# SMC Minimal v2 (TradingView, Pine Script v6)

Market structure with one strict rule set, plus session lines and a daily volume profile.

## Market structure
- Internal swings that don't break the leg's extremes are ignored.
- On a new higher high, the protected low is the **start of the leg** that made it (mirror for lows).
- **CHoCH** = a candle close beyond that protected level. **BOS** = a new extreme after a real pullback.

## Sessions
Vertical lines at the London and New York opens (and optionally closes), with next-session lines drawn into the future. Tokyo and Sydney are included but off by default. Line style and width can be changed.

## Daily volume profile
For each of the last N daily candles (50, 75, 100 — your choice) the script builds a separate fixed-range volume profile, like TradingView's *Fixed Range Volume Profile* dropped on that one candle, and joins the **POC**, **VAH** and **VAL** from day to day. Today shows yesterday's levels until the daily candle closes. POC and VAH/VAL can be switched on and off separately.

Notes: recent days use 1-minute data and match TradingView's tool; older days fall back to 5–60 minute data and are close approximations. Forex/CFD volume is broker tick volume.

## How to use
Pine Editor → paste [`smc_minimal_v2.pine`](smc_minimal_v2.pine) → *Add to chart*.

> **Disclaimer:** research and education only. Nothing here is financial advice or a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
