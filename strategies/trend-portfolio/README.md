# Time-series momentum on retail CFDs: overnight swap eats the trend

**Platform:** MetaTrader 5 (Expert Advisor)  
**Verdict:** ❌ Failed — the trend was there, but holding CFDs for months cost more than the trend paid

## The hook
"Trend following works across every market" is one of the best-documented ideas in finance. Managed-futures funds have run it for decades on stock indices, metals, energy and currencies.

So we built the textbook version for an ordinary MT5 account and ran it on CFDs. The rules were simple, the markets were diversified, the paper behind it is famous. And it still failed — not because the trends disappeared, but because of a cost that futures traders never pay in the same way: **overnight swap on every position, every night, for months.**

## The idea and where it came from
The strategy follows **time-series momentum** as described by **Moskowitz, Ooi & Pedersen (2012), "Time Series Momentum"**, and the long-history follow-up by **Hurst, Ooi & Pedersen (2017)**.

The idea in one line: *if a market has gone up over the past months, be long; if it has gone down, be short* — and do this on many unrelated markets at once, each sized so that no single market dominates the risk.

Unlike the G10 basket in [post #5](../fx-g10-basket/), this is not a ranking. Each market is judged only against its own past.

## The exact rules
**Markets** (input `InpSymbols`; missing symbols are skipped, a market joins once it has enough data):

- Stock indices: US500, NAS100, US30, GER40, UK100, JP225, FRA40, EU50, HK50
- Metals: XAUUSD, XAGUSD
- Energy: WTI and Brent crude, natural gas (several common broker names are listed)
- FX: EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, USDCHF, NZDUSD

**Once a month** (first weekday of the month, from 03:00 server time), for every market:

1. **Signal** = average of the sign of the return over **1, 3 and 12 months** (21, 63 and 252 trading days). The result is −1, −1/3, +1/3 or +1. A market needs at least 260 daily bars to get a signal.
2. **Volatility** = annualised standard deviation of daily log returns over the last **60 days** (`InpVolDays`).
3. **Target size** = signal × (volatility budget ÷ volatility). The budget is **4% per year per market** (`InpAssetVol = 0.04`).
4. **Caps:** at most **1× equity** notional per market (`InpMaxW`) and at most **4× equity** in total (`InpMaxGross`); if the total is larger, every position is scaled down.
5. **Low turnover:** a position is only changed when its direction flips or its size moves by more than **25%** (`InpBand`). Otherwise it is held.

There is no stop loss and no profit target — the position simply follows the monthly signal. That means many positions stay open for months.

At the end of a test the EA prints positive vs negative months, worst and best month, the return before and after 2016, yearly returns, P&L per market and — the key line — **price P&L versus swap**.

## How we tested it
- MetaTrader 5 Strategy Tester, one EA trading the whole basket on a retail broker's CFDs.
- Monthly rebalance as above, with broker swap charged on every position held overnight.
- The EA splits the result into the profit from price moves and the cost of swap, so we could see where the money went.

## What happened
Holding CFD positions for months means paying swap **every single night**. On retail CFDs that overnight financing cost **ate the trend premium**. The strategy was doing what trend following is supposed to do — but the edge it captured was not large enough to pay the broker's financing on positions held for weeks and months.

We are not quoting a performance figure here. The point of this test is the cost structure, and it gave a clear answer: on this kind of account, this kind of holding period does not survive the swap.

## The lesson for you
- **A strategy is only as good as the instrument you run it on.** The academic results are built on futures. A CFD on the same index or commodity charges you financing every night, and for a slow strategy that adds up fast.
- **The slower the strategy, the more swap matters.** A day trader barely notices it. A trend follower who holds for three months pays it about ninety times per position.
- **Always split your P&L into price and swap.** If the price line is positive and the total is not, you have found your problem. The EA here prints both — reuse that idea.
- **Check your broker's swap rates before you build a long-holding system.** Sometimes the honest conclusion is "good idea, wrong vehicle".

## Files
- [`Trend_Portfolio.mq5`](Trend_Portfolio.mq5) — the EA: monthly 1/3/12-month trend signal, volatility-budget sizing, per-market and total exposure caps, 25% rebalance band, monthly/yearly report, P&L per market and price-vs-swap split

> **Disclaimer:** Research and education only, not financial advice. Nothing here is a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
