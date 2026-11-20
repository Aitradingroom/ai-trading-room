# Can a filter cut drawdown? Five tricks tested on the 5-market portfolio

**Variants (AITR_Portfolio_v2_EA.mq5, InpCfg):** 1 halve risk when drawdown > 10%; 2 halve at 15%, quarter at 25%; 3 halve when balance < 20-trade average (equity-curve filter); 4 skip a second same-direction JPY trade; 5 stop for the day after −2R; plus combinations.

**Fixed sizing, 1% risk, 2021 – 19 Nov 2026 (profit / max drawdown):**
- Base: $42.5k / 36.7%
- DD throttle 15%/25%: $41.2k / **25.5%** (best: −3% profit, −11 points drawdown)
- DD throttle 10%: $38.8k / 25.8%
- Day-loss stop 2R: $37.7k / 29.6%
- Equity-curve filter: $31.1k / 30.0%
- JPY correlation cap: $37.2k / 35.6%

With compounding at 1%, the 15/25 throttle lowered drawdown only from 33.5% to 30.0% and cut growth a lot — similar to simply trading 0.5% risk.

**Lesson:** risk throttling helps a little; the most reliable drawdown control is a smaller risk per trade.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
