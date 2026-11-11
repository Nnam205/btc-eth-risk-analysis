# Dữ liệu và cách làm sạch

## Dữ liệu

| | |
|---|---|
| Nguồn | Binance, giao ngay, cặp BTCUSDT và ETHUSDT, nến 1 giờ |
| Quy mô | 161.610 dòng (2 mã × 80.805 nến), 11 cột |
| Thời gian | 17/08/2017 – 09/11/2026 (3.371 ngày đầy đủ) |
| Giờ trong file | UTC. Khi phân tích theo giờ Việt Nam thì cộng thêm 7 giờ |
| Các cột | mã, giờ mở nến, giá mở, cao, thấp, đóng, khối lượng, số lệnh, khối lượng mua chủ động |

## Các bước kiểm tra (file `sql/02_quality_checks.sql`)

Kết quả với dữ liệu mốc 09/11/2026:

| Kiểm tra | Kết quả |
|---|---|
| Giá trị thiếu, dòng trùng | Không có |
| Lỗi logic giá (cao < thấp, giá không dương...) | 0 dòng |
| Khoảng thiếu giờ | 128 giờ mỗi mã (khoảng 0,16%), gom thành 28 khoảng, dài nhất 33 giờ. Hai mã thiếu cùng khung giờ nên là lúc sàn bảo trì |
| Nến không có giao dịch | 10 nến, đều là nến phẳng |
| Nến nghi sai giá | 3 nến (ví dụ ETH 22/08/2017: giá mở lệch gần −48% so với giờ trước) |
| Giai đoạn thị trường mỏng | Trước 2018, giá nhảy nhiều do ít lệnh |

## Các cờ gắn khi làm sạch (file `sql/03_clean.sql`)

Nguyên tắc: **gắn cờ thay vì xóa**, để lúc phân tích có thể lọc ra.

| Cờ | Ý nghĩa | Vì sao giữ |
|---|---|---|
| `gap_before` | Nến nằm ngay sau một khoảng thiếu giờ | Không điền giờ thiếu vì sẽ là bịa dữ liệu; `ret_1h` ở dòng này để trống để không tính xuyên qua khoảng trống |
| `is_flat_candle` | Nến phẳng (mở = cao = thấp = đóng) | Phần lớn là giờ không có giao dịch |
| `is_thin_period` | Trước năm 2018 | Giữ để so sánh có và không có 2017 |
| `ohlc_suspect` | Nến nghi sai giá | Chỉ 3 dòng, không sửa |
| `is_incomplete` | Nến cuối cùng, chưa đóng | Bỏ khi phân tích |
| `ret_outlier` | Giờ giá nhảy bất thường | Là biến cố thị trường thật; xóa sẽ mất đúng những giờ quan trọng nhất |

Ngưỡng giờ bất thường tính riêng cho từng mã, dùng khoảng tứ phân vị × 3 trên log-return 1 giờ, chỉ từ 2018 và bỏ nến chưa đóng. Giai đoạn 2017 bị loại khỏi phép tính ngưỡng vì thị trường còn mỏng, nếu không sẽ làm lệch cả ngưỡng.

## Kiểm tra lại (file `sql/04_validate_export.sql`)

- Số dòng bảng sạch bằng số dòng bảng gốc.
- `ret_1h` để trống ở mọi dòng sau khoảng thiếu giờ.
- Giai đoạn mỏng không bị gắn ngoại lai.
- Mỗi mã có đúng một nến chưa đóng, và đó là nến mới nhất.
