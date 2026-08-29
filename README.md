# XAUUSD ICT M5 EA

Version 2.00 — ICT/SMC multi-confirmation EA for XAUUSD M5.

## Included
- MSS / Market Structure Shift
- BOS / CHOCH structure detection
- Liquidity sweep
- Order Block
- Fair Value Gap (FVG)
- Fibonacci retracement / OTE zone: 0.618, 0.705, 0.786
- EMA 20/50/200 trend filter
- RSI momentum filter
- ATR-based adaptive SL and risk/reward TP
- Spread, margin, daily loss and daily trade limits
- One-position-at-a-time protection
- Score-based multi-confirmation entries

## Safety
`InpEnableTrading` defaults to `false`. Compile and validate in Strategy Tester / FX24 Demo before enabling trading. Do not use on a live account until independently validated.

## Recommended initial test
- Symbol: XAUUSD
- Timeframe: M5
- Lot: 0.01
- Trading disabled during code validation
- Strategy Tester first, then FX24 Demo
