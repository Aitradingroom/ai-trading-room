# G10 carry, momentum and value — and the swap trap in MT5 backtests

**Platform:** MetaTrader 5 (Expert Advisor)  
**Verdict:** ❌ Failed — the backtest could not tell us whether the idea works, because broker swap dominated the result

## The hook
Big funds have traded currencies on three simple ideas for decades: buy the currencies that **pay more interest**, buy the ones that **have been rising**, and buy the ones that look **cheap**. We wanted to know if a retail trader could run the same thing on an ordinary MT5 account.

We coded it, ran it, and got a result. Then we looked at *where* the result came from — and found that the backtest was mostly measuring something that never existed in the past: **today's swap rates, applied to all of history.**

This post is less about a strategy and more about a trap that hides inside almost every long carry backtest on MT5.

## The idea and where it came from
Carry, momentum and value are three of the best-known currency "factors" in institutional and academic FX research:

- **Carry:** high-interest currencies tend to earn the interest gap over low-interest ones.
- **Momentum:** currencies that have been strong over the past year tend to stay strong for a while.
- **Value:** currencies that have moved a lot over many years tend to drift back.

The classic way to trade them is **cross-sectional**: you do not ask "will EUR go up?", you rank all currencies against each other and go long the best and short the worst.

## The exact rules
The robot trades the G10 currencies against the US dollar, using nine pairs: EURUSD, GBPUSD, AUDUSD, NZDUSD, USDJPY, USDCHF, USDCAD, USDNOK, USDSEK. The USD itself is the tenth currency in the ranking.

**Once a month** (first weekday of the month, after 02:00 server time) every currency gets three scores:

| Factor | How it is measured |
|---|---|
| Carry | Central-bank policy rate at the **previous year end** (approximate table inside the code, 2004–2025) |
| Momentum | Return of the currency vs USD over the last **12 months** (`InpMomMonths`) |
| Value | **Minus** the return over the last **60 months** (`InpValMonths`) |

- Each factor is turned into a **demeaned rank** (best positive, worst negative, scaled so the absolute values add up to 1).
- The three ranks are added with equal weights (`InpWCarry`, `InpWMom`, `InpWVal` = 1.0).
- The combined score is scaled so the **total notional of all legs = 2 × equity** (`InpGross`).
- Positive score → long that currency; negative → short it. Long EUR means buying EURUSD; long JPY means selling USDJPY. The USD leg is implied.
- All positions are closed and rebuilt every month. No stop loss.

At the end of a test the EA prints: positive vs negative months, worst and best month, the return before and after 2016, yearly returns, and — most importantly — the split between **price P&L** and **swap**.

## How we tested it
- MetaTrader 5 Strategy Tester on forex CFDs from a retail broker.
- One EA trading all nine pairs at once, monthly rebalance.
- The EA separates profit from price moves and profit from swap, so we could see what was really driving the curve.

## What happened
**1. Swap dominated the result.** When we split the P&L, the swap line was the main driver, not the price moves. That sounds like "carry works" — but it does not prove that.

**2. The MT5 tester uses today's swap for all of history.** The Strategy Tester does not know what swap your broker charged in 2008 or 2014. It takes the swap rates set on the symbol **today** and charges them on every night of the backtest. Interest rates have changed enormously over the last twenty years (look at the rate table in the code: zero and negative rates for years, then a sharp rise). So a carry backtest on MT5 is effectively asking: *"what if today's interest rates had existed the whole time?"* That is not history, and the answer is close to meaningless for a carry strategy.

**3. One bad tick can fake a disaster or a miracle.** On **15 January 2015** the Swiss National Bank removed the EUR/CHF floor and CHF jumped violently. The broker data had a **bad USDCHF tick** that day, and it has to be excluded, otherwise one print decides the whole backtest.

Because the swap problem distorts the whole curve, we are not publishing the performance numbers as if they meant something. The honest verdict is: **this test cannot answer the question.**

## The lesson for you
- **Before you trust a carry backtest on MT5, check the swap line.** If swap is the main source of profit, the result is built on today's rates, not on history.
- **Split your P&L.** Price P&L and swap tell very different stories. The EA here prints both — copy that idea into your own robots.
- **Check the famous dates.** SNB day (15 Jan 2015), flash crashes and similar events often contain broken ticks. One bad price can make or break a whole test.
- **A strategy that only works because of the costs model is not a strategy.** To test carry properly you need historical interest rates or real historical swap data, not the tester default.

## Files
- [`FX_G10_Basket.mq5`](FX_G10_Basket.mq5) — the EA: monthly carry/momentum/value ranking on nine USD pairs, gross exposure input, monthly/yearly report and price-vs-swap split

> **Disclaimer:** Research and education only, not financial advice. Nothing here is a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
