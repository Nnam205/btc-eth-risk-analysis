-- 02_quality_checks.sql
-- Mục đích: kiểm tra chất lượng bảng gốc raw_klines theo các nhóm lỗi. CHỈ ĐỌC, không sửa gì.
-- Chạy từng khối (bôi đen rồi Ctrl+Enter) và đọc kết quả. Kỳ vọng ghi trong chú thích.
USE crypto_1h;

-- (1) Tổng quan: số dòng, khoảng thời gian mỗi mã
SELECT symbol, COUNT(*) AS so_dong, MIN(open_time) AS dau, MAX(open_time) AS cuoi
FROM raw_klines GROUP BY symbol;

-- (2) Giá trị thiếu và số 0. Kỳ vọng: NULL = 0 ở mọi cột; volume = 0 có 10 dòng (đều trades = 0)
SELECT SUM(`open` IS NULL OR high IS NULL OR low IS NULL OR `close` IS NULL
        OR volume IS NULL OR quote_volume IS NULL OR trades IS NULL
        OR taker_buy_base IS NULL OR taker_buy_quote IS NULL) AS dong_co_null,
       SUM(volume = 0)                    AS nen_volume_0,
       SUM(volume = 0 AND trades = 0)     AS nen_volume_0_va_trades_0,
       SUM(taker_buy_base = 0 AND volume > 0) AS taker_0_nhung_co_volume
FROM raw_klines;

-- (3) Trùng lặp. Kỳ vọng: 0 (khoá chính (symbol, open_time) đã chặn từ bước 01)
SELECT COUNT(*) - COUNT(DISTINCT symbol, open_time) AS dong_trung_khoa FROM raw_klines;

-- (4) Lỗi logic và ràng buộc OHLC. Kỳ vọng: tất cả = 0
SELECT SUM(`open` <= 0 OR high <= 0 OR low <= 0 OR `close` <= 0)       AS gia_khong_duong,
       SUM(high < low)                                                  AS high_nho_hon_low,
       SUM(high < GREATEST(`open`, `close`))                            AS high_thap_hon_open_close,
       SUM(low  > LEAST(`open`, `close`))                               AS low_cao_hon_open_close,
       SUM(taker_buy_base  > volume       + 0.000000001)                AS taker_base_vuot_volume,
       SUM(taker_buy_quote > quote_volume + 0.000001)                   AS taker_quote_vuot_quote_volume
FROM raw_klines;

-- (5) Nến phẳng (open = high = low = close). Kỳ vọng: 12 nến, trong đó 2 nến có volume > 0 (ETH 2017)
SELECT symbol, open_time, `open`, volume, trades
FROM raw_klines
WHERE `open` = high AND high = low AND low = `close`
ORDER BY volume DESC, symbol, open_time;

-- (6) Toàn vẹn chuỗi thời gian: mỗi mã phải đủ từng giờ. Mỗi dòng dưới đây là một khoảng thiếu.
-- Kỳ vọng: 28 khoảng/mã, tổng 128 giờ thiếu/mã, hai mã thiếu cùng các khung giờ (dài nhất ~33 giờ, 08-09/02/2018)
WITH g AS (
    SELECT symbol, open_time,
           TIMESTAMPDIFF(HOUR, LAG(open_time) OVER (PARTITION BY symbol ORDER BY open_time), open_time) AS gap_hours
    FROM raw_klines
)
SELECT symbol,
       COUNT(*)                AS so_khoang_thieu,
       SUM(gap_hours - 1)      AS tong_gio_thieu,
       MAX(gap_hours - 1)      AS khoang_dai_nhat_gio
FROM g
WHERE gap_hours > 1
GROUP BY symbol;

-- Danh sách các khoảng thiếu (xem BTC; ETH giống hệt)
WITH g AS (
    SELECT symbol, open_time,
           LAG(open_time) OVER (PARTITION BY symbol ORDER BY open_time) AS prev_time,
           TIMESTAMPDIFF(HOUR, LAG(open_time) OVER (PARTITION BY symbol ORDER BY open_time), open_time) AS gap_hours
    FROM raw_klines
)
SELECT symbol,
       prev_time + INTERVAL 1 HOUR   AS thieu_tu,
       open_time - INTERVAL 1 HOUR   AS thieu_den,
       gap_hours - 1                 AS so_gio_thieu
FROM g
WHERE gap_hours > 1 AND symbol = 'BTCUSDT'
ORDER BY so_gio_thieu DESC;

-- (7) Tính liên tục giá: open của giờ này phải gần close của giờ trước (thị trường chạy 24/7).
-- Kỳ vọng: 2017 có ~8% cặp giờ lệch > 0,5% (thị trường mỏng), từ 2018 gần như 0
WITH g AS (
    SELECT symbol, open_time, `open`, trades,
           LAG(`close`) OVER (PARTITION BY symbol ORDER BY open_time) AS prev_close,
           TIMESTAMPDIFF(HOUR, LAG(open_time) OVER (PARTITION BY symbol ORDER BY open_time), open_time) AS gap_hours
    FROM raw_klines
)
SELECT YEAR(open_time)                                                AS nam,
       ROUND(AVG(ABS(`open` / prev_close - 1) > 0.005), 4)            AS ti_le_open_lech_hon_0_5pct,
       COUNT(*)                                                       AS so_cap_gio
FROM g
WHERE gap_hours = 1
GROUP BY YEAR(open_time)
ORDER BY nam;

-- Các cặp giờ liền kề lệch > 20%. Kỳ vọng: 1 dòng (ETH 22/08/2017 04:00, lệch ~ -48%)
WITH g AS (
    SELECT symbol, open_time, `open`, low, `close`, trades,
           LAG(`close`) OVER (PARTITION BY symbol ORDER BY open_time) AS prev_close,
           TIMESTAMPDIFF(HOUR, LAG(open_time) OVER (PARTITION BY symbol ORDER BY open_time), open_time) AS gap_hours
    FROM raw_klines
)
SELECT symbol, open_time, prev_close, `open`, low, `close`, trades,
       ROUND((`open` / prev_close - 1) * 100, 2) AS gap_pct
FROM g
WHERE gap_hours = 1 AND ABS(`open` / prev_close - 1) > 0.20;
