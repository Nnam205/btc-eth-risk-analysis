"""Đẩy crypto_1h_all.csv vào MySQL (bảng crypto_1h.raw_klines).

Cài thư viện (1 lần):  pip install pandas sqlalchemy pymysql
Chạy:                  python load_to_mysql.py
Mật khẩu: chạy xong script sẽ hỏi, gõ vào là được (không hiện chữ khi gõ).
Muốn khỏi gõ lại mỗi lần: đặt biến môi trường trước khi chạy, ví dụ PowerShell:  $env:MYSQL_PASSWORD = "..."
Không ghi mật khẩu thẳng vào file này để khỏi lộ khi đẩy repo lên GitHub.
"""
import os
from getpass import getpass
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

# ---- Cấu hình: sửa cho đúng máy bạn ----
ROOT = Path(__file__).resolve().parents[1]          # thư mục gốc của repo
CSV_PATH = ROOT / "data" / "crypto_1h_all.csv"
HOST, PORT = "localhost", 3306
USER = "root"
PASSWORD = os.environ.get("MYSQL_PASSWORD") or getpass(f"Mật khẩu MySQL của {USER}: ")
DB, TABLE = "crypto_1h", "raw_klines"
CHUNK = 20_000   # số dòng mỗi lần ghi
# ----------------------------------------

DDL = f"""
CREATE TABLE IF NOT EXISTS {TABLE} (
    symbol          VARCHAR(10)    NOT NULL,
    open_time       DATETIME       NOT NULL,          -- giờ UTC
    `open`          DECIMAL(20,8),
    high            DECIMAL(20,8),
    low             DECIMAL(20,8),
    `close`         DECIMAL(20,8),
    volume          DECIMAL(24,8),
    quote_volume    DECIMAL(28,8),
    trades          INT,
    taker_buy_base  DECIMAL(24,8),
    taker_buy_quote DECIMAL(28,8),
    PRIMARY KEY (symbol, open_time)
)
"""


def main():
    # 1) Tạo database nếu chưa có
    server = create_engine(f"mysql+pymysql://{USER}:{PASSWORD}@{HOST}:{PORT}/?charset=utf8mb4")
    with server.begin() as conn:
        conn.execute(text(f"CREATE DATABASE IF NOT EXISTS {DB} DEFAULT CHARACTER SET utf8mb4"))

    engine = create_engine(f"mysql+pymysql://{USER}:{PASSWORD}@{HOST}:{PORT}/{DB}?charset=utf8mb4")

    # 2) Đọc CSV (utf-8-sig: file có BOM dính vào tên cột đầu), bỏ múi giờ +00:00 vì cột MySQL là DATETIME (UTC)
    df = pd.read_csv(CSV_PATH, encoding="utf-8-sig")
    df["open_time"] = pd.to_datetime(df["open_time"], utc=True).dt.tz_localize(None)
    print(f"Đọc {len(df):,} dòng từ {CSV_PATH.name}")

    # 3) Làm mới bảng rồi ghi theo lô. Khoá chính (symbol, open_time) sẽ báo lỗi nếu file có dòng trùng
    with engine.begin() as conn:
        conn.execute(text(f"DROP TABLE IF EXISTS {TABLE}"))
        conn.execute(text(DDL))
    df.to_sql(TABLE, engine, if_exists="append", index=False, chunksize=CHUNK, method="multi")

    # 4) Đối chiếu số dòng
    with engine.connect() as conn:
        n = conn.execute(text(f"SELECT COUNT(*) FROM {TABLE}")).scalar()
    print(f"Bảng {DB}.{TABLE}: {n:,} dòng", "- KHỚP" if n == len(df) else "- LỆCH, kiểm tra lại")


if __name__ == "__main__":
    main()
