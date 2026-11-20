# NY Opening Range Breakout on US500 + NAS100 (our best result so far)

**Rules (ORB_NY_Final_EA.mq5)**
- Opening range = first 15 minutes after the New York cash open (16:30 server time).
- Entry: an M5 candle closes beyond the range, in the direction of the M15 EMA50.
- Skip the day if the range is smaller than 0.1 × daily ATR(14).
- Stop 0.2 × range back inside the breakout edge (small stop), target 6R.
- Entries only during the first 90 minutes after the range; flat at 22:55 server time. One trade per symbol per day.
- Risk halved in June and July (weaker months in the test).

**Result ($5,000, 0.5% risk per trade, both symbols)**
- End balance $64,224, profit factor 1.28, max drawdown 21.3%, 69% of months positive.
- Years: 2021 +55%, 2022 +62%, 2023 +29%, 2024 +108%, 2025 +25%, 2026 (to 19 Nov) +52%.
- Walk-forward check: all 36 parameter sets stayed profitable out of sample.
- Higher risk: 0.75% → $185k with 30% drawdown; 1% → $504k with 38% drawdown.
- Prop-style version (ORB_NY_Prop_EA.mq5, 0.075% risk on $200k): max drawdown 3.46%, worst day −0.60%, about 7% per year.

**Lesson:** the edge is tied to one event — the New York cash open on indices. The same rules on other times and markets did not work (see the session lab post).

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
