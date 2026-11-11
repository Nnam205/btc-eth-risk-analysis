-- 01_load_raw.sql
-- Mục đích: tạo database và nạp file gốc crypto_1h_all.csv vào MySQL.
-- File gốc chỉ đọc: bảng raw_klines không bao giờ bị sửa, mọi xử lý ở bước 03 làm trên bảng khác.
-- Chạy bằng MySQL Workbench: mở file, bấm biểu tượng tia sét (Ctrl+Shift+Enter) để chạy cả file.

CREATE DATABASE IF NOT EXISTS crypto_1h
  DEFAULT CHARACTER SET utf8mb4;
USE crypto_1h;

-- Bảng nhập tạm: giữ open_time dạng chuỗi vì file có đuôi '+00:00' (giờ UTC)
DROP TABLE IF EXISTS raw_import;
CREATE TABLE raw_import (
    symbol          VARCHAR(10),
    open_time       VARCHAR(32),
    `open`          DECIMAL(20,8),
    high            DECIMAL(20,8),
    low             DECIMAL(20,8),
    `close`         DECIMAL(20,8),
    volume          DECIMAL(24,8),
    quote_volume    DECIMAL(28,8),
    trades          INT,
    taker_buy_base  DECIMAL(24,8),
    taker_buy_quote DECIMAL(28,8)
);

-- CÁCH A (nhanh): LOAD DATA. Cần bật local_infile ở cả server lẫn Workbench:
--   Workbench: Database > Manage Connections > Advanced > ô "Others" thêm dòng  OPT_LOCAL_INFILE=1
--   Server (chạy 1 lần):  SET GLOBAL local_infile = 1;
-- Sửa đường dẫn cho đúng máy bạn, dùng dấu / thay cho \
SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'D:/Banance/crypto_1h_all.csv'
INTO TABLE raw_import
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;   -- bỏ dòng tiêu đề (dòng này có ký tự BOM nên không nạp được)

-- CÁCH B (nếu cách A báo lỗi): bấm chuột phải bảng raw_import > Table Data Import Wizard,
-- chọn file csv, "Use existing table" = raw_import. Chậm hơn (khoảng vài phút) nhưng không cần cấu hình.

-- Bảng gốc có kiểu dữ liệu đúng: open_time là DATETIME (UTC)
DROP TABLE IF EXISTS raw_klines;
CREATE TABLE raw_klines AS
SELECT symbol,
       STR_TO_DATE(LEFT(open_time, 19), '%Y-%m-%d %H:%i:%s') AS open_time,
       `open`, high, low, `close`, volume, quote_volume, trades,
       taker_buy_base, taker_buy_quote
FROM raw_import;

ALTER TABLE raw_klines ADD PRIMARY KEY (symbol, open_time);   -- đồng thời kiểm tra trùng khoá: trùng sẽ báo lỗi

DROP TABLE raw_import;

-- Kiểm tra nhanh: kỳ vọng 2 mã, mỗi mã 80.805 dòng (đến 09/11/2026), bắt đầu 17/08/2017 04:00 UTC
SELECT symbol, COUNT(*) AS so_dong, MIN(open_time) AS dau, MAX(open_time) AS cuoi
FROM raw_klines
GROUP BY symbol;
