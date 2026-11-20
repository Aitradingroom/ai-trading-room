# AI Trading Room — publishing playbook (queue branch)

This branch holds material for future posts. `main` is the public library. Each daily run moves ONE item from here to `main` and posts it on Instagram (@aitradingroom).

## Order (publish the first item not yet in the `main` README "Posts" table)
1. queue/shadow-grid — "Why a smooth balance curve can hide a disaster" (grid, no stop loss; equity images included)
2. queue/vwap-intraday — "Session VWAP: 3 popular rules tested on indices, forex and gold" (failed out-of-sample)
3. queue/ibs-mean-reversion — "IBS mean reversion on stock indices" (weak; first basket version had a −40% month before the exposure cap)
4. queue/fx-g10-basket — "G10 carry / momentum / value — and the swap trap in MT5 backtests"
5. queue/trend-portfolio — "Time-series momentum on retail CFDs: overnight swap eats the trend"
6. queue/trend-pyramid — "Turtle-style pyramiding 2016–2026" (image included)
7. queue/map-levels — free indicator post (MAP Levels)
8. queue/map-trend-rider — "Trend following on round-number levels, 2005–2026" (image included)
9. queue/index-system — "Turn-of-the-month + IBS on an index basket"
10–12. opening-range-breakout, quasimodo, asian-mean-reversion — SKIP (old, results not documented; ORB is replaced by item 13).
13. queue/orb-ny-indices — "NY opening range breakout on US500 + NAS100" (post #11, 23 Nov)
14. queue/session-lab-fx — "5 strategies × 5 sessions: why NY broke on forex" (post #12, 24 Nov)
15. queue/london-orb — "London ORB: EURUSD, GBPUSD, DAX and JPY crosses" (post #13, 25 Nov)
16. queue/portfolio-5 — "One account, five markets: London + NY ORB, risk 0.5–2%" (post #14, 26 Nov)
17. queue/ivb-fail — "IVB: the viral claim vs MT5" (post #15, 27 Nov)
18. queue/range-breakout-fx — "Forex squeeze breakout: rejected" (post #16, 28 Nov)
19. queue/drawdown-control — "5 tricks to cut drawdown, tested" (post #17, 29 Nov)
20. queue/compounding-trap — "Why $5k → $3.5M backtests lie" (education post #18, 30 Nov; folder goes to docs/compounding-trap/)
21. queue/ny-orb-signal-indicator — free TradingView indicator post (post #19, 1 Dec; folder goes to indicators/ny-orb-signal/)

## GitHub post (on main)
- Copy `queue/<item>/` to `strategies/<item>/` (indicators go to `indicators/`).
- Expand its README into a story: hook, the idea and its source, exact rules, how it was tested, what happened, the lesson, files, disclaimer.
- Add a row to the README "Posts" table (next number); remove it from "Coming next".
- Honesty: never invent numbers. Use only what the queue README/images show; otherwise describe results qualitatively.
- Commit as "AI Trading Room" and push to main.

## Instagram post
- 3–5 slides, 1080×1350 (4:5), brand navy #0b1220 + gold #e2b04a, header "AI TRADING ROOM", page counter, footer "Research & education only — not financial advice." Template: `tools/instagram_slide_template.html`.
- Caption (English): hook, 3–5 bullets, strong GitHub call to action ("full code + write-up FREE on our GitHub — link in bio"), next-post teaser, "Research & education only, not financial advice.", ~10 hashtags incl. #github.
- AI label off (graphics, not realistic photos).
