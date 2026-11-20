# Initial Volatility Breakout (IVB) — the viral claim vs MT5

**Rules (IVB_EA.mq5, as shown in the video):** initial balance = 09:30–10:00 New York; trade only if today's IB is 0.3–1.1 × the 10-day average IB; breakout candle volume ≥ 1.2 × average; stop 3.5 ATR, target 5 ATR, risk 2%, max 2 trades per day. M5, $10,000.

**Result 2021 – 19 Nov 2026**
- US500: 1,294 trades, win 42.9%, profit factor **1.00**, net +$526, max drawdown **70.9%** — no edge.
- NAS100: 991 trades, win 44.9%, profit factor 1.08, net +$16,176, drawdown 45.7% — weak edge, far too deep.

**Lesson:** the filters sound smart; the numbers don't back the claim. Our simpler NY ORB did better with a third of the drawdown.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
