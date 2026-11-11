-- 03_clean.sql
-- Mục đích: tạo bảng crypto_1h_clean = bảng gốc + các cột cờ + ret_1h. KHÔNG xoá, KHÔNG sửa giá.
-- Cần MySQL 8.0 trở lên (dùng hàm cửa sổ LAG, ROW_NUMBER và CTE).
-- Nguyên tắc giống notebook cleaning: gắn cờ thay vì xoá để bước EDA còn lọc được.
USE crypto_1h;

-- 1) Ngưỡng ngoại lai của ret_1h, tính RIÊNG từng mã, chỉ trên giai đoạn từ 01/01/2018,
--    bỏ nến chưa đóng và giờ có khoảng thiếu. Ngưỡng = Q1 - 3*IQR và Q3 + 3*IQR.
--    Phân vị nội suy tuyến tính (cho kết quả giống pandas quantile).
DROP TABLE IF EXISTS tmp_ret;
CREATE TABLE tmp_ret AS
SELECT symbol,
       LN(`close` / prev_close) AS ret_1h
FROM (
    SELECT symbol, open_time, `close`,
           LAG(`close`)     OVER w AS prev_close,
           LAG(open_time)   OVER w AS prev_time,
           ROW_NUMBER()     OVER (PARTITION BY symbol ORDER BY open_time DESC) AS rn_desc
    FROM raw_klines
    WINDOW w AS (PARTITION BY symbol ORDER BY open_time)
) x
WHERE open_time >= '2018-01-01'
  AND rn_desc > 1                                   -- bỏ nến cuối chưa đóng
  AND TIMESTAMPDIFF(HOUR, prev_time, open_time) = 1; -- bỏ giờ ngay sau khoảng thiếu

DROP TABLE IF EXISTS tmp_ranked;
CREATE TABLE tmp_ranked AS
SELECT symbol, ret_1h,
       ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY ret_1h) AS rn,
       COUNT(*)     OVER (PARTITION BY symbol)                 AS n
FROM tmp_ret;

DROP TABLE IF EXISTS ret_thresholds;
CREATE TABLE ret_thresholds AS
SELECT symbol, n AS gio_xet, q1, q3,
       q1 - 3 * (q3 - q1) AS nguong_duoi,
       q3 + 3 * (q3 - q1) AS nguong_tren
FROM (
    SELECT a.symbol, a.n,
           -- phân vị p: vị trí (n-1)*p, lấy 2 giá trị kề nhau rồi nội suy
           MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.25)+1 THEN a.ret_1h END)
         + ((a.n-1)*0.25 - FLOOR((a.n-1)*0.25))
         * (MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.25)+2 THEN a.ret_1h END)
          - MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.25)+1 THEN a.ret_1h END)) AS q1,
           MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.75)+1 THEN a.ret_1h END)
         + ((a.n-1)*0.75 - FLOOR((a.n-1)*0.75))
         * (MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.75)+2 THEN a.ret_1h END)
          - MAX(CASE WHEN a.rn = FLOOR((a.n-1)*0.75)+1 THEN a.ret_1h END)) AS q3
    FROM tmp_ranked a
    GROUP BY a.symbol, a.n
) t;

-- 2) Bảng sạch: thêm cờ
DROP TABLE IF EXISTS crypto_1h_clean;
CREATE TABLE crypto_1h_clean AS
SELECT c.symbol, c.open_time, c.`open`, c.high, c.low, c.`close`,
       c.volume, c.quote_volume, c.trades, c.taker_buy_base, c.taker_buy_quote,
       -- nến ngay sau một khoảng thiếu giờ (sàn bảo trì), KHÔNG điền giờ thiếu
       COALESCE(c.gap_hours > 1, 0)                                        AS gap_before,
       -- nến phẳng: open = high = low = close
       (c.`open` = c.high AND c.high = c.low AND c.low = c.`close`)        AS is_flat_candle,
       -- giai đoạn thị trường mỏng (trước 2018)
       (c.open_time < '2018-01-01')                                        AS is_thin_period,
       -- nến nghi sai giá: phẳng nhưng có giao dịch, hoặc open lệch close trước > 20%
       COALESCE(( c.`open` = c.high AND c.high = c.low AND c.low = c.`close` AND c.volume > 0)
        OR (c.gap_hours = 1 AND ABS((c.`open` / c.prev_close - 1) * 100) > 20), 0) AS ohlc_suspect,
       -- nến cuối mỗi mã: tải trong giờ đó nên chưa đóng
       (c.rn_desc = 1)                                                     AS is_incomplete,
       -- log-return 1 giờ, NULL khi có khoảng thiếu (để diff/rolling không tính xuyên qua)
       CASE WHEN c.gap_hours = 1 THEN LN(c.`close` / c.prev_close) END     AS ret_1h,
       -- ngoại lai: chỉ xét từ 2018, ngoài ngưỡng IQR x 3 của từng mã
       COALESCE(c.open_time >= '2018-01-01' AND c.gap_hours = 1
        AND (LN(c.`close` / c.prev_close) < t.nguong_duoi
          OR LN(c.`close` / c.prev_close) > t.nguong_tren), 0)             AS ret_outlier
FROM (
    SELECT r.*,
           LAG(`close`)   OVER w AS prev_close,
           TIMESTAMPDIFF(HOUR, LAG(open_time) OVER w, open_time) AS gap_hours,
           ROW_NUMBER()   OVER (PARTITION BY symbol ORDER BY open_time DESC) AS rn_desc
    FROM raw_klines r
    WINDOW w AS (PARTITION BY symbol ORDER BY open_time)
) c
JOIN ret_thresholds t ON t.symbol = c.symbol;

ALTER TABLE crypto_1h_clean ADD PRIMARY KEY (symbol, open_time);

DROP TABLE tmp_ret;
DROP TABLE tmp_ranked;

SELECT * FROM ret_thresholds;
