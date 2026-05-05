# Klipper 開發說明文件

本文件整理 Klipper 專案的開發內容、程式架構與近期開發重點，協助開發者快速理解專案全貌。

## 專案簡介

Klipper 是一套控制 3D 印表機的韌體／主機軟體。其設計特點是將「一般用途電腦」與「一個或多個微控制器（MCU）」結合：由主機端負責複雜的運動學運算與排程，由 MCU 負責即時的步進脈衝輸出與 I/O，透過自訂的序列／CAN 協議彼此溝通。

- 官方網站：https://www.klipper3d.org/
- 授權：GNU GPLv3（見 `COPYING`）

## 目錄結構

| 目錄 | 內容 |
| --- | --- |
| `src/` | 微控制器端（MCU）C 原始碼 |
| `src/avr/`, `src/stm32/`, `src/atsam/`, `src/atsamd/`, `src/lpc176x/`, `src/rp2040/`, `src/hc32f460/`, `src/pru/`, `src/ar100/`, `src/linux/` | 各 MCU 架構專用程式碼 |
| `src/generic/` | 跨架構共用的輔助程式碼 |
| `src/simulator/` | 提供其他架構下測試編譯用的樁程式 |
| `klippy/` | 主機端軟體（Python 為主） |
| `klippy/chelper/` | 主機端效能關鍵的 C 輔助模組（步進壓縮、序列佇列、trapq、運動學求解器等） |
| `klippy/kinematics/` | 各種機型運動學：cartesian、corexy、corexz、delta、deltesian、polar、rotary_delta、winch、hybrid_corexy/z、idex 等 |
| `klippy/extras/` | 可擴充模組（sensors、probes、fan、heater、bed_mesh、gcode_macro…） |
| `lib/` | 第三方函式庫（MCU 廠商 HAL 等） |
| `config/` | 各種印表機範例設定檔 |
| `scripts/` | 建置工具、燒錄工具、資料分析與繪圖腳本 |
| `test/` | 自動化測試案例（`test/klippy/` 為主機端迴歸測試） |
| `docs/` | 使用者與開發者文件 |

建置時會產生 `out/` 暫存目錄，最終韌體為 `out/klipper.elf.hex`（AVR）或 `out/klipper.bin`（ARM）。

## 建置系統

- 入口：根目錄 `Makefile`
- 組態：使用 Kconfig（`make menuconfig`）產生 `.config`，由 `src/Kconfig` 及各架構子目錄提供選項
- 編譯旗標：`-std=gnu11 -O2 -Wall`，開啟 LTO 與 `--gc-sections` 以最小化韌體大小
- Python 端：不需編譯，但 `klippy/chelper/` 會在主機端被動態編譯成 `.so`（見 `klippy/chelper/__init__.py`）

常用指令：

```bash
make menuconfig      # 設定目標 MCU
make                 # 編譯韌體
make flash           # 燒錄（依 MCU 而定）
make clean           # 清除 out/
```

## 主機端（klippy）架構

主機端程式由 `klippy/klippy.py` 作為進入點，重要模組：

- `klippy.py`：主程序、模組載入、主事件迴圈
- `reactor.py`：事件反應器，負責計時器與非阻塞 I/O 排程
- `configfile.py`：解析 `printer.cfg` 設定檔
- `gcode.py`：G-code 指令解析與分派
- `toolhead.py`：Look-ahead 移動佇列、加減速規劃
- `mcu.py` / `serialhdl.py` / `msgproto.py`：與 MCU 的訊息協議、時鐘同步
- `clocksync.py`：主機與各 MCU 之間的時鐘同步
- `stepper.py` / `pins.py`：步進馬達與腳位抽象
- `webhooks.py`：對外 API 伺服器（Moonraker 等前端使用）
- `mathutil.py`：數學工具（近期新增 Gaussian elimination 的矩陣 pseudo-inverse）

### chelper

`klippy/chelper/` 將效能關鍵路徑以 C 實作：

- `stepcompress.c` / `steppersync.c`：將移動壓縮為步進時間序列送往 MCU
- `itersolve.c` + `kin_*.c`：各運動學的迭代求解器
- `trapq.c`：梯形加速度區段佇列
- `serialqueue.c`：主機與 MCU 的序列佇列與重傳
- `trdispatch.c`：觸發（endstop／probe）事件分派

### extras 模組

`klippy/extras/` 以「模組化元件」方式提供擴充功能。每個 `.py` 檔實作一個可在 `printer.cfg` 中以 `[section]` 啟用的功能，例如：
`bed_mesh`, `probe`, `probe_eddy_current`, `axis_twist_compensation`, `input_shaper`, `resonance_tester`, `tmc2209` 等。

## MCU 端（src）架構

