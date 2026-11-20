# Forex range breakout after compression — rejected

**Rules (RangeBreakout_v1_EA.mq5 / AITR_RangeBreakout_v1.pine):** range = last 12 closed candles; compression if range < 1.5 × ATR(14); enter at next open after a close beyond the range; stop 1.5 ATR, target 3R, time exit after 12 bars; 0.5% risk, spread and commission included.

**Result 2021 – 2026 (total R; compression multiplier 1.5 → 4)**
- With the original 1.5 rule: only 8 trades on EURUSD M15 in six years.
- EURUSD M15: −49R (527 trades) down to −838R; GBPUSD M15: −64R down to −852R. Costs (~0.1R per trade) kill it.
- H1 roughly break-even over six years; GBPUSD H1 (2.5×) +65R, but almost all of it came in 2025–2026, while 2021–2024 was flat to strongly negative.

**Lesson:** classic "squeeze breakout" on major pairs had no robust edge in our test.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
