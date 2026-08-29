# Validation checklist

1. Compile `XAUUSD_ICT_M5_EA.mq5` in MetaEditor.
2. Resolve any compiler errors/warnings before trading.
3. Run Strategy Tester on XAUUSD M5.
4. Verify MSS/BOS/CHOCH, liquidity sweep, OB, FVG and Fibonacci detections against chart history.
5. Verify SL/TP, spread filter, daily loss limit and max trades/day.
6. Run on FX24 Demo after Strategy Tester validation.
7. Keep `InpEnableTrading=false` until validation is satisfactory.
