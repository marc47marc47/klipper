# Klipper 轉寫為 Rust 的可行性評估

本文件評估將 Klipper 從 C + Python 改寫為 Rust 的工程規模，列出需改寫的項目與難易度，並提出務實的推進策略。

## 專案規模（現況快照）

| 區塊 | 語言 | 約略規模 |
| --- | --- | --- |
| `src/` MCU 韌體 | C | 約 30,000 行，239 個 .c/.h 檔 |
| MCU 架構 | C | 12 個子目錄：avr、atsam、atsamd、stm32、lpc176x、rp2040、hc32f460、pru、ar100、linux、simulator、generic |
| `klippy/` 主機端 | Python | 約 40,000 行 |
| `klippy/chelper/` 效能核心 | C | 約 4,500 行 |
| `klippy/extras/` 擴充模組 | Python | 134 個模組 |
| `klippy/kinematics/` 運動學 | Python + `chelper/kin_*.c` | 16 個機型 |

難易度等級：★ 低　★★ 中　★★★ 高　★★★★ 極高

## A. MCU 韌體（`src/`）

| 項目 | 難易度 | 說明 |
| --- | --- | --- |
| A1. 排程核心（`sched.c`, `command.c`, `basecmd.c`） | ★★★ | Rust 需以 `#![no_std]` 加自製任務排程；`DECL_INIT/TASK/COMMAND` 巨集需改為 Rust 屬性巨集（proc-macro）並在編譯期產生指令表。原本由 `buildcommands.py` 組裝的 compile_time_request 要整併到 build.rs。 |
| A2. 指令協議（`msgblock`, VLQ 編解碼） | ★★ | 邏輯單純，Rust 改寫直接；需保持與主機端二進位相容。 |
| A3. GPIO / ADC / SPI / I2C / PWM 通用層 | ★★★ | 跨平台抽象；可借助 `embedded-hal` 生態，但 Klipper 的時序需求極嚴（µs 級），多數仍需自寫 HAL。 |
| A4. 步進輸出（`stepper.c`, `endstop.c`, `trsync.c`） | ★★★★ | 核心即時路徑，牽涉排程佇列與計時器中斷；正確性攸關印表機安全，需逐一驗證時序抖動。 |
| A5. 感測器驅動（adxl345、bmi160、mpu9250、lis2dw、icm20948、ads1220、ldc1612、hx71x、bme280、thermocouple…） | ★★ ~ ★★★ | 單一驅動難度不高，但數量眾多（>15 個），且大多搭配 `sensor_bulk` 串流格式。 |
| A6. 訊號處理（`sos_filter.c`, `trigger_analog.c`, `pulse_counter.c`） | ★★★ | 純演算法，Rust 改寫安全且可用 `const fn` 產生濾波器係數（呼應近期 `trigger_analog` 25Hz 低通快取的改動）。 |
| A7. 顯示（`lcd_hd44780.c`, `lcd_st7920.c`）、Neopixel、Buttons | ★ ~ ★★ | 邏輯簡單、時序需求中等。 |
| A8. 架構相依層（avr、stm32、rp2040、lpc176x、atsam、atsamd、hc32f460、pru、ar100、linux、simulator） | ★★★ ~ ★★★★ | **整體工程最大變數**。Rust 對各 MCU 的支援差異極大：<br>• rp2040 / stm32 / nrf：Rust 生態成熟（`rp-hal`, `stm32-rs`, `embassy`）★★★<br>• atsam / atsamd / lpc176x：部分 crate，但不完整 ★★★<br>• avr：Rust 支援仍為 nightly + LLVM 限制，8-bit 易遇 code size / LTO 問題 ★★★★<br>• hc32f460 / pru / ar100：幾乎無 Rust 支援，可能必須保留 C 或暫時放棄 ★★★★ |
| A9. CAN bus / Katapult bootloader 整合 | ★★★ | 需維持既有燒錄工具相容。 |
| A10. 建置系統（Kconfig、Makefile、linker script、`buildcommands.py`） | ★★★ | 須以 `cargo` + `build.rs` 或 `xtask` 取代 Makefile/Kconfig；多架構代表多個 `target` 與 `memory.x`。 |

## B. 主機端效能核心（`klippy/chelper/`）

| 項目 | 難易度 | 說明 |
| --- | --- | --- |
| B1. `stepcompress.c` / `steppersync.c`（步進壓縮） | ★★★★ | Klipper 最核心演算法之一，把移動拆解為 MCU 可接受的時間戳序列並做 LSQ 擬合；整數數學密集、效能熱點。改寫後必須逐步比對原輸出，否則印表機行為會變。 |
| B2. `itersolve.c` + `kin_*.c`（運動學迭代求解） | ★★★ | 16 個機型各一份 C 檔。演算法規則清楚，Rust 改寫直接，但需一併搬遷 `trapq`。 |
| B3. `trapq.c`（梯形佇列） | ★★★ | 小而關鍵，易改寫但難測試。 |
| B4. `serialqueue.c`（主機／MCU 佇列與重傳） | ★★★★ | 多執行緒、非同步、與 Python GIL 互動；`pollreactor` 也在此。若改寫需重新設計 Python 綁定（PyO3），或整個主機端一起改寫。 |
| B5. `trdispatch.c`（觸發分派） | ★★ | 邏輯清楚。 |
| B6. `pyhelper` / `__init__.py` 的 ctypes 綁定 | ★★ | 若主機端留在 Python，可用 `PyO3` 或維持 ctypes FFI 以 `cdylib` 匯出。 |

## C. 主機端 Python（`klippy/`）

