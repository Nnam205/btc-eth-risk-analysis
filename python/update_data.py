"""Cập nhật data/crypto_1h_all.csv bằng nến 1h mới từ Binance.

Chạy:  python python/update_data.py
Sau đó: python python/load_to_mysql.py, chạy sql/03_clean.sql và sql/04_validate_export.sql,
rồi python python/export_clean_csv.py (xem README).
"""
import time
from pathlib import Path

import pandas as pd
import requests

ROOT = Path(__file__).resolve().parents[1]          # thư mục gốc của repo
CSV = ROOT / "data" / "crypto_1h_all.csv"
SYMBOLS = ["BTCUSDT", "ETHUSDT"]
URL = "https://api.binance.com/api/v3/klines"
COLS = ["symbol", "open_time", "open", "high", "low", "close", "volume",
        "quote_volume", "trades", "taker_buy_base", "taker_buy_quote"]


def fetch(symbol, start_ms):
    """Lấy toàn bộ nến 1h từ start_ms đến hiện tại (mỗi lần tối đa 1000 nến)."""
    rows = []
    while True:
        r = requests.get(URL, params={"symbol": symbol, "interval": "1h",
                                      "startTime": start_ms, "limit": 1000}, timeout=30)
        r.raise_for_status()
        batch = r.json()
        if not batch:
            break
        rows += batch
        if len(batch) < 1000:
            break
        start_ms = batch[-1][0] + 3_600_000
        time.sleep(0.3)
    return rows


def to_frame(symbol, klines):
    """Đổi mảng kline của Binance sang đúng các cột của file CSV."""
    d = pd.DataFrame(klines).iloc[:, :11]
    d.columns = ["t", "open", "high", "low", "close", "volume", "ct",
                 "quote_volume", "trades", "taker_buy_base", "taker_buy_quote"]
    d["symbol"] = symbol
    d["open_time"] = pd.to_datetime(d["t"], unit="ms", utc=True)
    for c in ["open", "high", "low", "close", "volume", "quote_volume",
              "taker_buy_base", "taker_buy_quote"]:
        d[c] = d[c].astype(float)
    d["trades"] = d["trades"].astype(int)
    return d[COLS]


def update(fetch_fn=fetch):
    old = pd.read_csv(CSV, encoding="utf-8-sig")
    old["open_time"] = pd.to_datetime(old["open_time"], utc=True)
    parts = [old]
    for s in SYMBOLS:
        # lấy lại từ nến cuối cùng đang có, vì nến đó có thể chưa đóng (số liệu dở dang)
        last = old.loc[old["symbol"] == s, "open_time"].max()
        new = to_frame(s, fetch_fn(s, int(last.timestamp() * 1000)))
        print(f"{s}: lấy {len(new)} nến từ {last}")
        parts.append(new)
    out = (pd.concat(parts)
             .drop_duplicates(["symbol", "open_time"], keep="last")  # bản mới ghi đè bản cũ
             .sort_values(["symbol", "open_time"]))
    out.to_csv(CSV, index=False, encoding="utf-8-sig")
    print(f"Đã ghi {len(out):,} dòng, dữ liệu mới nhất: {out['open_time'].max()}")


if __name__ == "__main__":
    update()
    print("Bước tiếp theo: python python/load_to_mysql.py, rồi sql/03_clean.sql, sql/04_validate_export.sql và python python/export_clean_csv.py")
