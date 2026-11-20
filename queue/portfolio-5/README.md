# One account, five markets: London ORB + NY ORB

**Setup (AITR_Portfolio_EA.mq5):** London ORB on GER40, GBPJPY, EURJPY + NY ORB on US500, NAS100, all on one account, $5,000 start, risk compounded on balance. 6,121 trades (≈4 per day).

| Risk/trade | Max DD | Worst month | Months up | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 YTD |
|---|---|---|---|---|---|---|---|---|---|
| 0.5% | 25% | −12% | 73% | +55% | +145% | +59% | +202% | +46% | +93% |
| 1% | 33.5% | −17% | 70% | +118% | +429% | +128% | +622% | +87% | +99% |
| 1.5% | 47% | −25% | 69% | +184% | +907% | +205% | +574% | +76% | +40% |
| 2% | 58% | −36% | 70% | +236% | +1686% | +246% | +283% | +62% | +32% |

**Read this before getting excited:** the compounded end balances run into millions, which is not realistic — later years hit the broker's maximum lot size, and real liquidity and slippage would be much worse. The symbols were also chosen after seeing results (selection bias). The first-year numbers are the more honest ones.

Tested in MetaTrader 5 Strategy Tester on broker demo data (Alpari-MT5-Demo feed), M5 chart, "1 minute OHLC" modelling with the broker spread, 1 Jan 2021 – 19 Nov 2026. Research and education only, not financial advice. Backtests are not live results.
