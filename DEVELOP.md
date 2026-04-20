# Klipper 開發文件 (DEVELOP.md)

本文件彙整 Klipper 專案的開發相關資訊，適合想參與開發、除錯、
或深入了解 Klipper 架構的工程師閱讀。官方使用者文件請見
[docs/Overview.md](docs/Overview.md)。

---

## 1. 專案簡介

Klipper 是一套 3D 印表機韌體，透過將通用計算機（例如 Raspberry Pi）
與一個或多個微控制器（MCU）結合，以達到高精度的運動控制。

- 官方網站：https://www.klipper3d.org/
- 授權：GNU GPLv3（詳見 [COPYING](COPYING)）
- 原始儲存庫：https://github.com/Klipper3d/klipper

---

## 2. 目錄結構

| 路徑 | 用途 |
| --- | --- |
| `src/` | MCU 端 C 原始碼 |
| `src/avr/` `src/stm32/` `src/atsam/` `src/atsamd/` `src/lpc176x/` `src/pru/` `src/linux/` `src/rp2040/` `src/hc32f460/` `src/ar100/` | 各架構專屬 MCU 程式 |
| `src/generic/` | 跨架構通用輔助程式 |
| `src/simulator/` | 可在其他架構測試編譯的 stub |
| `klippy/` | 主機端 Python 程式（Klippy 主程式） |
| `klippy/chelper/` | Klippy 所用之 C 輔助碼（透過 CFFI 呼叫） |
| `klippy/kinematics/` | 各種運動學模組（cartesian、corexy、delta…） |
| `klippy/extras/` | 可擴充模組（sensor、probe、macro、fan…） |
| `lib/` | 第三方函式庫 |
| `config/` | 範例印表機設定檔 |
| `scripts/` | 編譯、安裝、除錯用的輔助腳本 |
| `test/` | 自動化回歸測試 |
| `docs/` | 完整文件（Markdown） |
| `out/` | 編譯產生的暫存目錄（`make` 後出現） |

編譯後的韌體產物：
- AVR 平台：`out/klipper.elf.hex`
- ARM 平台：`out/klipper.bin`

---

## 3. 開發環境準備

### 3.1 主機端（Klippy）Python 依賴

依據 `scripts/klippy-requirements.txt`：

```
greenlet    # reactor.py 使用
cffi        # chelper 與 greenlet 相依
Jinja2      # gcode_macro.py 模板
markupsafe  # Jinja2 相依
pyserial    # USB/UART 連線
python-can  # CAN bus 連線
msgspec     # webhooks.py 可選依賴
```

建議建立獨立的 virtualenv：

```bash
python3 -m venv ~/klippy-env
~/klippy-env/bin/pip install -r scripts/klippy-requirements.txt
```

### 3.2 系統套件與工具鏈

依 OS 執行對應腳本：

- `scripts/install-debian.sh`
- `scripts/install-ubuntu-22.04.sh` / `install-ubuntu-18.04.sh`
- `scripts/install-octopi.sh`
- `scripts/install-centos.sh`
- `scripts/install-arch.sh`
- `scripts/install-beaglebone.sh`

各 MCU 架構交叉編譯工具鏈需求，參考 `scripts/ci-install.sh`。

---

## 4. 編譯 MCU 韌體

Klipper 使用以 Kconfig 為基礎的 Makefile 系統。

```bash
make menuconfig     # 選擇 MCU、bootloader、通訊介面、時脈等
make                # 編譯韌體
make flash          # 燒錄（依板子可能需先手動進入 bootloader）
make clean          # 清除輸出
make V=1            # 顯示完整編譯指令
```

常用旗標（由 `Makefile` 提供）：

- `-flto=auto -fwhole-program`：啟用整體程式最佳化
- `-O2 -Wall`：最佳化與警告
- `-ffunction-sections -fdata-sections -Wl,--gc-sections`：縮減體積

進階燒錄腳本：

- `scripts/flash-linux.sh`：Linux MCU
- `scripts/flash-pru.sh`：BeagleBone PRU
- `scripts/flash-sdcard.sh`：透過 SD 卡更新韌體
- `scripts/flash_usb.py`：USB DFU / CANBoot 等
- `scripts/update_chitu.py` / `update_mks_robin.py`：Chitu / MKS Robin 板專屬

### 4.1 編譯產物總覽

