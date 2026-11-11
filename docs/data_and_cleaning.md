# Data and cleaning

## Data

| | |
|---|---|
| Source | Binance spot, BTCUSDT and ETHUSDT, 1-hour candles |
| Size | 161,610 rows (2 symbols × 80,805 candles), 11 columns |
| Period | 2017-08-17 to 2026-11-09 (3,371 complete days) |
| Timestamps in the file | UTC. Add 7 hours for Vietnam time |
| Columns | symbol, open time, open, high, low, close, volume, number of trades, taker buy volume |

## Quality checks (`sql/02_quality_checks.sql`)

Results on data up to 2026-11-09:

| Check | Result |
|---|---|
| Missing values, duplicate rows | None |
| Price logic errors (high < low, non-positive prices, etc.) | 0 rows |
| Missing hours | 128 hours per symbol (about 0.16%), in 28 gaps, the longest 33 hours. Both symbols are missing the same hours, so these are exchange maintenance windows |
| Candles with no trades | 10 candles, all flat |
| Suspect-price candles | 3 candles (e.g. ETH on 2017-08-22: the open is about −48% off the previous close) |
| Thin-market period | Before 2018, prices jump a lot because there are few trades |

## Flags added during cleaning (`sql/03_clean.sql`)

Principle: **flag instead of delete**, so rows can be filtered out at analysis time.

| Flag | Meaning | Why the rows are kept |
|---|---|---|
| `gap_before` | Candle right after a gap of missing hours | Missing hours are not filled, since that would be inventing data. `ret_1h` is left empty on these rows so calculations don't run across the gap |
| `is_flat_candle` | Flat candle (open = high = low = close) | Mostly hours with no trading |
| `is_thin_period` | Before 2018 | Kept so results can be compared with and without 2017 |
| `ohlc_suspect` | Suspect-price candle | Only 3 rows, not modified |
| `is_incomplete` | Last candle of each symbol, not yet closed | Excluded from analysis |
| `ret_outlier` | Hour with an abnormal price jump | These are real market events; deleting them would remove exactly the most important hours |

The outlier threshold is computed separately for each symbol, using the interquartile range × 3 on the 1-hour log-return, only from 2018 onward and excluding the unclosed candle. The 2017 period is left out of the threshold calculation because the market was thin, which would otherwise distort it.

## Re-checks (`sql/04_validate_export.sql`)

- The cleaned table has the same number of rows as the raw table.
- `ret_1h` is empty on every row that follows a gap of missing hours.
- The thin-market period is not flagged as outliers.
- Each symbol has exactly one unclosed candle, and it is the latest one.
