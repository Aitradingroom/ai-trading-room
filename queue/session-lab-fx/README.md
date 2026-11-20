# Session lab: 5 strategies × 5 sessions on EURUSD and GBPUSD

**Strategies (Session_Lab_EA.mq5):** 1 ORB breakout (first 30 min), 2 ORB fade, 3 breakout of the 6-hour pre-session range, 4 fade of that range, 5 first-30-minute momentum. **Sessions (server time):** London 10–18, NY 15–23, NY cash 16:30–23, overlap 15–19, London morning 10–15. 0.5% risk, target 2R, one trade per day, flat at session end.

**Train 2021–2024 / test 2025–2026 (total R):**
- London ORB: EURUSD −1.5 / +15.2, GBPUSD +15.3 / +26.5 (only combination positive in both periods on GBPUSD).
- NY ORB on forex: EURUSD +97.5 / **−36.6**, GBPUSD +3.7 / **−54.0** — great in-sample, broken out of sample.
- Fades and pre-session-range trades were negative almost everywhere.
- Gold results were discarded: our R calculation had a bug for XAUUSD.

**Lesson:** a result that only works in one period is not an edge. On forex the London open mattered, not New York.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
