# IBS mean reversion on stock indices: a real edge, almost eaten by costs

**Platform:** MetaTrader 5 (Expert Advisors) + TradingView (Pine Script)  
**Verdict:** ⚠️ Weak — the edge is real but small after costs, and the basket version needed a hard cap to survive

## The hook
"Buy the index after an ugly close, sell it when it bounces." It is one of the oldest short-term ideas in index trading, and on a chart it looks almost too easy.

We coded it twice: once on a single index, and once as a basket that trades many indices at the same time. The single-index version showed a small, real edge. The basket version looked like a way to multiply that edge — until it produced a **−40% month**.

This post is about both: a small edge that survives, and a diversification idea that did not diversify anything.

## The idea and where it came from
**IBS (Internal Bar Strength)** measures where the day closed inside its own range:

`IBS = (close − low) / (high − low)`

- IBS near **0** → the day closed at its low (sellers in control into the close).
- IBS near **1** → the day closed at its high.

The popular observation is that stock indices tend to bounce after a close near the low, especially when the market has already pulled back. We combined the IBS filter with a simple pullback band, which is a common way this rule is shared in short-term index-trading research.

## The exact rules
Everything is on the **daily** bar.

**Entry (long only by default)**
- IBS of the last closed day **< 0.3**, and
- the close is **below the pullback band**:
  `band = highest high of the last 10 days − 2.5 × average (high − low) of the last 25 days`
- The order is placed at the next bar open (the Pine version fills at the close).

**Exit**
- When a day closes **above the previous day's high**.
- No stop loss and no time stop: the trade waits for the bounce.

**Size**
- Single-index EA: position notional = `InpExposure` × equity (default 1.0 = fully invested).
- Basket EA: each position = 0.25 × equity (`InpExpo`), and the **total** notional of all open positions is capped at 1.0 × equity (`InpMaxGross`). New entries are skipped when the basket is full.

The single-index EA also has optional short trades (mirror rules) and an optional "reverse martingale" size step after wins; both are **off** by default.

## How we tested it
- MetaTrader 5 Strategy Tester on CFD stock indices from a retail broker, so spread and overnight financing are included in the result.
- **Single index:** `IBS_MeanReversion.mq5`, one index at a time. It prints trades, wins, win rate and average days held at the end of each run.
- **Basket:** `IBS_Portfolio.mq5` on a list of major indices (US500, US30, NAS100, GER40, UK100, JP225, FRA40, EU50, AUS200, HK50, ESP35 and similar names; names the broker does not have are skipped). It prints a monthly report — share of positive months, average, worst and best month — plus yearly returns and per-symbol results.
- The Pine version lets you check the same rule visually on TradingView.

## What happened
**Single index:** the edge is **real but small**. The rule does tend to catch bounces, but on CFD indices a good part of it goes to the spread and the overnight financing you pay while you wait for the exit.

**Basket, first version:** the idea was "more indices = more trades = smoother returns". Instead, the worst month was **about −40%**. The reason is simple: stock indices around the world fall **together**. On a bad day, almost every index in the basket gives a buy signal at the same time, so the robot ends up fully loaded on one bet — "global stocks will bounce" — exactly when that bet is most dangerous.

**Basket, with the exposure cap:** capping total exposure stopped the blow-up. But it also removed **most of the return**. The cap mostly blocked the very trades that made the money.

We describe the rest qualitatively on purpose: the exact numbers depend heavily on the broker's spread and financing, and the conclusion does not change.

## The lesson for you
- **A real edge is not the same as a tradable edge.** Small edges get eaten by spread and financing, especially on CFDs you hold overnight.
- **Many markets is not the same as diversification.** If all your markets drop on the same day, a basket is just one big position split into pieces.
- **Look at the worst month, not the average.** A −40% month is something you will not sit through in real life, whatever the long-term curve says.
- **Risk limits cost return.** A cap that fixes the blow-up often removes the profit too. If a strategy only makes money when its risk is uncapped, it is not a good strategy.

## Files
- [`IBS_MeanReversion.mq5`](IBS_MeanReversion.mq5) — single-symbol EA (IBS threshold, pullback band, exposure, optional shorts and size step as inputs)
- [`IBS_Portfolio.mq5`](IBS_Portfolio.mq5) — basket EA with per-position size, total exposure cap and a monthly/yearly report
- [`ibs_mean_reversion.pine`](ibs_mean_reversion.pine) — TradingView strategy with the same rule, for visual checking

> **Disclaimer:** Research and education only, not financial advice. Nothing here is a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