Klipper 專案實際「被編譯」的產物分成兩類：**MCU 韌體** 與
**Klippy 執行期 C 輔助庫**。

#### (A) MCU 韌體

每次 `make` 依 `.config` 選定的架構產生一份。共用主目標 `out/klipper.elf`，
再由 `objcopy` 轉成實際燒錄格式：

| 架構 | 原始碼目錄 | 最終產物 | 格式 |
| --- | --- | --- | --- |
| AVR (Arduino Mega, etc.) | `src/avr/` | `out/klipper.elf.hex` | Intel HEX |
| STM32 / GD32 / N32 | `src/stm32/` | `out/klipper.bin` (+ `klipper.elf`) | 裸 binary |
| Atmel SAM (SAM3/4) | `src/atsam/` | `out/klipper.bin` | 裸 binary |
| Atmel SAMD (SAMC21/D21/D51) | `src/atsamd/` | `out/klipper.bin` + `out/klipper.elf.hex` | binary + HEX |
| NXP LPC176x (Smoothieboard) | `src/lpc176x/` | `out/klipper.bin` | 裸 binary |
| RP2040 / RP2350 | `src/rp2040/` | `out/klipper.bin` + `out/klipper.uf2` | binary + UF2 |
| HC32F460 (華大) | `src/hc32f460/` | `out/klipper.bin` | 裸 binary |
| BeagleBone PRU | `src/pru/` | `out/pru0.elf` + `out/pru1.elf` | 兩顆 PRU 各一 ELF |
| Allwinner AR100 | `src/ar100/` | `out/ar100.bin` | 逆序位元組 binary |
| Linux MCU (Pi GPIO) | `src/linux/` | `out/klipper.elf` | Linux ELF 可執行檔 |
| Simulator | `src/simulator/` | `out/klipper.elf` | 僅測試編譯用 |

> Anycubic Vyper（GD32F103RET6）走 `src/stm32/`，產出 `out/klipper.bin`
> 後再由外部工具 pad 成 489472 bytes 供 bootloader 讀取。

#### (B) Klippy 執行期 C 輔助庫

由 `klippy/chelper/__init__.py` 在 **Klippy 啟動時**自動呼叫 gcc 編譯
（不是 `make` 的一部分）：

| 產物 | 原始碼 | 用途 |
| --- | --- | --- |
| `klippy/chelper/c_helper.so` | `klippy/chelper/*.c`（共 22 個 .c） | Python 透過 CFFI dlopen，涵蓋 step compression、trapq、kinematics solve、serial queue、shaper 等熱點迴圈 |

涵蓋模組：
- 通訊：`serialqueue.c`, `msgblock.c`, `pollreactor.c`, `pyhelper.c`
- 運動：`stepcompress.c`, `steppersync.c`, `itersolve.c`, `trapq.c`, `trdispatch.c`
- 運動學：`kin_cartesian.c`, `kin_corexy.c`, `kin_corexz.c`, `kin_delta.c`,
  `kin_deltesian.c`, `kin_polar.c`, `kin_rotary_delta.c`, `kin_winch.c`,
  `kin_generic.c`, `kin_idex.c`, `kin_extruder.c`, `kin_shaper.c`

首次啟動會編譯，之後以 mtime 判斷是否重建，故日常啟動不會重新編譯。

#### (C) 編譯過程暫存 / 衍生物（`out/` 下）

| 檔 | 作用 |
| --- | --- |
| `out/autoconf.h` | 由 `.config` (Kconfig) 轉成 C 標頭 |
| `out/board-link` | 指向當前選定 `src/<arch>/` 的 symlink |
| `out/compile_time_request.o` | `scripts/buildcommands.py` 掃描 `DECL_COMMAND` / `DECL_CONSTANT` 後產生的指令表 |
| `out/klipper.dict` | MCU 指令字典（協定壓縮表）；`test_klippy.py` 必需 |
| `out/klipper.elf.map` | 連結 map 檔（除錯用） |
| `out/src/**/*.o` | 各 `.c` 中間物件 |
| `out/src/**/*.o.ctr` | `compile_time_request` 抽取階段 |
| `out/*.ld` | 連結腳本（由 `.lds.S` 生成） |

#### (D) **不會**被編譯的部分

- `klippy/*.py`、`klippy/extras/*.py`、`klippy/kinematics/*.py` — 純 Python
- `scripts/*.py`、`scripts/*.sh` — 純腳本
- `config/*.cfg` — 文字設定

