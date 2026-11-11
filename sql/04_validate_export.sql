-- 04_validate_export.sql
-- Mục đích: kiểm tra lại bảng crypto_1h_clean sau khi làm sạch, rồi xuất ra CSV.
USE crypto_1h;
SELECT symbol, COUNT(*) FROM crypto_1h.raw_klines GROUP BY symbol;

-- (1) Không mất, không thừa dòng. Kỳ vọng: hai số bằng nhau, chênh lệch = 0
SELECT (SELECT COUNT(*) FROM raw_klines)      AS dong_goc,
       (SELECT COUNT(*) FROM crypto_1h_clean) AS dong_sach,
       (SELECT COUNT(*) FROM crypto_1h_clean) - (SELECT COUNT(*) FROM raw_klines) AS chenh_lech;

-- (2) Số lượng cờ. Kỳ vọng (dữ liệu đến 09/11/2026):
--     gap_before 56 (28/mã), is_flat_candle 12, ohlc_suspect 3, is_incomplete 2, ret_outlier 4.762
SELECT SUM(gap_before)    AS gap_before,
       SUM(is_flat_candle) AS is_flat_candle,
       SUM(is_thin_period) AS is_thin_period,
       SUM(ohlc_suspect)  AS ohlc_suspect,
       SUM(is_incomplete) AS is_incomplete,
       SUM(ret_outlier)   AS ret_outlier
FROM crypto_1h_clean;

-- (3) Sau khoảng thiếu, ret_1h phải là NULL. Kỳ vọng: 0
SELECT COUNT(*) AS ret_khac_null_sau_khoang_thieu
FROM crypto_1h_clean WHERE gap_before = 1 AND ret_1h IS NOT NULL;

-- (4) Giai đoạn thưa (trước 2018) không được gắn ngoại lai. Kỳ vọng: 0
SELECT COUNT(*) AS ngoai_lai_trong_giai_doan_thua
FROM crypto_1h_clean WHERE is_thin_period = 1 AND ret_outlier = 1;

-- (5) Mỗi mã có đúng 1 nến chưa đóng, và đó là nến mới nhất. Kỳ vọng: 2 dòng
SELECT symbol, open_time, `close` FROM crypto_1h_clean WHERE is_incomplete = 1;

-- (6) Ngoại lai theo năm và mã (xem có dồn vào năm biến cố: 2018, 2020, 2021 không)
SELECT YEAR(open_time) AS nam,
       SUM(symbol = 'BTCUSDT') AS btc,
       SUM(symbol = 'ETHUSDT') AS eth
FROM crypto_1h_clean WHERE ret_outlier = 1
GROUP BY YEAR(open_time) ORDER BY nam;

-- (7) Xuất file CSV cho Python / Power BI.
-- Cách dễ nhất trong Workbench: chuột phải bảng crypto_1h_clean > Table Data Export Wizard > CSV
-- (hoặc chạy SELECT bên dưới, bấm "Export recordset to an external file" trên thanh kết quả).
-- Giờ trong bảng là UTC. Khi phân tích theo giờ Việt Nam, cộng thêm 7 giờ.
SELECT * FROM crypto_1h_clean ORDER BY symbol, open_time;
