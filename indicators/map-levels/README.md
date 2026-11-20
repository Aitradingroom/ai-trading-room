# MAP Levels: a free round-number price map for TradingView

**Platform:** TradingView (Pine Script v6)  
**Type:** Free indicator — a chart tool, not a strategy, so there is no backtest or result in this post

## The hook
Watch any chart long enough and you notice price hesitating at "obvious" numbers: 1.1000 on EURUSD, 2000 on gold, 20,000 on an index. Most traders draw those lines by hand, and every trader draws them a little differently.

MAP Levels draws them for you, with one fixed rule, on every market and every timeframe. It is also the foundation for our next post, where we turn these levels into a trend-following system and test it.

## The idea
The map is built from **logarithmic round numbers**: 1, 2, 3 … 10, then 20, 30 … 100, then 200, 300 … 1000, and so on. Those are the **A** levels (the main grid). Each gap between two A levels is then **halved again and again** into finer mid-levels for lower timeframes:

| Tier | What it is | Default colour |
|---|---|---|
| **A** | Main round numbers (1, 2 … 10, 20 … 100, 200 …) | Gold |
| **B** | 1/2 of the A cell | Blue |
| **C** | 1/4 | Purple |
| **D** | 1/8 | Teal |
| **E … P** | 1/16 and finer | Grey |

Use it as a structure for where price is likely to react — a map, not a signal.

*Example of how the arithmetic works (not a trade idea):* with price at 2,350, the A cell is 2,000 → 3,000, the B mid-level is 2,500, the C levels are 2,250 and 2,750, and so on down the tiers.

## How it works (the exact logic)
All of this is in [`map_levels.pine`](map_levels.pine).

1. On the last bar the script finds the A cell that contains the current price (the two neighbouring round numbers, e.g. 2,000 and 3,000).
2. **Depth** decides how many halvings are shown:
   - **Auto** (default): the finest level spacing is kept at least **1.5 × ATR(14)** of the chart timeframe, so lower timeframes automatically get finer levels and higher timeframes stay clean.
   - **Manual**: a fixed depth (0 = A only, 1 = +B, 2 = +C …, up to 15). Default 4.
3. Only levels near price are drawn: the **12 finest levels above and below** price (adjustable from 2 to 60), across all tiers inside that window.
4. **Colour mode**
   - *Relative* (default): the coarsest levels visible on this timeframe get the strongest colours, so the chart always reads "big level → small level" whatever the zoom.
   - *By letter*: a fixed colour per tier letter.
5. A small info table (bottom right) shows the current **A cell**, the **B mid-level** and the **finest tier** with its step size.

Every tier can be switched on/off and recoloured; labels and their size are optional.

## How to use
1. Open TradingView → **Pine Editor**.
2. Paste [`map_levels.pine`](map_levels.pine) → **Add to chart**.
3. Leave Depth on *Auto* and switch timeframes: the map refines itself as you zoom in.

## The lesson
Round numbers are a simple, objective way to put structure on a chart — but a line is not an edge. Whether these levels can actually be traded is a separate question, and that is exactly what the next post tests.

## Files
- [`map_levels.pine`](map_levels.pine) — the indicator (Pine Script v6)

> **Disclaimer:** Research and education only, not financial advice. Nothing here is a signal service. Backtests are not live results, past performance does not predict future returns, and trading leveraged products can lose more than you deposit.