#### (E) 一次 `make` 的典型產物（以 STM32 為例）

```
out/klipper.elf         ; 含符號的 ELF，供 gdb / addr2line 使用
out/klipper.bin         ; 裸 binary，實際燒錄物
out/klipper.elf.map     ; 連結布局
out/klipper.dict        ; 指令字典（~30 KB JSON）
out/autoconf.h          ; 由 .config 生成
out/compile_time_request.o
out/src/…*.o            ; 各 .c 中間產物
```

#### 記憶口訣

> 一次 `make` → **一份 MCU 韌體**（`klipper.bin` / `.hex` / `.uf2`）
> Klippy 首次啟動 → **一份 `c_helper.so`**
> 其餘皆為 Python 解譯或 shell 腳本，不產生二進位檔案。

---

## 5. 原始碼架構

### 5.1 MCU 端執行流程

1. 架構專屬 `main.c`（例如 `src/avr/main.c`）呼叫 `sched_main()`（`src/sched.c`）。
2. `sched_main()` 先執行所有 `DECL_INIT()` 標註之初始化函式。
3. 接著反覆執行所有 `DECL_TASK()` 標註之任務函式。
4. `command_dispatch()`（`src/command.c`）由板端 I/O 程式呼叫，
   解析序列／CAN 傳來的指令並分派至對應 `DECL_COMMAND()` 註冊之函式。

排程注意事項：
- Task / init / command 函式執行時中斷保持開啟；須避免長延遲
  （>100µs 抖動、>500µs 可能重傳、>100ms 觸發看門狗 reboot）。
- 時序敏感工作請透過 `sched_add_timer()` 由 timer IRQ 處理；
  timer 函式以關閉中斷的狀態執行，須在數 µs 內完成。
- 偵測錯誤時呼叫 `shutdown()` 巨集，會執行所有 `DECL_SHUTDOWN()` 函式。

所有 GPIO 由架構專屬包裝（例如 `src/avr/gpio.c`）提供，
經 LTO 後多被 inline，無額外執行時成本。

### 5.2 Klippy（主機端）

- `klippy/klippy.py`：主進入點
- `klippy/reactor.py`：基於 greenlet 的事件迴圈
- `klippy/mcu.py`：MCU 抽象、指令排程
- `klippy/serialhdl.py`：序列 / CAN 傳輸層
- `klippy/msgproto.py`：MCU 協定編解碼（見 `docs/Protocol.md`）
- `klippy/clocksync.py`：主機與 MCU 時脈同步
- `klippy/toolhead.py`：運動佇列、look-ahead、加減速規劃
- `klippy/stepper.py`：步進馬達邏輯
- `klippy/gcode.py`：G-code 解析與分派
- `klippy/configfile.py`：`printer.cfg` 載入
- `klippy/webhooks.py`：JSON API 伺服器（`/tmp/klippy_uds`）
- `klippy/chelper/`：C 加速程式，透過 CFFI 呼叫，負責步進脈衝生成等
  熱點迴圈

運動學與擴充模組採外掛式載入：將 `.py` 放到
`klippy/kinematics/` 或 `klippy/extras/`，即可由設定檔章節名稱引用。

---

## 6. 通訊協定

Klipper 採 host↔MCU RPC 架構，訊息在編譯期被 `buildcommands.py`
壓縮成 ID，執行期傳遞緊湊二進位封包。

- `docs/Protocol.md`：協定概觀與壓縮原理
- `docs/MCU_Commands.md`：所有低階 MCU 指令
- `docs/CANBUS_protocol.md`：CAN bus 傳輸格式
- `docs/API_Server.md`：Klippy 對外 JSON-RPC API

---

## 7. 測試與除錯

### 7.1 白名單／空白格式檢查

```bash
./scripts/check_whitespace.sh
```

### 7.2 Klippy 回歸測試

需先取得資料字典（data dictionary）：

1. 從
   https://github.com/Klipper3d/klipper/issues/1438
   下載對應版本的 `klipper-dict-YYYYMMDD.tar.gz`。
2. 解壓並執行：

```bash
tar xfz klipper-dict-20??????.tar.gz
~/klippy-env/bin/python ~/klipper/scripts/test_klippy.py \
    -d dict/ ~/klipper/test/klippy/*.test
```

測試腳本放在 `test/klippy/*.test`，對應的印表機設定檔放在
同目錄 `*.cfg`。新增功能時請同步補充回歸案例。

