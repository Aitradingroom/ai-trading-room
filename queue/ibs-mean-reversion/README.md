# IBS mean reversion (single index + index basket)

**Platform:** MT5 EA + Pine  
**Verdict:** Weak

## Idea
Buy a stock index after a weak close: IBS = (close − low) / (high − low) below a threshold and the close below a pullback band (highest high of 10 days − 2.5 × average range of 25 days). Exit when the close is above the previous day's high. The basket version runs the same rule on several indices with a cap on total exposure.

## What we found
The edge is real but small on CFD indices once spread and financing are paid. The first basket version had a −40% worst month because the indices fall together; a gross-exposure cap fixed the blow-up but also most of the return.

## Files
- [`IBS_MeanReversion.mq5`](IBS_MeanReversion.mq5)
- [`IBS_Portfolio.mq5`](IBS_Portfolio.mq5)
- [`ibs_mean_reversion.pine`](ibs_mean_reversion.pine)

> **Disclaimer:** research and education only. Nothing here is financial advice or a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
