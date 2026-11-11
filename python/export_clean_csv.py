"""Xuất bảng crypto_1h.crypto_1h_clean từ MySQL ra crypto_1h_clean.csv (cho Power BI và notebook Python).

File xuất ra có đúng định dạng của file cũ (cùng tên cột, cùng thứ tự, cờ True/False, giờ dạng
'2017-08-17 04:00:00+00:00', ô trống là rỗng), nên Power BI chỉ cần bấm Làm mới (Refresh), không phải sửa gì.

Chạy:  python export_clean_csv.py   (hỏi mật khẩu MySQL, hoặc đặt trước $env:MYSQL_PASSWORD)
"""
import os
from getpass import getpass
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine

# ---- Cấu hình: sửa cho đúng máy bạn ----
ROOT = Path(__file__).resolve().parents[1]          # thư mục gốc của repo
OUT_PATH = ROOT / "data" / "crypto_1h_clean.csv"
HOST, PORT = "localhost", 3306
USER = "root"
PASSWORD = os.environ.get("MYSQL_PASSWORD") or getpass(f"Mật khẩu MySQL của {USER}: ")
DB, TABLE = "crypto_1h", "crypto_1h_clean"
# ----------------------------------------

FLAGS = ["gap_before", "is_flat_candle", "is_thin_period", "ohlc_suspect", "is_incomplete", "ret_outlier"]
NUM = ["open", "high", "low", "close", "volume", "quote_volume", "taker_buy_base", "taker_buy_quote", "ret_1h"]


def main():
    engine = create_engine(f"mysql+pymysql://{USER}:{PASSWORD}@{HOST}:{PORT}/{DB}?charset=utf8mb4")
    df = pd.read_sql(f"SELECT * FROM {TABLE} ORDER BY symbol, open_time", engine)

    df["open_time"] = pd.to_datetime(df["open_time"]).dt.tz_localize("UTC")   # giờ trong bảng là UTC
    df[NUM] = df[NUM].astype(float)
    df[FLAGS] = df[FLAGS].astype(bool)                                       # MySQL lưu 0/1 -> True/False

    df.to_csv(OUT_PATH, index=False, encoding="utf-8-sig")
    print(f"Đã lưu {OUT_PATH}: {len(df):,} dòng, {df.shape[1]} cột, đến {df['open_time'].max()}")


if __name__ == "__main__":
    main()