- 排程核心：`sched.c`，由架構特定 `main.c` 呼叫 `sched_main()`，依序跑 `DECL_INIT()`、再重複跑 `DECL_TASK()`
- 指令分派：`command.c` 的 `command_dispatch()`，指令由 `DECL_COMMAND()` 宣告
- 時間關鍵工作：透過 `sched_add_timer()` 註冊，計時器中斷處理位於 `sched_timer_dispatch()`
- 錯誤處理：`shutdown()` 巨集呼叫 `sched_shutdown()` 進入停機保護
- 常見子系統：`stepper.c`, `endstop.c`, `trsync.c`, `trigger_analog.c`, `adccmds.c`, `gpiocmds.c`, `i2ccmds.c`, `spicmds.c`, `pwmcmds.c`, `pulse_counter.c`
- 感測器：`sensor_adxl345.c`, `sensor_bmi160.c`, `sensor_mpu9250.c`, `sensor_lis2dw.c`, `sensor_icm20948.c`, `sensor_angle.c`, `sensor_ads1220.c`, `sensor_ldc1612.c`, `sensor_hx71x.c`, `thermocouple.c`
- 訊號處理：`sos_filter.c`（二階段聯串濾波器，用於類比觸發）

任務、初始化與指令函式都在中斷啟用狀態下執行，必須盡量避免超過 100µs 的阻塞，否則可能造成排程抖動、重傳甚至看門狗重啟。計時器函式則在關閉中斷下執行，須在數微秒內完成。

## 通訊協議

- 主機／MCU 以自訂協議溝通，細節見 `docs/Protocol.md`、`docs/MCU_Commands.md`、`docs/CANBUS_protocol.md`
- 指令與回應皆由 `DECL_COMMAND` / `DECL_OUTPUT` 宣告，建置腳本 `scripts/buildcommands.py` 會在編譯期產生對應資料結構

## 測試

- 位置：`test/klippy/`
- 方式：主機端迴歸測試讀取 `*.test` 設定檔與 G-code，跑過 Klippy 並比對輸出
- CI：`scripts/ci-build.sh`, `scripts/ci-install.sh` 以及 `scripts/check_whitespace.sh` 進行格式與建置檢查
- MCU 模擬：`src/simulator/` 可讓 MCU 程式在 PC 上試編

## 近期開發重點

根據最近的 git 提交，目前活躍的開發區域集中在：

### 1. Eddy current probe（`probe_eddy_current` / `probe_eddy_contact`）

對「接觸式敲擊（tap）」校正做了一連串精度與效能提升：

- 重寫 tap 分析的內部公式（`3ef23b37`）
- 移除對 numpy 的依賴，改以自有數學工具計算（`c1ed295d`）
- 於各次最小平方計算之間快取資料以減少重算（`5680b74b`）
- 將 tap 計算精度提升到 50nm（`55d7ed1a`）
- 處理 tap 資料時允許其他 timer 繼續執行，避免阻塞（`ec4b88db`）
- `probe_eddy_contact` 對 tap 分析加入完整性檢查（`db78babf`）
- 允許「tap 下壓」距離最小到 30µm（`aea1bcf5`）

### 2. 類比觸發濾波（`trigger_analog`）

- 允許在 `DigitalFilter` 內個別加入濾波器（`f05c66cb`）
- 合併 `DerivativeFilter` 進 `DigitalFilter`（`28c236df`）
- 預先儲存 25Hz 低通濾波器係數（250sps，`22dbdf10`）
- 配合 `sos_filter` 只配置必要的 SOS 項目數（`c8b2ef0c`）

### 3. 數學與 STM32 支援

- `mathutil` 新增以 Gaussian elimination 實作的泛型矩陣 pseudo-inverse（`12097eb4`）
- STM32G4：定義硬體 PWM 的 PB 腳位（`35ace529`）、啟用 Katapult 請求（`959a3cfb`）

### 4. 其他修補

- `gcode_button`：忽略空的 template（`b8c936f7`）
- `adxl345`：改善設定衝突錯誤訊息、修正預設 mux 指令可能被重複註冊的問題（`41b77b66`, `d487925b`）
- Katapult：將舊 `flash_can.py` 更新為新工具 `flashtool.py` 並補上 `Config_changes.md`（`29e26527`, `dbebcfd6`）
- 文件：更新 FAQ，heater 現在有 3 秒的 `MAX_HEAT_TIME`（`f3db41c6`）

## 開發者資源

- `docs/Code_Overview.md`：程式架構總覽
- `docs/CONTRIBUTING.md`：貢獻流程
- `docs/Protocol.md`, `docs/MCU_Commands.md`, `docs/API_Server.md`：協議與 API
- `docs/Debugging.md`：除錯技巧
- `docs/Benchmarks.md`：效能基準
- `docs/Kinematics.md`：運動學數學背景
- `docs/Eddy_Probe.md`：Eddy current probe 相關文件（對應近期開發重點）