### 7.3 MCU 指令手動輸入

可用 `klippy/console.py` 直接對 MCU 送 `DECL_COMMAND()` 指令：

```bash
~/klippy-env/bin/python ./klippy/console.py /tmp/pseudoserial
```

工具內輸入 `HELP` 可看更多功能；`--help` 則列出命令列選項。

### 7.4 批次模式與 MCU 指令追蹤

Klippy 可以 batch 模式將 G-code 檔轉成 MCU 指令，協助分析
低階行為與 diff 比較，詳見 `docs/Debugging.md`。

### 7.5 其他有用工具

- `scripts/graph_motion.py` / `graph_shaper.py` / `graph_accelerometer.py`
  / `graph_mesh.py` / `graph_extruder.py` / `graph_temp_sensor.py`：
  以 matplotlib 視覺化輸出資料
- `scripts/calibrate_shaper.py`：輸入共振測量後產生
  input shaper 建議
- `scripts/logextract.py`：從 `klippy.log` 抽取錯誤上下文
- `scripts/dump_mcu.py`：匯出 MCU 當前狀態
- `scripts/checkstack.py`：估算 C 函式的 stack 使用量
- `scripts/stepstats.py` / `graphstats.py`：步進統計分析

### 7.6 CI

GitHub Actions 透過 `scripts/ci-build.sh` 進行：

1. 空白檢查
2. 多架構 MCU 韌體編譯
3. Klippy 回歸測試（Python 3 / Python 2 兩套環境）

本機要完整重現 CI，可先執行 `scripts/ci-install.sh`
再執行 `scripts/ci-build.sh`。

---

## 8. 編碼與提交規範

摘自 `docs/CONTRIBUTING.md`：

- 所有提交需於送出前本機測試；PR 會被部署到成千上萬台印表機，
  品質是優先考量。
- 不接受 experimental 性質的 PR；請在自己的 fork 實驗完成後再 PR。
- 需通過所有回歸測試。
- 修 bug 時需了解 root cause，修改應對準根因。
- 禁止殘留偵錯程式碼、註解掉的舊碼、過多 TODO 或「施工中」宣告。
- 註解以幫助維護為主，不解釋 what，聚焦 why。
- 每次 commit 需附 `Signed-off-by`，遵守
  [Developer Certificate of Origin](docs/developer-certificate-of-origin)。
- commit message 採短主旨 + 詳細本文的格式（可參考
  `git log` 既有風格）。

---

## 9. 新增硬體支援的常見流程

1. 新 MCU 架構：於 `src/<arch>/` 建目錄，提供 `main.c`、`Makefile`、
   `gpio.c`、`timer.c`、`serial.c` 等；於 `src/Kconfig` 加入新選項。
2. 新 sensor / probe：於 `klippy/extras/` 新增 `.py`，並於
   `docs/Config_Reference.md` 補上設定說明；必要時在
   `src/` 加對應 `sensor_*.c`。
3. 新運動學：於 `klippy/kinematics/` 新增 `.py`，並於
   `docs/Kinematics.md` 補上數學說明。
4. 新增 `config/printer-*.cfg` 範例檔，命名遵循
   `docs/Example_Configs.md`。
5. 增補 `test/klippy/` 回歸案例。

---

## 10. 延伸閱讀

開發者應先閱讀的核心文件：

- [docs/Code_Overview.md](docs/Code_Overview.md)
- [docs/Kinematics.md](docs/Kinematics.md)
- [docs/Protocol.md](docs/Protocol.md)
- [docs/MCU_Commands.md](docs/MCU_Commands.md)
- [docs/API_Server.md](docs/API_Server.md)
- [docs/Debugging.md](docs/Debugging.md)
- [docs/Benchmarks.md](docs/Benchmarks.md)
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
- [docs/Packaging.md](docs/Packaging.md)
- [docs/Bootloaders.md](docs/Bootloaders.md) /
  [docs/Bootloader_Entry.md](docs/Bootloader_Entry.md)
- [docs/CANBUS.md](docs/CANBUS.md) /
  [docs/CANBUS_protocol.md](docs/CANBUS_protocol.md) /
  [docs/CANBUS_Troubleshooting.md](docs/CANBUS_Troubleshooting.md)

回報問題 / 聯絡開發者：[docs/Contact.md](docs/Contact.md)。
