# G10 currency basket: carry, momentum, value

**Platform:** MT5 EA  
**Verdict:** Failed

## Idea
Every month rank the G10 currencies against USD on carry (policy rate), momentum and value, go long the best and short the worst.

## What we found
The result was dominated by broker swap. The MT5 tester applies today's swap rates to all of history, so long backtests of carry strategies on CFDs are unreliable. A bad USDCHF tick on 15 Jan 2015 (SNB day) also has to be excluded.

## Files
- [`FX_G10_Basket.mq5`](FX_G10_Basket.mq5)

> **Disclaimer:** research and education only. Nothing here is financial advice or a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
