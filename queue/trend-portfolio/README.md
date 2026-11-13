# Diversified time-series momentum

**Platform:** MT5 EA  
**Verdict:** Failed

## Idea
Monthly, for indices, metals, energy and FX: signal = average sign of the 1, 3 and 12-month return, position sized to a fixed volatility budget (Moskowitz, Ooi & Pedersen 2012).

## What we found
Holding CFD positions for months means paying swap every night; on retail CFDs that cost ate the trend premium.

## Files
- [`Trend_Portfolio.mq5`](Trend_Portfolio.mq5)

> **Disclaimer:** research and education only. Nothing here is financial advice or a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