| 項目 | 難易度 | 說明 |
| --- | --- | --- |
| C1. 核心（`klippy.py`, `reactor.py`, `configfile.py`, `gcode.py`, `toolhead.py`, `mcu.py`, `serialhdl.py`, `msgproto.py`, `clocksync.py`, `pins.py`, `stepper.py`, `webhooks.py`, `mathutil.py`） | ★★★★ | 動態載入、ConfigWrapper、事件反應器等 Python 風格深植。Rust 改寫需重新設計組態系統（`serde` + 自訂 section 解析）、事件循環（`tokio`）與模組註冊（trait object + `inventory`）。 |
| C2. `kinematics/*.py`（16 個機型） | ★★★ | 多為公式與邊界檢查，Rust 改寫順利，但需與 chelper 端運動學對齊。 |
| C3. `extras/` 134 個擴充模組 | ★★ ~ ★★★★ | 長尾；數量龐大是主要問題。<br>• 簡單：`fan.py`, `heater_fan.py`, `delayed_gcode.py`（★）<br>• 中等：`bed_mesh.py`, `probe.py`, `input_shaper.py`, TMC 系列（★★★）<br>• `gcode_macro.py` 使用 Jinja2，Rust 可用 `minijinja` 取代<br>• 困難：`probe_eddy_current.py`, `probe_eddy_contact.py`, `resonance_tester.py`, `axis_twist_compensation.py`, `adxl345.py`（近期開發熱區、數學密集）★★★★<br>• 必須維持 `printer.cfg` 語法 100% 相容，否則社群無法遷移。 |
| C4. Moonraker / API Server（`webhooks.py`） | ★★★ | 對外 JSON API 必須維持相容，否則整個 Moonraker 生態會斷掉。 |
| C5. 測試框架（`test/klippy/`） | ★★ | 迴歸測試以 G-code 驅動、比對輸出；改寫過程可沿用作為行為對照黃金標準。 |

## D. 周邊工具與文件

| 項目 | 難易度 | 說明 |
| --- | --- | --- |
| D1. `scripts/`（build、flash、分析、繪圖、CI） | ★★ | 多為 Python，可先保留；`buildcommands.py` 必須改寫以融入 Rust 建置。 |
| D2. `lib/` 第三方函式庫（廠商 HAL、CMSIS、TinyUSB 等） | ★★★ | 部分可由 Rust crate 取代（CMSIS / TinyUSB → `embassy-usb`），部分仍需 `bindgen` FFI。 |
| D3. 文件（`docs/`）與範例設定（`config/`） | ★ | 幾乎可直接沿用；僅需新增建置章節。 |

## 整體難易度總評

- **完全重寫**：★★★★（極高）。工程量相當於「重新實作一整個 Klipper」，需數人年。主要風險不在語言本身，而在於：
  1. 社群生態（Moonraker、Mainsail、Fluidd、各類自訂 `printer.cfg`）的相容性必須 100% 保持。
  2. 12 個 MCU 架構中有 3–4 個缺乏成熟的 Rust 支援（avr、hc32f460、pru、ar100）。
  3. `stepcompress` / `serialqueue` / `trsync` 等時序關鍵路徑必須逐位對齊原實作，否則可能造成失步或安全問題。

- **漸進式策略（建議）**：★★★（高但可行）。依風險與收益排序：
  1. **先改寫 `klippy/chelper/` 為 Rust `cdylib`**（經 PyO3 或 ctypes），不動 Python 主體。chelper 是效能熱點、界面穩定、測試覆蓋齊全，獲益/風險比最佳。
  2. **選定單一 MCU（建議 rp2040 或 stm32）做新韌體**，與既有 Python 主機端共存；其他 MCU 繼續沿用 C。
  3. **逐步將 `extras/` 中穩定、純運算型模組（如 `input_shaper`、運動學）改寫 Rust 並以 PyO3 掛回**。
  4. 最後再討論是否把整個 `klippy.py` 核心改寫；這是風險最高、回報最低的一步，除非目標是徹底擺脫 Python GIL。

- **只改寫特定子系統（PoC）**：★★。例如將 `probe_eddy_current` 的 tap 分析或 `trigger_analog` 濾波改寫為 Rust，可作為概念驗證。

## 建議切入點

若要做第一個 PoC，建議選擇：

> **`probe_eddy_current` 的 tap 分析改寫為 Rust `cdylib`**

理由：
- 規模小、數學密集（least squares、矩陣 pseudo-inverse），正是 Rust 強項。
- 對應近期最活躍的開發區塊（見 git log），改進空間具體。
- 對主機端其他部分侵入性低，失敗可快速回退。
- 現有 `test/klippy/` 可用來做行為對照。

## 關鍵檔案（若進入實作需優先閱讀）

- `klippy/chelper/stepcompress.c`, `steppersync.c`, `itersolve.c`, `trapq.c`, `serialqueue.c`, `trdispatch.c`
- `src/sched.c`, `src/command.c`, `src/basecmd.c`, `src/stepper.c`, `src/endstop.c`, `src/trsync.c`
- `klippy/klippy.py`, `klippy/reactor.py`, `klippy/toolhead.py`, `klippy/mcu.py`, `klippy/serialhdl.py`, `klippy/msgproto.py`
- `scripts/buildcommands.py`（編譯期指令表產生器）
- `Makefile`, `src/Kconfig`（建置系統入口）

## 驗證方式（若進入實作階段）

- 跑 `test/klippy/` 全套迴歸測試，逐 case 比對 G-code 展開輸出
- 以 `src/simulator/` 執行韌體層單元測試
- 實機以相同 `printer.cfg` 比對 Rust 版與 C 版步進時序（透過 `dump_mcu.py` 的序列紀錄逐位比對）
- Moonraker 前端連線測試以確認 API 相容
