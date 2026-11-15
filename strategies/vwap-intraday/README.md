# Session VWAP: 3 popular rules tested on indices, forex and gold

**Platform:** MetaTrader 5 (Expert Advisor)  
**Verdict:** ❌ Failed — looked good in-sample, did not hold out-of-sample

## The hook
VWAP is everywhere. "Buy above VWAP, sell below it." "Fade the bands." "Buy the pullback to VWAP in an uptrend." Every intraday trading video has one of these rules, and many of them come with a nice-looking chart.

We coded the three most popular VWAP rules into one robot and tested them on stock indices, major forex pairs and gold. Some settings looked genuinely good. Then we tested them on data they had never seen — and the edge was gone.

This post is about that gap, and why it is the single most important thing to check before you trust any backtest.

## The idea and where it came from
VWAP (volume-weighted average price) is the average price of the session, weighted by volume. Institutions use it as a benchmark, so the idea is that price reacts to it.

- **Rule 1 (cross / flip)** comes from published research: Zarattini & Aziz (2023), who studied a simple "long above VWAP, short below VWAP" rule on intraday data.
- **Rules 2 and 3** (band reversion and trend pullback) are the two VWAP setups you see most often in trading education.

All three are **intraday only**: the robot is flat before the session ends, so there is no overnight swap to distort the result.

## How VWAP is built in the robot
- The session starts at a set server time (default 16:30) and the robot is flat at a set time (default 22:55).
- On each closed bar of the signal timeframe (default M5), the typical price `(high + low + close) / 3` is weighted by the bar's tick volume and added to the session total.
- **VWAP** = Σ(price × volume) / Σ(volume), reset every new session.
- **Bands** = VWAP ± k × the volume-weighted standard deviation of price around VWAP.
- No new entries in the first 15 minutes of the session (VWAP is too unstable with only a couple of bars).

## The exact rules
**Mode 1 — Cross / flip**
- Last bar closed above VWAP → be long. Closed below → be short.
- When the side flips, close the trade and open the other way.

**Mode 2 — Band reversion**
- Close below VWAP − 2 sd (but not beyond −3.5 sd) → buy. Mirror for shorts above +2 sd.
- Exit when price closes back at VWAP.
- Stop: a close beyond 3.5 sd on the wrong side.

**Mode 3 — Trend pullback**
- VWAP rising (compared with 6 bars ago) and a bar dips to VWAP but closes back above it → buy. Mirror for shorts when VWAP is falling.
- Exit on a close more than 1 sd on the wrong side of VWAP, or at session end.

**All modes:** one position at a time, size set as a multiple of equity (default 1× notional), shorts can be switched off, everything closed at the session end time.

## How we tested it
- MetaTrader 5 Strategy Tester on broker data.
- Markets: stock indices, major forex pairs and gold.
- We searched settings on one part of the history (**in-sample**), then ran the best settings, unchanged, on a later part they had not seen (**out-of-sample**).
- The robot also prints its own report at the end of each run: number of trades, win rate, average points per trade vs. the spread, positive vs. negative months, worst and best month, and the return per year.

## What happened
- **In-sample:** some combinations of rule, market and settings looked good.
- **Out-of-sample:** those same settings **did not hold up**. The good results did not carry over to the new data.

In plain words: what looked like an edge was the optimiser finding settings that happened to fit the past. That is curve-fitting, not a strategy.

We are not publishing the in-sample numbers on purpose. A number that only exists in-sample is exactly the kind of number that makes a bad strategy look good on social media.

## The lesson for you
- **In-sample results are a hypothesis, not a result.** The more settings, markets and modes you try, the more certain it is that *something* will look good by luck.
- **Always keep data the optimiser never sees.** Test the final settings once on it. If the edge disappears, it was never there.
- **Popular does not mean profitable.** A rule everyone knows is the rule everyone trades; whatever edge it had is usually gone after spread and slippage.
- If someone shows you a VWAP (or any) backtest, ask: **"Was this tested out-of-sample?"**

## Files
- [`VWAP_Intraday.mq5`](VWAP_Intraday.mq5) — one EA with all three modes (`InpMode` = 1 cross, 2 band reversion, 3 trend pullback), session times, band widths and sizing as inputs

> **Disclaimer:** Research and education only, not financial advice. Nothing here is a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
