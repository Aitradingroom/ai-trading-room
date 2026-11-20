# Free TradingView indicator: NY ORB Signal (US500 / NAS100, 5-minute chart)

AITR_NY_ORB_Signal.pine (Pine v5) shows the rules of our NY ORB research live on a chart:
- draws the 09:30–09:45 New York opening range box;
- signals a long/short when a 5-minute candle closes beyond the range in the direction of the 15-minute EMA50 (previous closed bar, no repaint), within 90 minutes, one signal per day;
- labels entry, stop (0.2 × range inside the edge), 6R target, risk in $ and position size from your account size and risk %;
- alerts on signal, target, stop and at 15:55 New York (time to flatten).

It is a research/education tool, not a signal service. Check your broker's point value before using the size label.
