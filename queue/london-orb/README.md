# London Opening Range Breakout (EURUSD, GBPUSD, DAX, JPY crosses)

**Rules (ORB_London_Final_EA.mq5):** London session 10:00–18:00 server time, opening range = first 45 minutes, entry on an M5 close beyond the range in the M15 EMA50 direction, stop on the opposite side of the range, target 6R, entries within 2 hours, flat at 18:00. Settings chosen from a 72-combination grid (positive in train 2021–2024 AND test 2025–2026 on both pairs, with positive neighbours).

**Full period, $5,000, 0.5% risk:**
| Symbol | PF | Net | Max DD |
|---|---|---|---|
| EURUSD | 1.10 | +34.5% | 21.7% |
| GBPUSD | 1.08 | +33.3% | 13.0% |
| GBPJPY | 1.17 | +64% | 17.7% |
| EURJPY | 1.13 | +45% | 19.6% |
| GER40 (DAX) | 1.22 | +67.5% | 9.3% |
| UK100 (FTSE) | 0.88 | −27% | 33% (fail) |

The extra symbols used the same settings without re-optimising. **Lesson:** small edge (~0.05R per trade) on major pairs; indices that open with the session (DAX) behave best.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
