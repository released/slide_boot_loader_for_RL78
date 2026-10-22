[知識庫首頁](https://released.github.io/) · [ISP Tool 操作](../slide_isp_tool_for_RL78/)

<a id="article_top"></a>

# RL78 Bootloader 實作指南

本頁整理 MCU CAN device 的 Boot／App 工程、metadata、向量與啟動流程。
F13、F24 各自使用獨立工程，沿用 C header 編輯、產生與映像驗證流程。

## MCU CAN device

<!-- DEVICE_MODE_NAV_BEGIN -->
Classical CAN 的 F13／F24 共用 metadata、IRQ 與更新教學，硬體設定由各自工程章節說明。
CAN FD 使用 F24 的獨立 Boot／App 與 Transfer 工程。

| 分類 | 工程／範例 | 操作入口 |
| --- | --- | --- |
| Classical CAN：F13／F24 | [F13 Boot 啟動與更新](#f13-boot-decision)／[F24 工程配置與建置](#f24-can-device) | [App 更新](https://released.github.io/slide_isp_tool_for_RL78/#f13-device-update) |
| CAN FD：F24 | [Boot／App 設定、timing、metadata、IRQ 與 Flash](#can-fd-device-engineering) | [CAN FD App 更新](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-update) |
| Custom Transfer | F13／F24 Classical CAN；F24 CAN FD | [範例分類與通訊測試](https://released.github.io/slide_isp_tool_for_RL78/#custom-transfer) |
<!-- DEVICE_MODE_NAV_END -->

- [Metadata 與 IRQ 設定](#device-metadata-vector-workshop)
- [App BIN 更新耗時參考](#device-update-timing)
- [Boot／App 移植](#boot-app-porting)
- [Flash／metadata 每 byte 與 CAN 格式](#flash-metadata-can-reference)

## F13 (MCU CAN device)：Boot 啟動與更新

<!-- F13_BOOT_DECISION_BEGIN -->
<a id="f13-boot-decision"></a>

本節整理 F13 (MCU CAN device) 的 Boot 啟動與更新狀態。
對應來源為 `r_main.c` 與 `can_boot_transport.c`。

#### A. 每次 reset 的 app 有效性檢查：全部通過才可啟動

| 檢查 | 目前 F13 build 必須符合 |
| --- | --- |
| Reset entry | `0x2000` 的第一個 DWORD 不為 `0xFFFFFFFF`；只檢查非 erased，沒有完整反組譯／驗證跳轉目的地 |
| Metadata header | `0x2100` magic=`0x004E4143`；format6、core length128、flags=`0x0003`；protocol ID1／version5、checksum type1（CRC32）、target=`0xF13B`、Classical CAN／standard ID 格式全部匹配 |
| Metadata reserved | 整區256 bytes 中後128 bytes（`0x2180..0x21FF`）全部為 `0xFF` |
| Metadata policy | UPD1 version3／size32、DEVICE_APP／CAN、F1V1 IRQ ABI；minimum Boot 不高於目前 Boot；`0x74..0x77` version control 為0或1，UART baud 與其餘保留欄位為0 |
| Image size | manifest size 含尾端 CRC4 bytes，介於516與121856 bytes，且4-byte aligned |
| App version | `0x00MMmmpp`；啟動時驗證欄位有效。更新版本比較在 START 執行，依目前有效 App 的 version control 判斷；build 不參與比較 |
| Flash layout | app start=`0x2000`、capacity=`0x1DC00`、code Flash=`0x20000`、boot reserve=`0x2000`、erase=`0x400`、minimum=`0x204`，均等於 boot 編譯設定 |
| CAN contract | nominal mask=`0x04`（500K）、data mask=0、request ID=`0x700`、response ID=`0x701`，均等於 boot 編譯設定 |
| CRC32 | 對 `[app_start, app_start + image_size - 4)` 計算 CRC32，等於該 image 最後4 bytes 的 LE32 stored CRC |

Boot 直接比對 MCU ASCII family／part，要求 build 已初始化，並檢查
UPD1更新政策、IRQ ABI與最低boot版本。PC仍須另作image/live device比對。
CRC是完整性，不是簽章或身分認證；最低boot版本不等於app防回滾。

#### B. ENTER marker 與啟動路徑

1. app 有效且沒有 ENTER marker：正常返回 startup，轉到 `0x2000` 的 app table。
2. app 收到 standard data ID=`0x700`、DLC1、data=`06` 的明確 ENTER request 時，
   先嘗試送 ACK（ID=`0x701`、DLC2、`06 00`），再將 `0xAA55AA55` 寫入
   no-init RAM `0xFF700`，最後 software reset。ACK 不是 reset 的可靠送達保證。
3. boot 看見 marker 後立即清除，表示本次先進入更新模式，不是永久鎖住 boot。
   P13.7／INTP0 不參與 boot decision，也不要求 tool 或 analyzer 必須在線才能正常開 app。
4. app 無效：禁止跳 app；CAN ready 時留 boot 等完整更新，clock／CAN 初始化失敗則
   software reset 重試，不能藉此放行無效 app。
5. app 有效但要求進 boot，而 clock／CAN 初始化失敗：目前實作會返回有效 app，
   不會永久卡 boot；CAN ready／FSL ready 不是所有正常啟動都必須通過的額外 gate。
6. 真正交接前關中斷，寫 `0xFF714` handoff signature、將 `0xFF710` ISR owner
   設為 app（`0x55`），startup 再 branch app table。這些是 boot 的輸出，不是額外外部啟動要求。

```mermaid
flowchart TD
    RESET["Reset；初始化 clock/CAN<br/>檢查 entry、metadata、CRC"] --> VALID{"App 全部有效？"}
    VALID -->|否| RECOVERY{"CAN ready？"}
    RECOVERY -->|否| RETRY["禁止 app；software reset 重試"]
    RECOVERY -->|是| MUST["留 boot；不啟用 inactivity timer"]
    VALID -->|是| ENTER{"有一次性 ENTER marker？"}
    ENTER -->|否| JUMP["DI；handoff / owner=app<br/>startup branch 0x2000"]
    ENTER -->|是，清除 marker| CAN{"CAN ready？"}
    CAN -->|否| JUMP
    CAN -->|是| WAIT["留 boot；初始化 Flash driver<br/>啟用 30s inactivity"]
```

#### C. 30 秒 inactivity、START、失敗與更新成功

在 Tool 完成 Enter Boot 後，若停留在選檔或確認視窗而未開始更新，原有效 App 可能因 inactivity 到期而重新執行。
此時先 `Discover Target` 取得目前模式；若為 App，再 `Enter Boot`，確認 Boot Ready 後執行 `Start Device Update`。
操作圖集中於 [Device App 更新操作圖](https://released.github.io/slide_isp_tool_for_RL78/#device-update-example)。

| 事件 | boot 的實際結果 |
| --- | --- |
| 原 app 有效、ENTER 後尚未接受 START | 連續30秒沒有符合底層接收條件的 CAN request，關閉已初始化的 FSL 後返回原 app |
| 持續 INFO／HELLO／其他符合接收條件的 frame | 都會刷新 inactivity；不是上電後固定30秒，也不是只由 DATA 刷新；未知 command／錯誤 DLC 也可能刷新 |
| 原 app 無效 | 從一開始不啟用 inactivity timer，接受 START 後也不會自動啟用；失聯仍留 boot 等重試 |
| START 被拒絕（protocol／target／size／FSL not ready） | 沒有進入 started state；不能把這個拒絕當成 app 已被擦寫；原 app 有效且 timer 啟用時仍可 inactivity 返回 |
| START 已接受後 inactivity 到期 | 若本次 timer 原本啟用，回 session-timeout error、留 boot、關閉後續自動返回；不跳可能只有部分內容的 app |
| ABORT／erase-write error／END metadata 或 CRC error | error 返回主迴圈，關閉後續自動返回，留 boot 等新 session；ABORT 即使在 START 前也走這條留 boot 路徑 |
| END 長度／state 尚不完整 | 回錯誤但保留 session；不得先宣布成功或跳 app |
| END 收齊、metadata size 等於 START size、Flash metadata 與 CRC 正確 | ACK 成功，關閉 FSL，寫 `0xFF718` update-complete marker，再 software reset；下次 reset 重新通過 A 節與 ENTER 判斷才進 app |
| 擦寫中掉電 | 下次上電重新跑 A 節；若 image 仍有效且無 ENTER 則可啟動，否則留 boot；不是保證有雙映像回復 |

底層接收條件為standard／非RTR、ID700或720..727、DLC>0；通過即刷新timer，之後才
檢查 command。計時由1ms TMRJ0 IRQ 累加，Flash 操作關 IRQ 時不是嚴格的 wall-clock
30秒。timer 已停用或未啟用時，PC 失聯不能期待 target 自動 timeout／reset；tool 的
bounded wait／ABORT 不能取代供電、Flash、IRQ 與掉電的實板驗證。

```mermaid
flowchart TD
    WAIT["Boot 接收迴圈"] --> EVENT{"事件"}
    EVENT -->|"尚未 START；timer 到期"| OLD["僅原 app 有效且 timer 啟用<br/>返回未改寫的原 app"]
    EVENT -->|"原 app 無效／timer 停用"| STAY["留 boot；等待完整新 session"]
    EVENT -->|"START 已接受；timer 到期"| STAY
    EVENT -->|"ABORT／Flash／END metadata-CRC error"| STAY
    EVENT -->|"END 收齊且驗證通過"| RESET["ACK；Flash driver close；update marker<br/>software reset"]
    RESET --> CHECK["重新檢查所有 boot decision<br/>不是直接無條件跳 app"]
```
#### App 工程設定

固定向量介面與 ISR 登錄方式見 [Device IRQ 設定](https://released.github.io/slide_boot_loader_for_RL78/#device-app-irq)。
Metadata 與 App-only 建置命令見 [Device App 建置](https://released.github.io/slide_boot_loader_for_RL78/#device-app-build)。

<!-- F13_BOOT_DECISION_END -->

<!-- F24_DEVICE_BEGIN -->
<a id="f24-can-device"></a>

## F24 (MCU CAN device)：Boot／App 工程配置

F24 CAN device 使用獨立的 Transfer、Boot 與 App 工程。
板端為 RL78/F24 Target Board R7F124FPJ5xFB。
正常 CAN App 更新已完成實板驗證，操作與 F13 device 相同：載入配對 BIN、Discover、必要時 Enter Boot、更新並確認 App。
完成報告與 UART counter 見 [F24 device 更新結果](https://released.github.io/slide_isp_tool_for_RL78/#f24-device-update-example)。

### 板端與更新設定

| 項目 | 設定 |
| --- | --- |
| X1／CPU／CAN clock | 4 MHz／40 MHz／40 MHz，PLL80 |
| CAN backend | RS-CANFD，Classical CAN 500K |
| CAN pins | P10 TX、P11 RX、P12 STB LOW |
| 診斷 UART | P15 TX、P16 RX、115200 |
| Flash driver | RFD Type02，programming-mode 路徑在 RAM 執行 |
| Target／IRQ ABI | `0xF24B`／F2V1 |
| IRQ owner | `0xAA`：Boot；`0x55`：App |
| CAN IDs | Control `0x700`、response `0x701`、raw `0x720..0x727` |
| 更新格式 | App image format6、CAN protocol5、64-byte blocks |

### Flash 配置

| 絕對 address | 用途 |
| --- | --- |
| `0x00000..0x01FFF` | 8 KiB Boot，含實體 vector／option |
| `0x02000..0x020FF` | App 64 組4-byte跳轉表 |
| `0x02100..0x0217F` | 128-byte metadata core |
| `0x02180..0x021FF` | 128-byte metadata reserved FF |
| `0x02200..` | App startup／code／far constants |
| `app_start + image_size - 4` | App CRC32 尾碼 |
| `0x3FC00..0x3FFFF` | 最後1 KiB保留，含 debug monitor |

最大 App 容量為 `0x3DC00`（247 KiB），擦除單位1 KiB，寫入單位4 bytes。
建置檢查保留至少512 bytes Boot ROM 餘裕，預設關閉 Boot UART log。
完整欄位說明見 [Device metadata 位址表](https://released.github.io/slide_boot_loader_for_RL78/#flash-metadata-can-reference)。

### Boot 啟動與更新

Boot 檢查 metadata、跳轉表與全映像 CRC。
SW1（P137 LOW）或 ENTER marker 進入更新模式；有效 App 的 ENTER session 使用30秒 inactivity。
Flash 操作透過 RAM 中的 RFD 執行路徑更新 App 範圍。

```mermaid
flowchart TD
    RESET["MCU CAN device reset"] --> CHECK{"App 驗證有效且無更新要求？"}
    CHECK -->|是| APP["設定 App owner / handoff<br/>執行 App startup"]
    CHECK -->|否| WAIT["Boot 接收 CAN 更新"]
    WAIT --> META["完整 metadata 暫存 / SEAL"]
    META --> BLOCK["START 版本政策 / 收齊區塊 / CRC 檢查"]
    BLOCK --> FLASH["Flash driver 寫入 App"]
    FLASH --> END{"END 全映像驗證通過？"}
    END -->|是| RESET
    END -->|否| WAIT
```

### 工程與建置

三個工程放在同一父目錄。
Boot 的 `common` 提供 board／clock／CAN backend，Boot 內含 RFD 來源。
App 與 Transfer 各自保存 SC 與 MTPJ。

在 Boot 目錄使用 PowerShell：

```powershell
# Clean rebuild Transfer, Boot and App.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind all

# App-only clean rebuild.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind app

# Safe artifact and contract checks.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test.ps1
```

日常建置使用 Windows PowerShell、CS+／CC-RL。
CS+ hooks 依序執行產表與封裝；map、ROM／RAM、向量、metadata 與 CRC 由腳本核對。

C header 編輯、ISR 與 App-only 命令集中於 [Device App 設定與建置](https://released.github.io/slide_boot_loader_for_RL78/#device-app-build)。
初裝檔為 Boot `boot0000_1FFF.hex`＋App `flash_app_variable_CRC.hex`，或 App 根目錄 `boot_app.hex`。
CAN 更新使用 App `*_update.bin`。App 產表為 `ftable.inc`、`app_identity.h`、`app_irq_table.inc`，
由 `ftable_RL78_F24.asm` 組譯；兩份 C header 仍是編輯入口。

### 驗證項目

軟體檢查涵蓋編譯、向量／RETI、IRQ stack、RFD RAM 路徑及 metadata／區塊處理。
正常 500K CAN App 寫入、END CRC、reset 後 APP_READY／live INFO 與 UART timer counter 已確認。
CAN 波形量測、250K／1M、其他 IRQ、長時間壓力、取消、斷線及斷電復原分項驗證，
見 [更新驗證矩陣](https://released.github.io/slide_isp_tool_for_RL78/#update-confirmation)。
<!-- F24_DEVICE_END -->

<!-- DEVICE_WORKSHOP_BEGIN -->
<a id="device-metadata-vector-workshop"></a>

## Device 開發實作：編輯 Metadata、增加 IRQ、產生並驗證 App

本章整理 **F13 (MCU CAN device)** 與 **F24 (MCU CAN device)** 的 App 設定與建置流程。
兩者皆透過 CAN 更新 App，由 pre-build／post-build 將專案設定轉成映像。
兩份工程共同作為後續 MCU 的 [golden sample](https://github.com/released/simple_renesas_isp_tool/blob/main/docs/DEVICE_GOLDEN_SAMPLE_zh-TW.md)。
編輯與建置使用 C header、Windows PowerShell／.NET 與 CS+；不需要 Python。

### A. 專案配置與共用介面

| 項目 | F13 (MCU CAN device) | F24 (MCU CAN device) |
| --- | --- | --- |
| Boot／App | `RL78_F13_Boot_loader_CAN`／`RL78_F13_Boot_loader_CAN_app` | `RL78_F24_Boot_loader_CAN`／`RL78_F24_Boot_loader_CAN_app` |
| MCU／Flash driver | R5F10BMG／FSL | R7F124FPJ5xFB／RFD，忙碌期間必要程式在 RAM |
| Target／IRQ ABI | `0xF13B`／F1V1 | `0xF24B`／F2V1 |
| Boot／App 起點 | 8 KiB／`0x2000` | 8 KiB／`0x2000` |
| App capacity | `0x1DC00`，119 KiB；最後 1 KiB 保護 | `0x3DC00`，247 KiB；最後 1 KiB 保護 |
| 更新契約 | App image format 6、CAN protocol 5、Classical 500K | 同樣格式／協定，但身分與 geometry 不同 |
| 版本／build 編輯來源 | App `app_image_config.h` | App `app_image_config.h` |
| IRQ 編輯來源 | 各 App 的 `app_irq_handlers.h`＋已註冊 ISR C 檔 | 同左 |

App 與 matching Boot 以原名稱放在同一父目錄；保留相鄰 Boot 提供的腳本／共用來源。
F13 可由 [Boot](https://github.com/released/RL78_F13_Boot_loader_CAN)／[App](https://github.com/released/RL78_F13_Boot_loader_CAN_app) 取得。
F24 device 的板端設定與建置方式見 [F24 CAN device 工程配置](https://released.github.io/slide_boot_loader_for_RL78/#f24-can-device)。
獨立 Transfer 專案是通訊測試整機映像，不是可載入的 App 更新 BIN。

#### A1. 設定檔與產物分工

| 檔案 | 內容 | 編輯方式 |
| --- | --- | --- |
| `app_image_config.h` | App 版本、build 與映像身分核對值 | 使用者設定 |
| Boot `image_metadata_config.h` | 格式、MCU／Flash、IRQ ABI、更新政策與 Boot 版本 | 共用映像契約；變動時核對 Boot／App、linker、封裝及 Tool |
| Boot `can_boot_config.h` | CAN ID、速率宣告、命令與接收規則 | CAN 通訊設定；搭配實際 clock／timing 修改 |
| Boot `boot_app_handoff.h` | 共用 RAM、IRQ owner 與一次性交接標記 | 啟動交接契約；與 linker／startup／向量產生器對應 |
| `image_metadata.c/.h` | 執行時欄位解碼與完整 metadata 驗證 | 共用 C90 模組；Boot／App 分別編譯引用 |
| `image_metadata_profile.c` | 工程接受的 32-word metadata core | 結合映像契約與 ISP 設定；不操作 driver register |
| `app_irq_handlers.h` | 實體 vector → ISR 函式名稱 | 使用者設定，搭配 App 的 ISR C 檔 |
| `.inc`、identity header、向量表 | 編譯與封裝所需資料 | 產生器輸出；檔名見 [建置產物](#device-app-build) |
| `DefaultBuild/app_build_report.html` | 實際 BIN 的 metadata、位址、CRC、向量表 | post-build 輸出；以瀏覽器開啟，見 [編譯摘要](#device-app-build-report) |

兩個 device 使用相同的 C header 欄位，產生器依各自的 Boot 契約輸出對應檔案。

Metadata 的共用宣告採 `IMAGE_*` 名稱，放在獨立 header；不引用 CAN driver。
CAN 參數仍會被記錄到 BIN，產生器及驗證端在組合欄位時讀取 `can_boot_config.h`，
因此不需要在 metadata header 再維護一份 CAN ID／速率。

日常 App 發行編輯 `app_image_config.h`；改 MCU／分區／格式時核對 `image_metadata_config.h`；
改 CAN 通訊參數時核對 `can_boot_config.h` 與驅動。
CS+ 專案樹已列入這些設定 header。F13 App 的同名 metadata header 只引用相鄰 Boot 契約，
不另存一份可獨立修改的共用數值。

<a id="device-app-json"></a>
<a id="device-app-config"></a>

### B. Metadata 設定與產生來源

| 分類／欄位 | 編輯或產生位置 | 只更新 App？ |
| --- | --- | --- |
| App version／build | 兩者都編輯 `app_image_config.h` 的 `APP_IMAGE_VERSION`／`APP_IMAGE_BUILD` | 是，仍須符合既有契約 |
| 版本管制 | `APP_IMAGE_VERSION_CONTROL`；`0U` 預設允許任意版本，`1U` 僅允許同版／新版 | 是；成功更新後採用映像設定 |
| image_size／CRC 地址／CRC32 | 由 linker map 與 post-build 封裝決定 | 自動產生，不填預估大小、不用 hex editor 改 |
| Target、MCU part／family、Flash geometry、CAN IDs／rate | Boot 契約、App producer、linker／backend、封裝與 live INFO 必須一致 | Boot／App 共同契約 |
| Role／transport／IRQ ABI／minimum Boot | matching Boot config／producer 產生；Boot／Tool 均驗證 | 由 Boot／Tool 核對 |
| Metadata reserved `0x80..0xFF` | Producer 固定填 `FF` | 新增欄位時同步 producer 與 validator |
| `APP_IMAGE_TARGET_ID`／`APP_IMAGE_ROLE`／`APP_IMAGE_UPDATE_TRANSPORTS` | App 與 Boot 的契約核對值 | Target：F13 `0xF13B`、F24 `0xF24B`；role `1U`＝DEVICE_APP、transport `0x01U`＝CAN |

Packed version 採 `(major << 16) | (minor << 8) | patch`；每部分一個 byte。
以下版本／日期用於展示設定差異。
build 使用十進位整數。
App 版本、Boot 版本與 minimum Boot 為不同欄位。

| Define | 功能與用途 | 範例／其他值的處理 |
| --- | --- | --- |
| `APP_IMAGE_VERSION` | App 自己的 major／minor／patch；作版本比較 | `0x00020103UL`＝2.1.3；不要求等於 Boot 版本 |
| `APP_IMAGE_BUILD` | App 建置識別；不參與版本排序 | `20261018UL`；與 Boot build 不必一致；相同版本換 build 仍視為同版 |
| `APP_IMAGE_TARGET_ID` | 與 paired Boot 核對映像身分，不是 MCU 選擇器 | F13 `0xF13BU`／F24 `0xF24BU`；只改成 `0xF33BU` 會在 pre-build 被拒絕 |
| `APP_IMAGE_ROLE` | 更新目的地角色 | 協定 `1U`＝DEVICE_APP、`2U`＝HOST_BRIDGE_APP；本工程要求 `1U`，改 `2U` 或未定義的 `5U` 都拒絕產生 |
| `APP_IMAGE_UPDATE_TRANSPORTS` | 允許的更新介面 bitmask，不是 App 執行時使用的周邊 | 協定 `0x01U`＝CAN、`0x02U`＝I2C、`0x04U`＝UART，`0x03U`＝CAN＋I2C；本 CAN 工程僅接受 `0x01U`，其他值不會啟用另一種更新流程 |
| `APP_IMAGE_VERSION_CONTROL` | 已安裝有效 App 的版本政策 | `0U`＝任意版本、`1U`＝同版／新版；其他值拒絕產生；維護操作見 [force 降版](https://released.github.io/slide_isp_tool_for_RL78/#force-old-version) |

Boot 自身的版本／build 位於 `image_metadata_config.h` 的 `IMAGE_BOOT_VERSION`／`IMAGE_BOOT_BUILD`。
App producer 將該 Boot 版本寫成 metadata 的 minimum Boot；板上 Boot 版本須不低於此值。
例如 Boot 1.7.0 與 App 2.1.3 可以搭配；App 版本與 Boot 版本不做相等比較。
只更新相容的 App 時，保留 Boot 設定即可。

#### B1. F13：編輯 app_image_config.h

修改前：

```c
#ifndef APP_IMAGE_CONFIG_H
#define APP_IMAGE_CONFIG_H

#define APP_IMAGE_VERSION           (0x00010500UL)
#define APP_IMAGE_BUILD             (20261015UL)
#define APP_IMAGE_TARGET_ID         (0xF13BU)
#define APP_IMAGE_ROLE              (1U)    /* DEVICE_APP */
#define APP_IMAGE_UPDATE_TRANSPORTS (0x01U) /* CAN */
#define APP_IMAGE_VERSION_CONTROL   (0U)    /* 0=any; 1=same/newer */

#endif
```

修改後（僅示範 App 資訊變更）：

```c
#ifndef APP_IMAGE_CONFIG_H
#define APP_IMAGE_CONFIG_H

#define APP_IMAGE_VERSION           (0x00010501UL)
#define APP_IMAGE_BUILD             (20261016UL)
#define APP_IMAGE_TARGET_ID         (0xF13BU)
#define APP_IMAGE_ROLE              (1U)    /* DEVICE_APP */
#define APP_IMAGE_UPDATE_TRANSPORTS (0x01U) /* CAN */
#define APP_IMAGE_VERSION_CONTROL   (0U)    /* 0=any; 1=same/newer */

#endif
```

App pre-build 讀 App C header、Boot 的 `image_metadata_config.h` 及 CAN 設定，產生 `ftable.inc`／`app_identity.h`；
`ftable_RL78_F13.asm` 依生成常數排列 App metadata，讓 App INFO 與 BIN 使用同一版本／build。
`IMAGE_SIZE_POST_BUILD = 0xFFFFFFFF` 是封裝前的長度預留值，post-build 會填入實際大小。

#### B2. F24 device：編輯 app_image_config.h

修改前：

```c
#ifndef APP_IMAGE_CONFIG_H
#define APP_IMAGE_CONFIG_H

#define APP_IMAGE_VERSION           (0x00010000UL)
#define APP_IMAGE_BUILD             (20261015UL)
#define APP_IMAGE_TARGET_ID         (0xF24BU)
#define APP_IMAGE_ROLE              (1U)    /* DEVICE_APP */
#define APP_IMAGE_UPDATE_TRANSPORTS (0x01U) /* CAN */
#define APP_IMAGE_VERSION_CONTROL   (0U)    /* 0=any; 1=same/newer */

#endif
```

修改後（保留契約欄位）：

```c
#ifndef APP_IMAGE_CONFIG_H
#define APP_IMAGE_CONFIG_H

#define APP_IMAGE_VERSION           (0x00010001UL)
#define APP_IMAGE_BUILD             (20261016UL)
#define APP_IMAGE_TARGET_ID         (0xF24BU)
#define APP_IMAGE_ROLE              (1U)    /* DEVICE_APP */
#define APP_IMAGE_UPDATE_TRANSPORTS (0x01U) /* CAN */
#define APP_IMAGE_VERSION_CONTROL   (0U)    /* 0=any; 1=same/newer */

#endif
```

`prepare_projects.ps1` 核對 C header，產生 `app_identity.h`、`ftable.inc`
與其組語 wrapper；linker 將該 256-byte metadata 放到 `0x2100`。
`package_images.ps1` 比對已編譯 metadata 與同一 C header／Boot contract，再填實際長度與尾端 CRC。
geometry、IRQ ABI、CAN routing 等欄位由 Boot 契約提供。
更新目的地與介面的核對規則見 [更新政策](https://released.github.io/slide_isp_tool_for_RL78/#image-update-policy)。

`app_image_config.h` 使用上述六個 `APP_IMAGE_*` define 與固定 include guard。
數值採 C 的十六進位或十進位整數，可加 `U`／`UL` 及一層括號；version 為 `0x00000000..0x00FFFFFF`，build 為 `0..4294967294`。
設定以 literal 表示，不使用條件編譯、其他 include 或運算式；C90 `/* ... */` 註解可保留。
產生器會拒絕缺少／重複／未知 define、契約不符或非整數設定。

工程內的 header 在每個欄位旁標示用途、編碼與修改條件。
version／build 是 App 身分設定；target／role／transport 是與 Boot 核對的契約值。
完整 Flash／CAN／IRQ ABI 資料由 Boot 契約產生，不需要在 App header 重複填寫。

#### B3. 用 address 與 byte 核對結果

兩個 device 的 App 起點相同，以下 address 相同；**欄位值與 image capacity 仍不同**。
完整欄位見 [Flash／Metadata byte 對照](https://released.github.io/slide_boot_loader_for_RL78/#flash-metadata-can-reference)；
兩個工程的欄位值由各自的 App 設定及 Boot 契約產生。

| 欄位 | Metadata offset | BIN offset | 絕對 Flash address | 本例預期 |
| --- | --- | --- | --- | --- |
| App version | `0x10..0x13` | `0x110..0x113` | `0x2110..0x2113` | F13：`01 05 01 00`；F24：`01 00 01 00` |
| App build | `0x14..0x17` | `0x114..0x117` | `0x2114..0x2117` | 20261016，LE32 |
| Actual image size | `0x18..0x1B` | `0x118..0x11B` | `0x2118..0x211B` | 必須等於 BIN 檔案長度，不是 capacity |
| Policy／IRQ ABI | `0x60..0x6F` | `0x160..0x16F` | `0x2160..0x216F` | DEVICE_APP、允許 CAN、各自 ABI 與 minimum Boot |
| Version control | `0x74..0x77` | `0x174..0x177` | `0x2174..0x2177` | `0U`／`1U`，LE32；Boot 在一般 START 比較已安裝版本 |
| Reserved FF | `0x80..0xFF` | `0x180..0x1FF` | `0x2180..0x21FF` | 128 bytes 全 `FF` |
| Tail CRC32 | 不在 metadata 裡 | `actual size - 4` | `0x2000 + actual size - 4` | 前面全部 BIN bytes 的 CRC32，LE32 |

#### B4. Metadata 產生路徑

```mermaid
flowchart TD
    CONFIG["MCU CAN device App<br/>app_image_config.h"] --> PRE["App pre-build<br/>metadata INC／identity header"]
    IMAGE["image_metadata_config.h<br/>映像格式與工程配置"] --> PRE
    CANCFG["can_boot_config.h<br/>CAN 通訊參數"] --> PRE
    PRE --> LINK["Linker map：實際 code / data 範圍"]
    LINK --> PACK["各自 post-build<br/>產生或填入 metadata、actual size、tail CRC"]
    PACK --> BIN["封裝 update.bin<br/>不是 raw MOT / ABS"]
```

<a id="device-metadata-parser"></a>

#### B5. Metadata C 模組與移植入口

兩個 device 的 Boot／App 分別編譯 `image_metadata.c`，介面由 `image_metadata.h` 宣告。
模組不包含 CAN driver、Flash 擦寫或 reset 操作。
App 的 INFO 欄位讀取與 Boot 的 metadata 驗證使用同一組介面。
`image_metadata_profile.c` 定義工程的 `g_image_metadata_contract[32]`，
由映像契約及 ISP 設定組合預期 core；CAN 分包暫存、順序／重送與 SEAL 留在 adapter。

| API | 輸入與結果 | 驗證範圍 |
| --- | --- | --- |
| `ImageMetadataRead32(data, length, offset, &value)` | data 指向 metadata byte0；可用長度至少 256 bytes，offset 為 0..252；成功回傳 1，失敗回傳 0 並清除輸出值 | 讀取任意 LE32 window，支援未對齊 byte buffer；不代表身分或 CRC 已通過 |
| `ImageMetadataValidate(words)` | 完整 64 個對齊的 native 32-bit words；成功為 `IMAGE_METADATA_OK` | 128-byte core、128-byte reserved FF、大小、版本編碼、build、版控值、minimum Boot、分區、身分、ISP 參數與 IRQ ABI |

C90 模組要求 `unsigned long` 為 32 bits，header 會檢查寬度。
直接映射 Flash 為 word pointer 適用於對齊的 little-endian CPU。
Byte-oriented 或 big-endian backend 先用 `ImageMetadataRead32` 將 64 words 解碼至對齊的 native word array，再執行完整 metadata 驗證。
長度、來源範圍及對齊由呼叫端確認；範例的 Flash metadata 與 RAM staging buffer 已依此配置。

完整 metadata 驗證不包含全映像 CRC，也不取代 START 的已安裝 App 版控判斷。
「欄位可讀」「映像契約相符」與「完整映像可啟動」分別核對。

```mermaid
flowchart TD
    RX["ISP adapter<br/>收齊 256-byte metadata"] --> CHECK["ImageMetadataValidate"]
    PROFILE["工程 config／profile"] --> CHECK
    CHECK --> OK{"Metadata 契約相符？"}
    OK -->|否| STOP["回報錯誤；拒絕更新"]
    OK -->|是| NEXT["Boot 續行 CRC／更新狀態機<br/>與完整啟動檢查"]
    APP["App 讀取欄位"] --> READ["ImageMetadataRead32<br/>解碼不代表映像有效"]
```

`IMAGE_METADATA_DETAILED_STATUS` 是編譯時診斷選項，不寫入 BIN metadata。
`1U` 回報 field／policy／IRQ ABI／layout 等原因；`0U` 統一回報 BAD_IMAGE。
兩種設定執行相同的接受／拒絕條件，並由工程的 ROM 餘裕檢查核對容量。

#### 模組移植步驟

1. 保留 `image_metadata.c/.h`，依實際 MCU／分區修改 `image_metadata_config.h`。
2. 在 `image_metadata_profile.c` 組合工程接受的身分、格式與 ISP 參數。
   換介面時對應其設定與 adapter；共用解析模組不處理通訊命令或 register。
3. 在 Boot／App 的 CS+ 專案樹註冊 C 來源與 header；C 來源各編譯一次，不以 include 合併 C 檔。
   範例已完成註冊，App 引用相鄰 Boot 的本機來源。
4. Boot 在 metadata staging、已安裝映像判斷與 END 使用共用驗證；
   CRC、向量檢查及 Flash 保護維持在 Boot 流程。
   App 讀欄位時呼叫 `ImageMetadataRead32`，不另行複製 byte shift 或直接套用未對齊 struct。
5. Clean rebuild 後核對 Boot map／餘裕、App metadata／CRC／向量及 HTML 編譯摘要。
   檢查正常映像、錯誤身分／分區／IRQ、保留 bytes、短資料與更新中斷等情況。

共用原稿位於 Tool repository 的 `firmware/common/device_metadata`。
兩份 Boot repository 各自攜帶相同 C／header，日常 MCU 建置不依賴 Tool checkout。
維護共用模組時，在 Tool repository 使用
`scripts/sync_device_metadata.ps1 -F13Boot <Boot checkout> -F24Boot <Boot checkout>` 同步，
加上 `-CheckOnly` 可唯讀核對；各工程 config／profile 不由此腳本覆寫。

<a id="device-app-irq"></a>

### C. App Vector Table：新增 IRQ 範例

本例使用兩個 device header 都定義的 `INTP1 = 0x0A`。
其他 IRQ 的 vector 位址依各 MCU 的 device header 決定。
Vector 位址是**實體 vector byte address**，不是 IRQ 序號、App slot 或周邊 pin。
本例對應 App slot `0x2014`，即 BIN offset `0x14`；換算方式見 [槽位位址](#device-irq-slot)。

<a id="device-irq-ownership"></a>

#### C0. Boot／App 中斷所有權與向量轉送

本節的 RL78 工程由固定 Boot 持有實體 vector，再由軟體 dispatcher 轉送到 App。
App 不寫入實體 vector，而是在固定位置提供跳轉表；表內的 `BR` 指向該 App 的實際 ISR。

Boot 與 App 是分開編譯、連結的映像。兩份映像可以使用相同 C ISR 名稱，
也可以各自命名；函式名稱不決定硬體 vector 的所有權。
同一個映像內，每個函式只能有一份定義，每個已使用 vector 對應一個 handler。

| 項目 | Boot | App |
| --- | --- | --- |
| 實體 vector | 固定完整普通向量轉送介面，管理 `.VECTOR` | 使用 `app_irq_handlers.h` 產生的 App BR table，不宣告實體 `vect=` |
| IRQ owner | `0xAA`：執行 Boot handler；未配置來源走 default RETI | `0x55`：由 Boot 轉送至 App slot，再進入該 App ISR |
| ISR 名稱 | 在 Boot 映像內解析為 Boot 程式位址 | 在 App 映像內解析為 App 程式位址；可與 Boot 同名 |
| 中斷啟用 | Boot 初始化及啟用自己需要的來源 | 交接後由 App 初始化、清 pending flag、設定 priority／mask，再啟用 |

Classical CAN 範例的兩份 Boot 都使用 1 ms timer，CAN 收發與診斷 UART 採 polling。
CAN FD 的接收中斷配置見 [接收與中斷](https://released.github.io/slide_boot_loader_for_RL78/#can-fd-device-rx)。

| Device | 實體 vector／來源 | Boot ISR | App ISR |
| --- | --- | --- | --- |
| F13 | `0x1E`／INTTRJ0 | `f13_boot_timer_isr` | `r_tmr_rj0_interrupt` |
| F24 | `0x2E`／INTTM01 | `Device_TimerIsr` | `Device_TimerIsr`，兩個專案各自編譯 |

App handler 使用 global、非 static、無 `vect=` 的 interrupt pragma，並由編譯器產生 RETI。
新增一般 IRQ 時，修改 App ISR、MTPJ 來源登錄及 `app_irq_handlers.h`，重新產表並建置 App；
App 同時完成周邊初始化、priority／mask 設定與中斷旗標處理。
在 MCU、分區與 IRQ ABI 不變時，App 使用不同 IRQ 或與 Boot 同名的 ISR，不需修改或重燒 Boot。
新增來源的操作接續 [C1](#device-app-irq-source)；實體地址來源與產表結果見下方 C2～C4。

```mermaid
flowchart TD
    IRQ["MCU CAN device / CPU 接受一般 IRQ"] --> VECTOR["Boot 實體 vector"]
    VECTOR --> DISPATCH["Boot 固定 stub / dispatcher"]
    DISPATCH --> OWNER{"IRQ owner"}
    OWNER -->|"AA"| BOOT["Boot handler／default RETI"]
    OWNER -->|"55"| SLOT["App 固定跳轉槽位 / BR"]
    SLOT --> APP["App ISR → RETI"]
    BOOT --> RETURN["回到被中斷的執行點"]
    APP --> RETURN
```

一般 IRQ 的轉送槽位涵蓋 `0x04..0x7C`，未使用來源保持 mask。
Reset 由 Boot startup 接手，再經驗證及交接進入 App startup。
保留的 `0x02` 與實體 BRK `0x7E` 不走一般 IRQ 轉送；App table 的 BRK 保留槽使用 RETB，與一般 ISR 的 RETI 區分。

<a id="device-irq-slot"></a>

##### 槽位位址與實際 ISR

RL78 的實體 vector 每項為 16-bit 入口位址，直接目的地位於低 64 KiB。
本架構將入口指向 Boot stub，再以 App table 的 far `BR` 連到實際 ISR，將硬體入口與 ISR 位置解耦。
硬體入口的位址寬度與跳轉表用途可對照 [Renesas RL78 ISR 說明](https://www.renesas.com/en/document/apn/rl78-dual-image-bootloader-example)。

實體 vector 每格 2 bytes，App table 為 64 格、每格 4-byte `BR`，共 256 bytes。
以實體 vector 的 byte address 換算：

```text
App slot = App start + (physical vector byte address / 2) * 4
         = App start + physical vector byte address * 2

0x2000 + (0x002E / 2) * 4 = 0x205C
```

以下是 F24 device timer 的具體例子；共通 IRQ 路徑使用上方流程。

| 步驟 | 位址／動作 | 對應位置 |
| --- | --- | --- |
| CPU 讀取實體 vector | `0x002E`，進入 Boot 固定 stub／dispatcher | App `iodefine.h` 的 `INTTM01`；Boot `f24_boot_vectors.asm` |
| owner 選擇 App | `0x55`，轉送至 App slot `0x205C` | Boot dispatcher；槽位為 BIN offset `0x5C` |
| 跳轉至 ISR | 該 slot 的 `BR !!_Device_TimerIsr` | App `app_irq_table.inc`；由 `X(0x2E, Device_TimerIsr)` 產生 |
| ISR 返回 | `Device_TimerIsr` 執行後以 RETI 返回 | App 的 `common/device_board.c` |

`0x205C` 是跳轉槽位，不是 ISR 本體的固定程式位址。
產生器與 linker 依 App 的 mapping 及實際連結結果填入 `BR` 目的地，無需手動指定 ISR 位址。

<a id="device-irq-dispatch-cost"></a>

##### 轉送延遲、CPU 負載與 stack

RL78 每次**實際接受、並進入這套一般 IRQ 入口**時，都會執行 stub／dispatcher。
這項成本會出現在 timer、外部中斷或 CAN RX 等已啟用的來源，不只發生在 Boot→App 交接。
未啟用的 IRQ 不執行 dispatcher；同一來源的多個事件若合併為一次 pending，也不是逐事件各執行一次。
相較實體 vector 直達相同 ISR，額外工作包含 CALL、PUSH／POP、owner／slot 計算及 App BR。

時間以 **CPU clock** 換算，不是 CAN bitrate 或 UART baud rate。
32 MHz 的一個 clock 為31.25 ns，40 MHz 為25 ns；一條指令可能需要多個 clocks。
完整轉送路徑累計後，本工程的 RL78 額外延遲約為 **1 µs 等級**。

以下是來源組語與原廠指令表的**名義時脈估算，尚非實板量測或最差延遲保證**。
條件為 RL78-S3、指令在 Code Flash 執行、stack／owner 在 RAM，採用
[RL78 Software Manual](https://www.renesas.com/en/document/mah/rl78-family-users-manual-software-rev230)
§5.5.3 Table5-7 的對應 clocks；ROM 資料讀取使用該表的 Code Flash 欄。
來源為各 Boot 的 `f13_boot_vectors.asm`／`f24_boot_vectors.asm` 與 App 的 `app_irq_table.inc`。

owner=`0x55` 的 App 路徑在三個 RL78 工程相同，執行22條指令：

| 階段 | 計算內容 | CPU clocks |
| --- | --- | --- |
| Boot stub | `CALL !dispatcher` | 3 |
| 暫存器保存 | 三次 PUSH，加上 `MOV A,ES` | 4 |
| 讀取 vector、換算 slot | 設定 ES、讀取 return address、讀取 ROM literal、換算 App slot | 12 |
| owner 分流 | RAM owner 的 CMP，加上成立的 BZ | 5 |
| 還原並進入 slot | 寫回 return address、POP／還原 ES、RET | 11 |
| App slot | `BR !!App_ISR` | 3 |
| 合計 | `3 + 4 + 12 + 5 + 11 + 3` | **38** |

其中 `MOV A,ES:[HL]` 讀取 Code Flash 中的 vector literal，計為5 clocks；
成立的 BZ 為4 clocks。`.DB` 是供讀取的資料，不是執行指令。
以上不包含 CPU 原本的硬體 IRQ 進入、編譯器 ISR 前言／結尾、ISR 本體及最後的 RETI。
App ISR 直接以 RETI 回到被中斷的位置，不會再回 Boot dispatcher 執行第二次轉送。

```text
Extra dispatch time (us) = dispatch CPU clocks / CPU frequency (MHz)
```

| Device／執行狀態 | 採用的路徑 | 名義 clocks | 額外轉送時間估算 |
| --- | --- | --- | --- |
| F13，CPU32 MHz | App owner | 38 | 1.1875 µs（1187.5 ns） |
| F24 Classical／FD，CPU40 MHz | App owner | 38 | 0.950 µs（950 ns） |
| F13，CPU32 MHz | Boot owner，timer | 43 | 1.34375 µs |
| F24 Classical／FD，CPU40 MHz | Boot owner，timer | 40 | 1.000 µs |
| F24 FD，CPU40 MHz | Boot owner，CAN RX | 45 | 1.125 µs |

這些路徑由 owner 與來源決定，不是逐一搜尋全部 IRQ。
單純增加 App IRQ mapping 數量、App BIN 長度或 metadata 內容，不會讓每次轉送多跑一輪 table 搜尋。
更改 dispatcher、MCU、時脈、記憶體配置或等待條件時，重新依組譯結果與量測核對。

**範例：F24 App 的 `Device_TimerIsr`。**
timer 的實體 vector `0x2E` 經 App slot `0x205C` 進入 ISR，路徑見 [槽位例子](#device-irq-slot)。
目前1 ms tick 為每秒1000次 IRQ，僅轉送部分約使用每秒0.95 ms CPU，即0.095%。
若同一類 IRQ 改成較高頻率，估算如下；這些頻率是負載試算，不代表已設定或測過。

| 實際 IRQ 進入頻率 | 平均間隔 | 每秒額外轉送時間 | 僅 dispatch 的 CPU 比例 |
| --- | --- | --- | --- |
| 1000次／秒 | 1 ms | 0.95 ms | 0.095% |
| 10000次／秒 | 100 µs | 9.5 ms | 0.95% |
| 100000次／秒 | 10 µs | 95 ms | 9.5% |

CPU 比例為 `IRQ entries/second × extra dispatch seconds × 100%`。
例如 ISR 的前言／本體／結尾（含 RETI）合計另需2 µs，1 ms tick 的合計軟體時間約為2.95 µs；
硬體 IRQ 接受時間與其他阻塞仍另外計算。
CAN FIFO 一次 IRQ 可處理多幀，估算時採用實際 IRQ 次數，不直接以 CAN frame 數代入。

**反應延遲與量測。**
外部事件到 App ISR 動作的時間，包含 IRQ mask／高優先來源等待、當前指令完成、硬體 IRQ 接受、dispatcher、
編譯器保存與 ISR 在該動作之前的指令。
dispatcher 期間沒有開啟 IE，因此這段時間也納入中斷可接受時機的預算。
固定路徑的名義成本與系統阻塞造成的 jitter 分別記錄。

可在獨立量測工程使用同一個外部週期訊號，於 ISR 第一個可觀察位置切換 GPIO，
比較「實體 vector 直達相同 ISR」與「Boot dispatcher→App slot→相同 ISR」兩組波形。
兩組使用相同 CPU clock、priority、GPIO 動作及負載，記錄多次樣本的最小／最大值。
事件到 GPIO 是整體反應延遲；兩組差值近似額外轉送成本，另核對 GPIO、前言與取指配置的差異。
只量 ISR 內 GPIO pulse 的寬度，涵蓋的是 pulse 之間的程式，不包含進入 ISR 前的 dispatcher。

**Stack。**
轉送階段額外暫用10 bytes：CALL return address 4 bytes，加三次 PUSH 共6 bytes。
這10 bytes 在進入 App ISR 前已釋放；硬體 IRQ frame、ISR 自身保存／區域變數與巢狀 IRQ 另計，
整體 stack 依各執行階段的最大使用量核對。

##### 移植範圍

此轉送架構不依賴硬體 boot swap，可作為其他 RL78 工程的移植基準。
共用的是設計與產表流程；各 MCU 的向量、Flash、startup 與 RAM 配置仍需建立對應的 Boot／App。
跨 MCU 與 Flash 擦寫期間的中斷條件集中於 [移植核對表](https://released.github.io/slide_boot_loader_for_RL78/#device-irq-porting)。

<a id="device-app-irq-source"></a>

#### C1. 加入一般 ISR，並在 App MTPJ 註冊來源

在自己的 App 新增 `app_extra_irq.c`，透過 CS+ 將它加入該 App 的編譯來源。
以下函式只清旗標並記錄事件；**不會初始化或啟用 INTP1**。

```c
#include "r_cg_macrodriver.h"

volatile unsigned char g_app_aux_irq_count;

#pragma interrupt app_aux_irq
void __near app_aux_irq(void)
{
    /* Clear the source flag and capture bounded state only. */
    PIF1 = 0U;
    g_app_aux_irq_count++;
}
```

ISR 宣告與返回規則沿用 [中斷所有權](#device-irq-ownership)。
啟用中斷之前，另依實際板子完成 pin／edge／priority／pending flag／mask 初始化；
範例未提供可直接接線使用的 INTP1 pin 設定。未用 IRQ 應保持 mask。
SC／Code Generator 重產後，核對 ISR pragma 並移除 App 的 `vect=`，保留 Boot 的實體向量所有權。

#### C2. F13 mapping：保留原有項目，新增 0x0A

Vector 位址的來源是此 App 的 [iodefine.h](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/iodefine.h) 中的中斷定義。
硬體規格可對照 RL78/F13 硬體手冊「Interrupt functions」章節的中斷來源／向量表。

| Vector 位址 | header 定義 | ISR 名稱 | 函式來源 |
| --- | --- | --- | --- |
| `0x08` | `INTP0 = 0x0008` | `r_intc0_interrupt` | [r_cg_intc_user.c](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/src/code_gen/r_cg_intc_user.c) |
| `0x0A` | `INTP1 = 0x000A` | `app_aux_irq` | 本章 C1 的 `app_extra_irq.c` |
| `0x16` | `INTST0 = 0x0016` | `r_uart0_interrupt_send` | [r_cg_serial_user.c](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/src/code_gen/r_cg_serial_user.c) |
| `0x18` | `INTSR0 = 0x0018` | `r_uart0_interrupt_receive` | 同一份 `r_cg_serial_user.c` |
| `0x1E` | `INTTRJ0 = 0x001E` | `r_tmr_rj0_interrupt` | [r_cg_timer_user.c](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/src/code_gen/r_cg_timer_user.c) |

查找時可先在 header 搜尋周邊中斷名稱，再於 ISR C 檔確認 `#pragma interrupt` 與函式定義。
同一向量可能列有 CSI／IIC／UART 別名，實際來源由本專案啟用的周邊模式決定。
`APP_IRQ_HANDLERS(X)` 的每一筆採 `X(vector, handler)`：第一個參數為實體向量位址，第二個為 App 的 C ISR 名稱。
清單使用 C 巨集續行，除最後一筆外，每行尾端保留 `\`；無使用項目時可保留空的巨集定義。

修改前：

```c
#ifndef APP_IRQ_HANDLERS_H
#define APP_IRQ_HANDLERS_H

#define APP_IRQ_HANDLERS(X) \
    X(0x08, r_intc0_interrupt) \
    X(0x16, r_uart0_interrupt_send) \
    X(0x18, r_uart0_interrupt_receive) \
    X(0x1E, r_tmr_rj0_interrupt)

#endif
```

修改後：

```c
#ifndef APP_IRQ_HANDLERS_H
#define APP_IRQ_HANDLERS_H

#define APP_IRQ_HANDLERS(X) \
    X(0x08, r_intc0_interrupt) \
    X(0x0A, app_aux_irq) \
    X(0x16, r_uart0_interrupt_send) \
    X(0x18, r_uart0_interrupt_receive) \
    X(0x1E, r_tmr_rj0_interrupt)

#endif
```

#### C3. F24 device mapping：保留自己的 timer

F24 App 的 `iodefine.h` 定義 `INTTM01 = 0x002E`。
本工程的 timer ISR 為 `common/device_board.c` 中的 `Device_TimerIsr`，因此使用 `X(0x2E, Device_TimerIsr)`。
`0x0A` 對應此 App header 中的 `INTP1 = 0x000A`，搭配 C1 的 `app_aux_irq` 範例。

修改前：

```c
#ifndef APP_IRQ_HANDLERS_H
#define APP_IRQ_HANDLERS_H

#define APP_IRQ_HANDLERS(X) \
    X(0x2E, Device_TimerIsr)

#endif
```

修改後：

```c
#ifndef APP_IRQ_HANDLERS_H
#define APP_IRQ_HANDLERS_H

#define APP_IRQ_HANDLERS(X) \
    X(0x0A, app_aux_irq) \
    X(0x2E, Device_TimerIsr)

#endif
```

各 App 的 C header 保存該專案使用的 IRQ 清單，新增項目時保留既有 mapping。
函式改名會同步反映於 C pragma、函式定義與 C header。
移除 mapping 時，對應周邊的 IRQ 也一併停用。

#### C4. 產生結果與核對欄位

| 檢查位置 | 修改前 | 修改後 |
| --- | --- | --- |
| F13 `app_irq_table.inc` 的 vector `0x0A` | `BR !!f13_app_default_isr` | `BR !!_app_aux_irq`，slot `0x2014` |
| F24 device `app_irq_table.inc` 的 vector `0x0A` | `BR !!device_default_isr` | `BR !!_app_aux_irq`；table start `0x2000` |
| App map | 沒有新 ISR symbol | `_app_aux_irq` 有有效 code address；應為 interrupt ISR |
| 最終 BIN 的 offset `0x14..0x17` | 指向原 default ISR | `EC`＋新 ISR 的 3-byte little-endian 絕對 address |
| Boot 的實體 vector／來源 | 固定轉送介面 | 不因 App 函式名或使用清單改變 |

Assembler symbol 前綴 `_` 由 generator 加入，C header 使用 C 函式原名 `app_aux_irq`。
表有固定 64 個 4-byte slot，不是每增加一個 IRQ 就把後面的 entry 往後推。
App reset slot 進 `_start`，不是直接進 `main`；`0x02` 仍是保留位置，不能加入 C header。
F13 此 slot 填 `FF`，F24 device 產生 default branch；兩者都不代表可啟用 reserved IRQ。
physical BRK `0x7E` 不由 Boot 轉送；App 的保留 BRK slot 使用 RETB，不是一般 IRQ 的 RETI。

#### C5. IRQ 的產生與執行路徑

```mermaid
flowchart TD
    C["App C 檔<br/>global ISR / no vect"] --> M["加入這個 App 的 MTPJ"]
    J["這個 App 的 app_irq_handlers.h"] --> GEN["App pre-build 驗證與產表"]
    M --> GEN
    GEN --> TABLE["固定 App table<br/>vector 0A 對應 slot2014"]
    TABLE --> LINK["Linker 解決 ISR address<br/>post-build 核對 / CRC"]
    IRQ["硬體 INTP1 IRQ"] --> BOOT["Boot 實體 vector / owner 分流"]
    BOOT -->|"App owner"| SLOT["App slot2014 的 BR"]
    LINK --> SLOT
    SLOT --> ISR["app_aux_irq → RETI<br/>返回原被中斷的 App"]
```

<a id="device-app-build"></a>

### D. 產生與建置

下列是相鄰工程的相對路徑；在自己的 App 根目錄執行。先備份／記錄 matching Boot image 雜湊。
範例只變動 App 資訊及一般 IRQ，**不應呼叫 Boot 產表或 Boot rebuild**。
兩個 device 都使用 Windows PowerShell 與工程對應的 CS+／CC-RL。
CS+ 開啟自己的 App `.mtpj`，建置組態為 `DefaultBuild`。
下方 PowerShell 腳本以單次 `-ExecutionPolicy Bypass` 執行，不需永久更改系統執行原則。

#### D0. 第一次操作：逐步完成一次 App 變更

1. 選定 F13 或 F24 **device** 的 matching Boot/App，按原名稱放在同一父目錄；確認工程可建置。
2. 保存 Boot HEX、App 更新 BIN 與兩份 C header，記錄 Boot image 雜湊。
3. 開啟 App 的 `app_image_config.h`，修改 `APP_IMAGE_VERSION`／`APP_IMAGE_BUILD`；對照 B1 或 B2，保留 target／role／transport。使用 UTF-8，程式註解採英文 C90 寫法。
4. 若只升版本，跳到第6步。若新增 IRQ，依 C1 新增正常 ISR C 檔，並在 CS+ **此 App** 的 MTPJ 加入來源；還不要啟用硬體 IRQ。
5. 編輯這個 App 的 `app_irq_handlers.h`，保留既有清單，再加入 `0x0A` 範例或已核對的合法 vector／handler。
6. 從 App 根目錄執行 D1 或 D2 的產生命令，再執行 CheckOnly。錯誤先修正 C header／MTPJ／ISR，不手改 `.inc`、identity 或 table。
7. Clean Rebuild **App**，確認 pre-build 與 post-build 都成功。對照下方產物表，確認新 table、version／build、實際 BIN 長度與 CRC；使用此次成功建置的產物。
8. 在 Tool CAN TAB 載入該 App 的 `*_update.bin`，依 E 節核對映像版本、Metadata VALID 與 CRC MATCH；這一步不寫 MCU。
9. Open + Probe host、Discover **device**，核對 live target／layout／CAN／IRQ ABI／minimum Boot；相容才 Enter Boot 並開始更新，不以離線 BIN 取代 live 身分。
10. END／reset 後另外確認 App 版本 INFO／UART、既有 IRQ 與新 IRQ；最後比較 Boot 區／映像未變。硬體 IRQ 啟用前的初始化與故障測試仍需另作。

只升 App 版本時不必新增 ISR；只新增 IRQ 時也不必更改 target 或 Boot 版本。

#### D1. F13 device

```powershell
# Generate this App's metadata INC, IRQ table and identity; never Boot.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "..\RL78_F13_Boot_loader_CAN\generate_irq_contract.ps1" `
  -Mode App -AppProject "."

# Read-only freshness check; run after generating, not instead of generating.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "..\RL78_F13_Boot_loader_CAN\generate_irq_contract.ps1" `
  -Mode App -AppProject "." -CheckOnly
```

然後在 CS+ **Clean Rebuild 此 App**。原有 pre-build 保留上述 App-mode 命令，
post-build 保留 `generate_update_image.ps1`；該腳本依 map／App HEX 封裝，並非只產表就有新 BIN。
Tool 的 `scripts/verify_f13_artifacts.ps1` 可作後續檢查，需指定正確 Boot／App project。
F13 目前仍保留參考 MTPJ／map／輸出檔名與 sibling Boot 假設；若改專案名／搬目錄，
必須另外對齊 source／include／hook、`-MapFile`、輸出命名、checker 及 Boot HEX 來源。

#### D2. F24 device

```powershell
# Update this App's projections / registered project settings, never Boot.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "..\RL78_F24_Boot_loader_CAN\tools\prepare_projects.ps1" `
  -Kind app -Project "."

# Read-only freshness / registration check.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "..\RL78_F24_Boot_loader_CAN\tools\prepare_projects.ps1" `
  -Kind app -Project "." -CheckOnly

# Clean rebuild and mandatory map / image packaging checks.
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "..\RL78_F24_Boot_loader_CAN\build.ps1" `
  -Kind app -AppProject "."
```

CS+ pre-build 使用 `prepare_projects.ps1 -Kind app -Project . -ArtifactsOnly`；
post-build 使用 `package_images.ps1 -Kind app -Project .`。`-ArtifactsOnly` 僅產生編譯所需檔案。
只改一般 App 功能，不用省略 kind 的 all-mode prepare／build；SC 重產後先重新 prepare **app**。
若改名或搬移，仍須修正相對 source／include／hook 路徑；不是任意 standalone App 加 C header 即可。
F24 device prepare 使用同一磁碟內的相對路徑。

| 產物 | F13 device | F24 device |
| --- | --- | --- |
| Metadata `.inc`（不可手改） | `ftable.inc` | `ftable.inc` |
| App pre-build identity | `app_identity.h` | `app_identity.h` |
| App vector table | `app_irq_table.inc` | `app_irq_table.inc` |
| 瀏覽器編譯摘要 | `DefaultBuild/app_build_report.html` | `DefaultBuild/app_build_report.html` |
| 後續 CAN 更新 | `DefaultBuild/RL78_F13_Boot_loader_CAN_app_update.bin` | `DefaultBuild/<MTPJ stem>_update.bin` |
| 燒錄器初裝 App | `DefaultBuild/flash_app_variable_CRC.hex` | `DefaultBuild/flash_app_variable_CRC.hex` |
| matching Boot 初裝 | 先核對 `boot_app.hex` 的來源／產生時間；或 matching Boot＋App HEX | matching `boot0000_1FFF.hex`＋封裝 App HEX，依燒錄器設定核對擦除範圍 |

F13 若找不到 sibling Boot HEX，post-build 不會產生新的合併檔；先前的 `boot_app.hex` 可能仍留著。
任何 build／guard 失敗，先前 BIN 仍可能保留，使用前核對此次建置結果。
raw App MOT／ABS 可能包含低位實體記錄，不應代替已封裝的 App HEX 或 update BIN。
post-build 會拒絕 C header 與已編譯 metadata／IRQ 表不同的編譯輸出；C header 修改後進行 clean rebuild。
F13 也直接比對 App map、實際 BR 目的地與 mapped ISR 的 RETI，不依賴 Boot map 才能執行這項 App 檢查。
CheckOnly 發現手改／過期生成檔時只報錯、不修復；先重產，再 clean rebuild。

<a id="device-app-build-report"></a>

#### D3. 以瀏覽器核對編譯摘要

App post-build 通過 C header、已編譯 metadata、linker map 與 BR／ISR 檢查，完成 BIN 封裝後，
會在相同的 `DefaultBuild` 目錄產生 `app_build_report.html`。
兩個 device 使用相同的 PowerShell／.NET 報告程式，不需安裝額外軟體；HTML 可離線開啟。

| 區塊 | 可以對照的內容 |
| --- | --- |
| Packaged image | MCU part、App version／build、BIN 檔名與實際長度 |
| CRC32／SHA-256 | 重新計算的 CRC32 與尾端儲存值、整份 BIN 的 SHA-256 |
| Flash 配置 | Boot、App 向量表、metadata、code 起點、實際尾端 CRC 位址 |
| Metadata field summary | 欄位 offset、解碼值與 C header／Boot contract／post-build 來源 |
| App vector table | 全部 64 個 slot、`iodefine.h` 中斷名稱、App slot 位址、實際 BR bytes／目的地、設定 handler |
| Metadata byte addresses | 展開後列出全部 256 bytes 的 metadata offset、BIN offset、Flash address、值與欄位索引 |

在 App 根目錄可執行：

```powershell
Start-Process '.\DefaultBuild\app_build_report.html'
Get-FileHash '.\DefaultBuild\RL78_F13_Boot_loader_CAN_app_update.bin' -Algorithm SHA256
```

F24 device 的 hash 命令使用 `RL78_F24_Boot_loader_CAN_app_update.bin`。
以此次 CS+ 建置成功結果為前提，再比對報告日期與 BIN SHA-256。
建置失敗時，先前的報告與 BIN 可能仍在目錄內；報告只描述其對應產物，不表示目前原始碼已成功建置。

| 報告種類 | 產生時機與用途 |
| --- | --- |
| `app_build_report.html` | MCU App 編譯／封裝完成；核對映像、metadata、vector 與程式設定 |
| Tool `reports/update_*.json` | 一次實際更新操作結束；記錄結果、分階段耗時、重試、counter 差值與錯誤，見 [更新報告](https://released.github.io/slide_isp_tool_for_RL78/#update-confirmation) |

編譯摘要不連接 MCU，不代表 Flash 已寫入或 App 已啟動。
Tool 的更新報告也不取代編譯產物檢查；板上啟動與 IRQ 行為另外依 [驗證步驟](#device-app-validation) 核對。

<a id="device-test-images"></a>

#### 由現有 App BIN 產生 FF 填充測試映像

F13 Classical CAN、F24 Classical CAN 與 F24 CAN FD 的 App 根目錄皆提供
`generate_test_bins.bat`／`generate_test_bins.ps1`。
先完成一般 App 建置，再雙擊 batch，或在該 App 根目錄執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\generate_test_bins.ps1
```

腳本使用 Windows PowerShell／.NET 及相鄰配對 Boot 的 `app_config.ps1`，
讀取 `DefaultBuild/*_update.bin`，不重新編譯或修改 Boot／App 原始碼。
來源的 metadata、CRC、向量範圍與 App C header 身分先通過檢查，才建立測試檔。

| 產物／處理 | 內容 |
| --- | --- |
| `test_bins/<batch>/*.bin` | 每次建立新批次；檔名同時標示 Boot＋App 的 Flash 級距與實際 App BIN 大小 |
| 預設 Flash 級距 | 16／32／64／128／256／512 KiB；扣除來源 metadata 的 Boot reserve，並限制於 App capacity |
| `0xFF` 填充 | 保留原本可執行 App 與向量表；從原 CRC 位置填到新 CRC 前，不截短程式 |
| 長度與 CRC | 更新 BIN `0x118..0x11B` 的 image_size；最後 4 bytes 為重新計算的 little-endian CRC32 |
| `manifest.csv` | 實際 bytes、CRC、SHA-256、來源雜湊、版本、build、CAN mode 與填充值 |
| `skipped.csv` | 說明超出實體 Flash 或現有 App 放不下的級距 |

1 KiB 為 1024 bytes。F13 App 上限 119 KiB；F24 兩種 CAN 模式均為 247 KiB，保留末端 1 KiB。
需要完整 120／248 KiB 時，工程設定與 RFP 安裝限制見 [Flash 尾端保護的重要事項](https://released.github.io/slide_boot_loader_for_RL78/#device-debug-monitor)。
既有 App 若變大，放不下的級距會略過；其他有效檔案仍可產生。
輸出目錄由 Git 排除，腳本隨專案分享，來源 App 更新後可再次產生對應測試檔。

版本、build、minimum Boot 與更新政策沿用來源，Tool 仍依板上資訊執行原有檢查。
測試檔依其 CAN mode 使用既有 [Device 更新操作](https://released.github.io/slide_isp_tool_for_RL78/#mcu-can-device)，
實際結果保留在 [Tool JSON 更新報告](https://released.github.io/slide_isp_tool_for_RL78/#update-confirmation)。
`0xFF` 填充描述這一種資料內容；離線檢查不代表實板更新或任意資料的寫入效能已驗證。

<a id="device-update-timing"></a>

#### App BIN 更新耗時參考

以下為單次實板更新的粗略等待時間參考，以 Tool 報告的 `elapsed_ms` 換算為秒，顯示至小數一位。
總時間包含更新流程的檢查、傳輸與 Flash 擦寫、END CRC、App 啟動確認及收尾，不是純 Flash 寫入速度。
實際時間也會受 Host Link UART、電腦與通訊狀態影響。

Classical CAN 使用 **500 kbit/s**。
CAN FD 欄位使用 **nominal 500 kbit/s／data 2 Mbit/s／BRS 開啟**，不是全程以 500 kbit/s 傳輸。

| App BIN | F13 device：Classical CAN 500K | F24 device：Classical CAN 500K | F24 device：CAN FD 500K／2M、BRS |
| --- | --- | --- | --- |
| 原始 App（未填充） | 20,308 bytes／— | 4,224 bytes／約 5.2 秒 | 4,756 bytes／約 5.5 秒 |
| 8 KiB（8,192 bytes） | 不適用 | 約 7.3 秒 | 約 7.2 秒 |
| 24 KiB（24,576 bytes） | 約 15.8 秒 | 約 15.6 秒 | 約 15.6 秒 |
| 56 KiB（57,344 bytes） | 約 32.3 秒 | 約 32.2 秒 | 約 32.2 秒 |
| 119 KiB（121,856 bytes） | 約 65.8 秒 | — | — |
| 120 KiB（122,880 bytes） | 不適用 | 約 65.5 秒 | 約 65.5 秒 |
| 247 KiB（252,928 bytes） | 不適用 | 約 136.2 秒 | 約 134.2 秒 |

「—」表示沒有該欄對應的量測資料，不代表更新失敗；原始 App 列分別列出 BIN 大小與已有的量測時間。
「不適用」表示測試映像小於來源 App，或超過目前預設 App 容量。
各列均指實際 App BIN 長度，包含向量表、metadata、程式／填充與 CRC；1 KiB＝1024 bytes。

##### F13 量測條件與來源

| 項目 | 本表使用的實測條件 |
| --- | --- |
| 日期／MCU | 2026-10-22／RL78/F13 R5F10BMG |
| Host Link UART／CAN | 115200 baud／Classical CAN 500 kbit/s |
| Detailed trace | 關閉 |
| Tool／Host firmware | 0.1.0.0097／1.7.0，Host build 20261019 |
| Device Boot／App | Boot 1.7.2、build 20261022／App 1.6.1、build 20261017 |
| 測試映像內容 | 由原始 App BIN 延伸，以 `0xFF` 填充並更新長度與 CRC32 |
| 更新結果 | 三份均 PASS，END CRC 通過、APP_READY 與 live image 比對通過 |
| 重試／已記錄的 Host 錯誤 | 三份 `link_retries=0`；UART overflow、CAN lost／warning／passive／bus-off／recovery／TX failure 差值均為 0 |

來源為 Tool 的 JSON／HTML 更新報告；下表報告識別前加 `update_20261022_`，副檔名為 `.json`／`.html`。
對應 Log 為 `firmware_upgrade_tool_20261022_172301.log`。

| 報告識別 | App BIN | elapsed_ms | Image CRC32 |
| --- | --- | --- | --- |
| `092335_621_54044_695182765_1` | 24 KiB | 15845 | `0xCA0DE29D` |
| `092427_590_54044_695234734_2` | 56 KiB | 32281 | `0x8BF223B3` |
| `092553_622_54044_695320765_3` | 119 KiB | 65793 | `0x7A2A9624` |

##### F24 Classical CAN 量測條件與來源

| 項目 | 本表使用的實測條件 |
| --- | --- |
| 日期／MCU | 2026-10-22／RL78/F24 R7F124FPJ5xFB |
| Host Link UART／CAN | 115200 baud／Classical CAN 500 kbit/s |
| 逐幀記錄 | 對應 Log 未包含 `TRACE UART`／`TRACE CAN` 記錄 |
| Tool／Host firmware | 0.1.0.0098／1.7.0，Host build 20261019 |
| Device Boot／App | Boot 1.1.1、build 20261022／App 1.0.3、build 20261019 |
| 測試映像內容 | 原始 App，以及由其延伸、以 `0xFF` 填充並更新長度與 CRC32 的測試 BIN |
| 更新完成條件 | 六次均完成 END CRC、APP_READY／live image 比對及 CAN_STOP 確認 |

來源為 Tool 的 JSON／HTML 更新報告；下表報告識別前加 `update_20261022_`，副檔名為 `.json`／`.html`。
對應 Log 為 `firmware_upgrade_tool_20261022_180801.log`；表格列出整次操作的實際耗時，診斷細節保留於原始報告。

| 報告識別 | App BIN | elapsed_ms | Image CRC32 |
| --- | --- | --- | --- |
| `100929_089_55528_697936171_1` | 原始 App，4,224 bytes | 5222 | `0x4837111E` |
| `101010_155_55528_697977234_2` | 8 KiB | 7272 | `0x04D5ED74` |
| `101047_098_55528_698014187_3` | 24 KiB | 15556 | `0xBF72D477` |
| `101148_050_55528_698075140_4` | 56 KiB | 32198 | `0x9A0D4CAA` |
| `101320_919_55528_698168000_5` | 120 KiB | 65453 | `0x1F248CFA` |
| `101601_871_55528_698328953_6` | 247 KiB | 136242 | `0x3274CC2A` |

##### F24 CAN FD 量測條件與來源

2026-10-22，RL78/F24 R7F124FPJ5xFB；Host Link UART 115200 baud，CAN FD nominal 500 kbit/s、data 2 Mbit/s、BRS 開啟。
Tool 0.1.0.0099，Host firmware 1.7.0／build 20261019，Device Boot 1.2.1／App 1.0.4。

測試映像為原始 App，以及由其延伸、以 `0xFF` 填充並更新長度與 CRC32 的 BIN。
六次均完成 END CRC、APP_READY／live image 比對及 CAN_STOP 確認；對應 Log 未包含 `TRACE UART`／`TRACE CAN` 逐幀記錄。

來源為 Tool 的 JSON／HTML 更新報告；下表報告識別前加 `update_20261022_`，副檔名為 `.json`／`.html`。
對應 Log 為 `firmware_upgrade_tool_20261022_182748.log`。
表格保留各次操作的實際總時間，包含重試與收尾；結果分類與 counter 細節保留於原始報告。
量測條件以上述 Tool 與 firmware 為準；不同設定需各自量測。

| 報告識別 | App BIN | elapsed_ms | Image CRC32 |
| --- | --- | --- | --- |
| `102840_499_88416_699087546_1` | 原始 App，4,756 bytes | 5516 | `0x2244D36A` |
| `102911_331_88416_699118375_2` | 8 KiB | 7240 | `0x3FCC99E2` |
| `102956_261_88416_699163312_3` | 24 KiB | 15559 | `0x688C8587` |
| `103045_317_88416_699212359_4` | 56 KiB | 32188 | `0x5ED8A374` |
| `103238_863_88416_699325906_5` | 120 KiB | 65515 | `0x2B5ADB06` |
| `103540_647_88416_699507687_6` | 247 KiB | 134185 | `0x325DBF76` |

##### 相關說明

- [CAN 更新協定與逐 byte 封包格式](https://released.github.io/slide_boot_loader_for_RL78/#flash-metadata-can-reference)
- [Boot 完整 IRQ table 與 App software dispatch](https://released.github.io/slide_boot_loader_for_RL78/#device-irq-ownership)
- [Software dispatch 的時間與 stack 成本](https://released.github.io/slide_boot_loader_for_RL78/#device-irq-dispatch-cost)
- [Boot 燒錄方式與 Flash 尾端保護](https://released.github.io/slide_boot_loader_for_RL78/#device-debug-monitor)：CS+ 安裝 Boot 時，App 上限為 119／247 KiB，最後 1 KiB 保留給 debug monitor 所在的擦除區塊。需要完整 120／248 KiB 時，須調整配對工程，且 **Boot 只能由 RFP 安裝**。

<a id="device-app-runtime-log"></a>

#### D4. App 執行標籤與每秒 counter

診斷 UART 使用 115200。兩個 App 都在主迴圈輸出每秒遞增 counter，
timer ISR 僅提供時基／事件；不在 ISR 內格式化或傳送文字。

| Device | 可編輯位置 | 用途 |
| --- | --- | --- |
| F13 | App `custom_func.h` 的 `APP_RUNTIME_LOG_TAG` | 選擇 `"V1"`／`"V2"` 等觀察標籤；`custom_func.c` 的主迴圈輸出 counter |
| F24 | App `app_runtime_log.h` 的 `APP_RUNTIME_LOG_TAG` | 同樣選擇觀察標籤；`app_main.c` 每秒呼叫 App 專用 counter formatter，再經 UART 輸出 |

```text
app image tag: V1
log(timer)-V1: 0
log(timer)-V1: 1
log(timer)-V1: 2
```

counter 從 App 啟動後的零開始，以十進位遞增；空白對齊不影響其數值。
標籤獨立於 metadata 的 `APP_IMAGE_VERSION`；只改標籤不會改變 Tool 的版本比較。
編輯後依 [App-only 建置](#device-app-build) 重新封裝、載入更新 BIN，
更新後同時核對 Tool 的 App 啟動確認與 UART 輸出。

<a id="device-app-validation"></a>

### E. BIN 與向量驗證

| 步驟 | 要檢查的結果 | 未通過時 |
| --- | --- | --- |
| 產表 | 新 C header entry 對應到正確 slot；source 有且僅有對應的正常 ISR | 不手改生成檔，修 source／MTPJ／C header |
| map／向量 bytes | table 在 `0x2000`，metadata 不佔 code；BR 指向 App code，ISR 應有 RETI | 不更新 MCU；先查 linker／pragma／註冊 |
| BIN offline | size 等於檔長、metadata reserved FF、CRC match、role／CAN／ABI 正確 | 不用修改 Tool 欄位繞過 |
| Tool Load Update Image | Metadata VALID、CRC MATCH、新 version／build；這仍只是 offline 資訊 | 重查 producer／封裝及實際載入檔案 |
| Discover live device | MCU／target／geometry／CAN／IRQ ABI／minimum Boot 相容 | 不送 START；不能把載入 BIN 身分當 live 身分 |
| 更新與 reset | END 成功後，確認 App INFO／UART 與載入映像一致、正常與新增 IRQ，Boot 區未變 | 保留 log／trace，分別記錄 END ACK 與 App 執行證據 |

#### E1. Tool 驗證與更新後 App 證據

```mermaid
flowchart TD
    BUILD["App clean rebuild / packaging guards"] --> OFF["檢查新 BIN<br/>metadata / version / size / CRC"]
    OFF --> LIVE["Tool：Probe host + Discover device<br/>比對 live contract"]
    LIVE --> OK{"全部相容？"}
    OK -->|"否"| STOP["停止；不送 START / 不擦 Flash"]
    OK -->|"是"| CAN["Enter Boot → metadata SEAL<br/>START → blocks → END"]
    CAN --> RESET["Reset 後 Boot 再驗證"]
    RESET --> APP["確認 App 版本 / IRQ 功能<br/>另留 Boot 未變的證據"]
```

INTP1 範例涵蓋來源登錄與產表；實際 IRQ 功能仍需搭配板端初始化與量測。
F13 與 F24 device 的正常 CAN App 更新及啟動皆已完成實板驗證；
F24 的報告與 UART counter 見 [更新結果](https://released.github.io/slide_isp_tool_for_RL78/#f24-device-update-example)。
不同速率、其他 IRQ、取消與斷電等條件分別驗證。
CRC 用於完整性檢查。
更新中斷後，Boot 於下次啟動重新驗證現有映像，驗證有效才進入 App。

### F. 常見錯誤與只換 App 的邊界

| 變更／錯誤 | 處理原則 |
| --- | --- |
| 只改 App version／build 或相容的一般 IRQ | 產表、重建與封裝 App；不因 ISR 名稱改動重燒 Boot |
| 改 MCU／App start／geometry／IRQ ABI／更新協定 | 屬於共同契約變更；同步 Boot、App、producer、Tool／validator 並重新驗證 |
| Vector 位址填入 `0x2014`、IRQ index 或保留／奇數 vector | 填寫合法實體 byte address，本例為 `0x0A`；以本工程 header 核對 |
| C 檔只複製進資料夾，沒有加入 MTPJ | generator 或 linker 應拒絕；先修正專案登錄 |
| ISR 帶 `vect=`／static／普通函式，或 symbol 拼錯 | 改成正常 global interrupt ISR，再核對 C header 與 generated table |
| 覆蓋原有 UART／timer mappings | 先恢復仍在用的清單；新增不是替換整份 C header |
| 手改 `.inc`、generated table、identity、BIN bytes／CRC | 由兩份 C header／ISR 來源修改並重建；CheckOnly 僅檢查，不更新產生檔 |

同一份 Boot 可搭配 App A／B 的不同 ISR 清單，前提是完整共同契約不變。
新增 IRQ 後，仍核對硬體初始化、stack、pending flag 與實際 IRQ 行為。

<a id="device-can-bitrate"></a>

### G. Device CAN 速率：250K／500K／1M

本節設定 MCU CAN device 的 Classical CAN 更新速率，單位為 kbit/s 或 Mbit/s。
Boot 與 App 的 INFO／ENTER／更新通訊使用相同速率；範例預設 500 kbit/s。
Tool 的 CAN Nominal 下拉選單設定 MCU CAN host 的 bus timing，不改寫 device register 或 metadata。
PC 與 host 之間的 Host Baud 仍是獨立的 UART 設定。

#### G1. 修改位置與計算來源

| Device | 實際 CAN timing 輸入 | Boot／App 的引用方式 | 目前時鐘／時序 |
| --- | --- | --- | --- |
| F13 | **Boot 與 App 各自**的 `RSCANconf/RSCANlite.h`：`CAN_CFG_C0_BAUDRATE_L` | 兩份工程各有 driver 設定，兩份 header 都修改；App 的 metadata CAN 契約引用相鄰 Boot | fCAN 16 MHz；SS／TSEG1／TSEG2＝1／11／4 TQ；sample point 75% |
| F24 | Boot `common/f24_device_config.h`：`CAN_CFG_NBRP` | Boot／App 的 CS+ preinclude 引用同一 header；保留此設定，不直接修改生成的 `smc_gen` | fCAN 40 MHz；SS／TSEG1／TSEG2＝1／15／4 TQ；sample point 80% |

兩者的計算式皆為 `bitrate = fCAN / ((BRP register + 1) × (1 + TSEG1 + TSEG2))`。
F13 寫入位置是 `r_rl78_can_drv.c` 的 `C0CFGL/C0CFGH`；
F24 是生成 driver `r_rscanfd_rl78.c` 的 `C0NCFGL/C0NCFGH`，
其 `CAN_CFG_NMNL_TSEG1/2` 由設定 header 轉成 register encoding。
可由各工程上述原始碼及 MCU 硬體手冊的 CAN bit timing／configuration register 核對。
F13 原始設定可直接開啟 [Boot RSCANlite.h](https://github.com/released/RL78_F13_Boot_loader_CAN/blob/main/RSCANconf/RSCANlite.h)
及 [App RSCANlite.h](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/RSCANconf/RSCANlite.h)。

以下只調整 BRP，保留上述 clock、TSEG1／2 與現有 SJW；改 clock 或 TSEG 時需重新計算。

| 選定速率 | F13 `CAN_CFG_BAUDRATEL(...)` 參數 | F24 `CAN_CFG_NBRP` | nominal mask／單一 bit | Metadata LE32 bytes |
| --- | --- | --- | --- | --- |
| 250 kbit/s | `3U`，除 4 | `(7)`，除 8 | `0x00000002UL`／bit1 | `02 00 00 00` |
| 500 kbit/s | `1U`，除 2 | `(3)`，除 4 | `0x00000004UL`／bit2 | `04 00 00 00` |
| 1 Mbit/s | `0U`，除 1 | `(1)`，除 2 | `0x00000010UL`／bit4 | `10 00 00 00` |

速率宣告位於 Boot `can_boot_config.h` 的 `CAN_BOOT_NOMINAL_500K_MASK`，
數值使用表中的選定速率單一 bit。它提供 metadata 與 live INFO 比對值，不設定 CAN register。
固定單一速率的 device 不宣告多個速率 bit；例如 `0x16` 不會讓 Boot 自動辨識三種速率。
Classical 的 `CAN_BOOT_DATA_BITRATE_MASK` 保持零。
nominal mask 位於 metadata `0x30..0x33`，即 BIN offset `0x130..0x133`、本配置 Flash `0x2130..0x2133`。

#### G2. 以 250 kbit/s 完成一次配置

1. 保存目前 Boot HEX、App BIN 與設定檔；選定配對的 MCU CAN device Boot／App。
2. 修改實際 timing：F13 在 **兩份** `RSCANlite.h` 將 `CAN_CFG_BAUDRATEL(1U)` 改成 `CAN_CFG_BAUDRATEL(3U)`；
   F24 在共用 `f24_device_config.h` 將 `CAN_CFG_NBRP (3)` 改成 `(7)`。
3. 在該 device Boot 的 `can_boot_config.h`，將 `CAN_BOOT_NOMINAL_500K_MASK` 設為 `(0x00000002UL)`。
   App 的 metadata／INFO 由配對契約取得，保留其引用，不手改生成的 INC／BIN。
4. 核對 App 發行版本／build，clean rebuild **Boot 與 App**，執行原有 pre-build／post-build。
   F13 分別在 CS+ 對兩個 `.mtpj` 執行 Rebuild；也可在各工程根目錄以 PowerShell 呼叫 CS+ 安裝目錄的
   `CubeSuite+.exe /br .\<project>.mtpj`。F24 在 Boot 根目錄執行下列命令：

```powershell
# Rebuild the paired device Boot, then App; Transfer is independent.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind boot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind app
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test.ps1
```

5. 核對成功建置結果、Boot 分區／512-byte 餘裕、App metadata、BR table 與 CRC。
   在 `app_build_report.html` 確認 nominal mask 為 `0x02`，並核對來源 timing；報告不是 bus 波形量測。
   本節範例改為 1 Mbit/s 時，使用表中的 BRP 與 mask `0x10`，其餘流程相同。
6. 使用燒錄器安裝新速率的 Boot 與封裝 App HEX，或工程產生的合併 `boot_app.hex`。
   保留分區／option bytes／保護範圍；檔案選擇見 [韌體下載與安裝](https://released.github.io/slide_isp_tool_for_RL78/#downloads)。
   CAN 更新只改 App，不能將已安裝的 500K Boot 一併換成 250K Boot。
7. Tool Open + Probe Host，在 CAN 頁選 Classical CAN／250K；analyzer 也設為 250K。
   載入此次 `*_update.bin`，確認 Interface / Rate、Metadata VALID、CRC MATCH。
8. Discover device，核對 live INFO 的 nominal mask 與 BIN／Tool 相符。
   若 App 正在執行，Enter Boot 後接續 Start Device Update；完成後核對 App 確認、UART counter 與下一次 Discover。

```mermaid
flowchart TD
    RATE["選定 MCU CAN device 速率"] --> DRIVER["Boot／App 實際 CAN timing"]
    RATE --> META["CAN 契約的 nominal mask"]
    DRIVER --> BUILD["Clean rebuild Boot 與 App"]
    META --> BUILD
    BUILD --> CHECK["檢查封裝／metadata／CRC／分區"]
    CHECK --> INSTALL["燒錄器安裝配對 Boot／App"]
    INSTALL --> TOOL["Tool 與 analyzer 選相同 CAN 速率"]
    TOOL --> LIVE{"Discover／BIN／live 設定相符？"}
    LIVE -->|"是"| UPDATE["Enter Boot／更新／確認 App"]
    LIVE -->|"否"| STOP["停止更新；核對 timing 與契約"]
```

#### G3. 驗證與錯誤定位

| 現象／檢查 | 核對位置與結果 |
| --- | --- |
| Discover timeout | 先核對 device 真正的 Boot／App timing、Tool／analyzer 速率、clock、ACK、接線與終端；尚未收到 INFO 不能以 BIN 宣告證明板上設定 |
| BIN 或 live rate mismatch | 核對 nominal mask、App producer 與已安裝 Boot／App 是否來自同一次配對建置；只改 driver 或只改 mask 都不完整 |
| App 可探索，Enter Boot 後失聯 | 核對 Boot 與 App 的實際 timing 是否一致；F13 特別核對兩份 `RSCANlite.h` |
| 完成更新後的 App 驗證 | CRC／App INFO／UART counter 分別確認；以 analyzer 核對實際速率與 error frame |
| 速率驗證範圍 | 本節列出依現有 clock 計算的 presets；500K 有正常更新紀錄，250K／1M 的連續更新、重啟與故障復原需分別保留實板證據 |
<!-- DEVICE_WORKSHOP_END -->

<!-- RL78_PORTING_BEGIN -->
<a id="boot-app-porting"></a>

## MCU CAN device：Boot 與 App 工程

本節整理 MCU CAN device 的分區、startup、RAM、向量與映像產生方式。
F13、F24 各自維護獨立的 Boot／App 工程，使用相同的流程概念與 C header 設定方式。
兩份工程共同作為後續 MCU 的 [工程基準](https://github.com/released/simple_renesas_isp_tool/blob/main/docs/DEVICE_GOLDEN_SAMPLE_zh-TW.md)。

Metadata 編輯與新增 IRQ 的逐步操作集中於 [Device App 設定](https://released.github.io/slide_boot_loader_for_RL78/#device-metadata-vector-workshop)。
本節著重移植時各項工程設定的關係。

### 1. 工程來源

| 工程 | F13 (MCU CAN device) | F24 (MCU CAN device) |
| --- | --- | --- |
| Boot | [RL78_F13_Boot_loader_CAN](https://github.com/released/RL78_F13_Boot_loader_CAN) | `RL78_F24_Boot_loader_CAN` |
| App | [RL78_F13_Boot_loader_CAN_app](https://github.com/released/RL78_F13_Boot_loader_CAN_app) | `RL78_F24_Boot_loader_CAN_app` |
| MCU | R5F10BMG | R7F124FPJ5xFB |
| Flash driver | FSL | RFD Type02 |
| Target／IRQ ABI | `0xF13B`／F1V1 | `0xF24B`／F2V1 |
| 板端時鐘 | X1 4MHz、CPU32／CAN16 | X1 4MHz、PLL80、CPU／CAN40 |
| 工程配置 | [F13 啟動與更新](https://released.github.io/slide_boot_loader_for_RL78/#f13-boot-decision) | [F24 工程配置](https://released.github.io/slide_boot_loader_for_RL78/#f24-can-device) |

各 App 引用相鄰 Boot 工程提供的共用來源與建置腳本。
工程放置方式如下，F13 與 F24 可依需要分別使用：

```text
examples/
  RL78_F13_Boot_loader_CAN/
  RL78_F13_Boot_loader_CAN_app/
  RL78_F24_Boot_loader_CAN/
  RL78_F24_Boot_loader_CAN_app/
```

ZIP 解壓後的目錄名稱與 MTPJ 引用路徑保持一致。
F13 原始碼可在同一目錄取得：

```powershell
git clone https://github.com/released/RL78_F13_Boot_loader_CAN.git
git clone https://github.com/released/RL78_F13_Boot_loader_CAN_app.git
```

### 2. Flash 與映像配置

| 區域 | F13 device | F24 device |
| --- | --- | --- |
| Boot | 0x0000..0x1FFF，8 KiB | 0x0000..0x1FFF，8 KiB |
| App 可用區 | 0x2000..0x1FBFF，119 KiB | 0x2000..0x3FBFF，247 KiB |
| App 跳轉表 | 0x2000..0x20FF | 0x2000..0x20FF |
| Metadata core | 0x2100..0x217F | 0x2100..0x217F |
| Metadata reserved FF | 0x2180..0x21FF | 0x2180..0x21FF |
| App code 起點 | 0x2200 | 0x2200 |
| Flash 尾端保護 | 0x1FC00..0x1FFFF，1 KiB | 0x3FC00..0x3FFFF，1 KiB |
| Image CRC32 | 實際 BIN 最後4 bytes、LE32 | 實際 BIN 最後4 bytes、LE32 |

App 前512 bytes 由256-byte向量表與256-byte metadata 組成。
BIN 的實際長度由 linker map 決定，尾端四位元組對齊並加上 CRC32。

各 Boot 的 `image_metadata_config.h` 定義映像契約；`can_boot_config.h` 定義 CAN，`boot_app_handoff.h` 定義 RAM 交接。
完整編輯分工見 [設定檔與產物](https://released.github.io/slide_boot_loader_for_RL78/#device-metadata-vector-workshop)。
獨立 `image_metadata.c/.h` 搭配工程專用 `image_metadata_profile.c`；API 與移植方式見 [Metadata C 模組](https://released.github.io/slide_boot_loader_for_RL78/#device-metadata-parser)。
逐 byte 位址見 [Flash／metadata 參考](https://released.github.io/slide_boot_loader_for_RL78/#flash-metadata-can-reference)。

<a id="device-debug-monitor"></a>

#### 重要事項：Boot 燒錄方式與 Flash 尾端保護

**若 App 需要用滿 F13 的 120 KiB／F24 的 248 KiB，Boot 只能使用 Renesas Flash Programmer（RFP）安裝。**
**不可使用 CS+「下載並除錯」安裝 Boot 後，再執行滿容量 App 更新；更新可能通過 END CRC，但 App 啟動、UART Log 或 CAN 連線仍出現異常。**

CS+ Debug 下載會在 Code Flash 尾端放入 debug monitor，並使用除錯啟動路徑。
移除 E2 Lite 或離開 Debug mode，並不代表 Flash 中的 monitor 已移除。
更新若擦寫到該區，會破壞除錯啟動所需的內容；不能只憑 END CRC 通過判定重啟一定正常。

| 配置 | F13 device | F24 device（Classical CAN／CAN FD） |
| --- | --- | --- |
| Code Flash／Boot | 128／8 KiB | 256／8 KiB |
| 目前 CS+ monitor 範圍 | `0x1FE00..0x1FFFF`，512 bytes | `0x3FF00..0x3FFFF`，256 bytes |
| 預設保護範圍 | `0x1FC00..0x1FFFF`，1 KiB | `0x3FC00..0x3FFFF`，1 KiB |
| 預設 App 最大 BIN | **119 KiB**（121856 bytes） | **247 KiB**（252928 bytes） |
| 預設配置的 Boot 安裝方式 | CS+ Debug 下載或 RFP | CS+ Debug 下載或 RFP |
| 自訂滿容量 App BIN | **120 KiB：僅限 RFP 安裝 Boot** | **248 KiB：僅限 RFP 安裝 Boot** |

Monitor 大小會隨 MCU 與除錯選項改變；表中是目前工程的設定。
Flash 擦除單位為 1 KiB，因此保留完整末端區塊，而非只扣除 monitor 的 256／512 bytes。
App BIN 容量包含向量表、metadata、程式／填充與最後 4 bytes CRC32；1 KiB＝1024 bytes。

需要滿容量時，工程配置與安裝方式須一起調整：

1. 在 Boot 的 `image_metadata_config.h` 設定 `IMAGE_APPLICATION_CAPACITY`：F13 為 `0x1E000`，F24 為 `0x3E000`。
2. 重新建置配對的 Boot 與 App，確認 Flash 擦寫邊界、產生的 metadata、封裝範圍與 Tool live capacity 一致；重新產生測試 BIN。
3. **使用 RFP 安裝配對的 Boot HEX**，再以 Tool 更新 App BIN；不可將 CS+ Debug 下載當作這一步的替代方式。
4. 若之後再次使用 CS+ Debug 下載，滿容量更新前須重新以 RFP 安裝 Boot。

僅改用 RFP、不修改配對工程，預設 Boot 仍只接受 119／247 KiB 以內的 App。
目前操作依據可參閱 Renesas [E1／E20／E2／E2 Lite RL78 附加手冊](https://www.renesas.com/en/document/mat/e1e20e2-emulator-e2-emulator-lite-additional-document-users-manual-notes-connection-rl78) §3.3.1（monitor 區域）、§3.5.1（self-programming）及 §3.8.2（離開除錯後獨立運作）。

### 3. Startup、RAM 與中斷交接

| 項目 | 工程設定與檢查位置 |
| --- | --- |
| Project device／CC-RL | MCU、記憶體模型、Flash driver |
| Startup | stack、data／bss 初始化、App 起點 |
| No-init RAM | `0xFF710..0xFF71F` owner／handoff／update marker；startup 與 linker 保留此區 |
| ENTER marker | F13：`0xFF700`，見 r_main.c；F24：`0xFF71C`，見 boot_main.c |
| IRQ owner | `0xAA`：Boot；`0x55`：App |
| RAM／stack | linker map 確認與 no-init 區間分離 |
| Flash 執行路徑 | F24 RFD programming-mode 路徑及必要資料位於 RAM |
| Build events | App pre-build 產表；post-build 驗證及封裝 |

Boot 交接前關閉中斷、整理周邊狀態並寫入 App owner。
App 經自己的 startup 初始化後，再啟用所需周邊與 IRQ。

F13 的 `f13_board_support` 與 startup user-area clock hook 負責時鐘交接。
F24 的 `common` 與 startup projection 負責板端初始化及 RFD RAM 配置。
這些來源分別保留在各自工程中。

### 4. 固定向量介面

一般 IRQ 的 owner 分流、16-bit 實體入口、App 槽位換算及轉送成本集中於
[Boot／App 中斷所有權](https://released.github.io/slide_boot_loader_for_RL78/#device-irq-ownership)。
新增 App ISR 的操作與來源查找見 [IRQ 設定與來源對照](https://released.github.io/slide_boot_loader_for_RL78/#device-app-irq)。

<a id="device-irq-porting"></a>

固定 Boot 與 App 跳轉表可沿用同一設計概念；跨 MCU 時，依目標硬體與編譯器建立工程配置。

| 項目 | 需要依 MCU 核對的內容 | 來源與核對結果 |
| --- | --- | --- |
| IRQ 配置 | 有效 vector、保留槽位、特殊中斷與返回方式 | 硬體手冊 Interrupt Functions、工程 `iodefine.h`、生成表及實際 RETI／RETB |
| Flash 分區 | Boot 大小、App 起點、擦除單位與保護範圍 | 硬體手冊、`image_metadata_config.h`、linker map 與封裝映像範圍 |
| startup／linker | 區段位置、近／遠跳轉、ISR 編譯規則 | startup、MTPJ 選項、Boot stub 的低位址範圍及 App BR 的實際目的地 |
| RAM／交接 | owner、stack、周邊停止與待處理中斷清除 | `boot_app_handoff.h`、no-init 區段、交接函式與 App 初始化 |
| Flash 更新 | 對應 Flash library、RAM 執行要求及擦寫期間的中斷條件 | 該 MCU 的 FSL／RFD 手冊、RAM copy 範圍、DI／EI 與 Flash 呼叫路徑 |

軟體向量轉送決定一般 IRQ 的執行目的地；Flash 擦寫期間能否取指、讀取常數或處理中斷，
仍依 MCU 與 Flash library 的限制配置。
若擦寫期間需要啟用中斷，另核對從實體 vector、stub、dispatcher 到 handler 與資料的完整路徑是否仍可存取。

### 5. 設定檔與建置

| 內容 | F13 device | F24 device |
| --- | --- | --- |
| App 資訊 | `app_image_config.h` | `app_image_config.h` |
| IRQ mapping | `app_irq_handlers.h` | `app_irq_handlers.h` |
| pre-build | `generate_irq_contract.ps1 -Mode App` | `prepare_projects.ps1 -Kind app` |
| post-build | `generate_update_image.ps1` | `package_images.ps1 -Kind app` |
| App-only 更新 | App update BIN | App update BIN |

兩個工程的日常產表與封裝均使用 Windows PowerShell、CS+／CC-RL。
來源搬移或改名時，source／include／hook、map 與輸出檔名一併調整。
完整命令集中於 [產生與建置](https://released.github.io/slide_boot_loader_for_RL78/#device-app-build)。

### 6. 初次安裝與後續更新

| 用途 | F13 device | F24 device |
| --- | --- | --- |
| 燒錄器初裝 | App 根目錄 `boot_app.hex` | App 根目錄 `boot_app.hex`，或 Boot `boot0000_1FFF.hex`＋App `flash_app_variable_CRC.hex` |
| CAN 更新 App | `DefaultBuild/*_update.bin` | `DefaultBuild/*_update.bin` |
| 除錯檢查 | 保留 Boot 實體向量，載入 App symbols | 保留 Boot 實體向量，載入 App symbols |

Tool 操作見 [CAN device 更新](https://released.github.io/slide_isp_tool_for_RL78/#mcu-can-device)。
以燒錄器安裝時，核對每個檔案的範圍與 erase 設定。
App raw ABS／MOT 與封裝後的安裝映像分別使用於編譯除錯及正式初裝。

### 7. 啟動與更新流程

```mermaid
flowchart TD
    RESET["MCU CAN device reset / Boot startup"] --> CHECK{"App 完整有效且無更新要求？"}
    CHECK -->|是| HAND["周邊交接與 App owner"]
    HAND --> APP["App startup / 正常功能"]
    CHECK -->|否| UPDATE["Boot 接收更新 / 驗證 metadata"]
    UPDATE --> FLASH["依序更新 App Flash"]
    FLASH --> END{"全映像驗證通過？"}
    END -->|否或更新中斷| RECOVERY["Boot 等待完整更新"]
    END -->|是| RESET
```

各工程的 marker、逾時與 Flash 操作由各自 Boot 處理。
F13 的狀態條件見 [F13 Boot 啟動與更新](https://released.github.io/slide_boot_loader_for_RL78/#f13-boot-decision)。
F24 的狀態路徑見 [F24 device 工程配置](https://released.github.io/slide_boot_loader_for_RL78/#f24-can-device)。

### 8. App 變更與驗證

| 變更 | 檢查範圍 |
| --- | --- |
| App 功能、版本、一般 IRQ | App 來源、C header、初始化、生成表與更新 BIN |
| MCU、Flash 分區、RAM、IRQ ABI | Boot／App 共同契約、linker 與封裝 |
| 更新介面、CAN IDs／speed | Boot／App 通訊、metadata 與 Tool target adapter |

App 更新時可保存 Boot 映像雜湊，確認 App-only 作業的範圍。
靜態檢查包含 BR entry、RETI／RETB、metadata、CRC、ROM／RAM／stack。
實板驗證包含上電、ENTER、更新後 App、各 IRQ、重送、斷線與斷電復原。
<!-- RL78_PORTING_END -->

<!-- FLASH_REFERENCE_BEGIN -->
<a id="flash-metadata-can-reference"></a>

## 1. 適用角色與閱讀方式

本節對照 **F13 (MCU CAN device)** 與 **F24 (MCU CAN device)** 的 App metadata、Flash 位址與 CAN 封包。
兩者各自有獨立的 Boot／App 工程，共用欄位格式與更新流程概念。

映像識別碼為 ASCII `CAN\0`（數值 `0x004E4143`，bytes `43 41 4E 00`）。
這是檔案格式的 magic，與 CAN0／CAN1 等通道編號無關。
CAN channel 與 pin 由各 MCU 工程設定，bridge port 由 Tool 選擇。

### Flash絕對位址、BIN offset與metadata offset

```text
metadata_base = app_start + 0x100
field_flash_address = app_start + 0x100 + metadata_offset
field_bin_offset = 0x100 + metadata_offset
crc_flash_address = app_start + image_size - 4
crc_bin_offset = image_size - 4
```

例如兩個 device 的 target_id 都位於 metadata offset `0x0C..0x0D`，Flash 位址為 `0x0210C..0x0210D`，BIN offset 為 `0x10C..0x10D`。
多 byte 整數採 little-endian，低位 byte 放在低位址。

| 區域 | F13 (MCU CAN device) | F24 (MCU CAN device) |
| --- | --- | --- |
| Code Flash | 0x00000..0x1FFFF | 0x00000..0x3FFFF |
| Boot | 0x00000..0x01FFF | 0x00000..0x01FFF |
| App 可用範圍 | 0x02000..0x1FBFF | 0x02000..0x3FBFF |
| App 固定跳轉表 | 0x02000..0x020FF | 0x02000..0x020FF |
| Metadata 整區 | 0x02100..0x021FF | 0x02100..0x021FF |
| 已定義 core／含 UPD1 | 0x02100..0x0217F | 0x02100..0x0217F |
| Reserved FF | 0x02180..0x021FF | 0x02180..0x021FF |
| Linked code 起點 | 0x02200 | 0x02200 |
| Flash 尾端保護 | 0x1FC00..0x1FFFF | 0x3FC00..0x3FFFF |
| Image CRC32 | 實際 BIN 最後4 bytes | 實際 BIN 最後4 bytes |

### CRC 類型、計算範圍與用途

| 名稱 | 存放／傳送位置 | 計算範圍 |
| --- | --- | --- |
| Image CRC32 | BIN最後4 bytes／LE32 | BIN[0..image_size-5]，含跳轉表、metadata、reserved及填洞FF；排除CRC自身 |
| Metadata staging CRC32 | CAN SEAL或Host BEGIN的command payload | 完整metadata 256 bytes；不是多佔用一組metadata內的CRC欄位 |
| CAN block CRC32 | BLOCK_BEGIN及BLOCK_COMMIT的Byte4..7 | 本區塊實際image bytes，最多64；不含control header或未傳送padding |
| Custom Transfer CRC8 | 固定8-byte payload的Byte7 | 該Transfer封包Byte0..6；不是CAN Upgrade的固定Byte7規則 |
| CAN控制器鏈路CRC | CAN frame硬體協定欄位 | 由CAN控制器處理，不佔本文件Byte0..7的payload |
| Host Link CRC16 | UART frame的header CRC／payload CRC | CRC16/CCITT-FALSE；header覆蓋Byte2..9，payload CRC只覆蓋UART payload，不是image CRC |
| Intel HEX／S-record checksum | HEX／MOT每筆文字record | 燒錄檔record完整性；不是App image CRC32 |

Image／metadata／block採CRC32/ISO-HDLC，reflected polynomial0xEDB88320，init及xorout0xFFFFFFFF。
CRC提供完整性，不是簽章、認證或防回滾。image_size隨linker結果改變，所以CRC實際address必須重新計算。

<a id="image-crc-linear-address"></a>

### CRC 的連續 Flash 位址

Boot 在 END 與啟動判斷時，依 metadata 的 `image_size` 讀取整個 App 映像並計算 CRC32。
讀取範圍可以跨越多個 64 KiB 區域；末端四個 CRC bytes 不參與計算。

| 範例映像 | 映像 Flash 範圍 | CRC32 儲存位址 |
| --- | --- | --- |
| App 24 KiB | `0x02000..0x07FFF` | `0x07FFC..0x07FFF` |
| App 56 KiB | `0x02000..0x0FFFF` | `0x0FFFC..0x0FFFF` |
| App 119 KiB | `0x02000..0x1FBFF` | `0x1FBFC..0x1FBFF` |
| App 247 KiB | `0x02000..0x3FBFF` | `0x3FBFC..0x3FBFF` |

表中的 App 起點為 `0x2000`；可用容量仍由各工程的 Flash 配置決定。
滿容量 120／248 KiB 的 RFP 安裝條件，見 [Flash 尾端保護的重要事項](https://released.github.io/slide_boot_loader_for_RL78/#device-debug-monitor)。

CC-RL 的 `__far` 指標加法只更新低 16 位。
連續讀取使用 32-bit 整數位址運算，再轉回 `__far` 指標，讓 `0x0FFFF` 的下一個 byte 為 `0x10000`。
此規則也適用於後續的 `0x1FFFF`、`0x2FFFF` 邊界。
來源為 [CC-RL 記憶體配置與 Pointer operation](https://tool-support.renesas.com/autoupdate/support/onlinehelp/csp/V8.15.00/CS%2B.chm/Compiler-CCRL.chm/Output/ccrl04c0206y0003.html)。

各 Boot 工程的 `sw_crc32.c` 以 `F13_Crc32Bytes()` 實作上述讀取及 CRC 運算，
`caculate_crc32_checksum()` 提供 Flash 起點／長度入口。
移植時一併核對目標編譯器的整數寬度、指標運算與可讀 Flash 範圍。
實板驗證可使用[各 App 的測試 BIN 產生流程](https://released.github.io/slide_boot_loader_for_RL78/#device-test-images)，
分別檢查跨界映像的 END CRC 與重啟後 APP_READY；離線 CRC 測試不代替 Flash 擦寫驗證。

## 2. 每個metadata byte：address、範例值與來源

下表所有offset均相對metadata_base；address／offset以0x標示，value欄是兩位十六進位byte，bytes欄長度為十進位。
「產生端來源」對照下一節的範例程式連結；欄位後[0]／[1]等表示該欄位內的byte。
產生來源為各 App 的 `ftable.inc`；F13 由 `ftable_RL78_F13.asm` 組譯，F24 由 `ftable_RL78_F24.asm` 組譯。
兩者的 App 身分由各自的 C header 提供，固定欄位來自各自 Boot 契約。

<!-- METADATA_BYTES_BEGIN -->
### MCU CAN device：Metadata 欄位與產生端

| Metadata offset | bytes | 欄位 | 產生端來源符號／位置 |
| --- | --- | --- | --- |
| 0x00..0x03 | 4 | image_magic (ASCII CAN\0) | IMAGE_MANIFEST_MAGIC |
| 0x04..0x04 | 1 | image_format | IMAGE_MANIFEST_FORMAT_INFO |
| 0x05..0x05 | 1 | core_length | IMAGE_MANIFEST_FORMAT_INFO |
| 0x06..0x07 | 2 | flags | IMAGE_MANIFEST_FORMAT_INFO |
| 0x08..0x09 | 2 | protocol_id | IMAGE_MANIFEST_PROTOCOL |
| 0x0A..0x0A | 1 | protocol_version | IMAGE_MANIFEST_PROTOCOL |
| 0x0B..0x0B | 1 | checksum_type | IMAGE_MANIFEST_PROTOCOL |
| 0x0C..0x0D | 2 | target_id | IMAGE_MANIFEST_TARGET |
| 0x0E..0x0E | 1 | can_mode_mask | IMAGE_MANIFEST_TARGET |
| 0x0F..0x0F | 1 | can_id_format | IMAGE_MANIFEST_TARGET |
| 0x10..0x13 | 4 | app_version | APP_IMAGE_VERSION |
| 0x14..0x17 | 4 | app_build | APP_IMAGE_BUILD |
| 0x18..0x1B | 4 | image_size | IMAGE_SIZE_POST_BUILD / post-build |
| 0x1C..0x1F | 4 | app_start | FLASH_TABLE |
| 0x20..0x23 | 4 | app_capacity | APP_REGION_SIZE |
| 0x24..0x27 | 4 | flash_size | CODE_FLASH_SIZE |
| 0x28..0x2B | 4 | boot_size | BOOT_RESERVED_SIZE |
| 0x2C..0x2F | 4 | erase_size | FLASH_ERASE_BLOCK_SIZE |
| 0x30..0x33 | 4 | nominal_rate_mask | CAN_NOMINAL_BITRATE_MASK |
| 0x34..0x37 | 4 | data_rate_mask | CAN_DATA_BITRATE_MASK |
| 0x38..0x3B | 4 | request_id | CAN_REQUEST_ID |
| 0x3C..0x3F | 4 | response_id | CAN_RESPONSE_ID |
| 0x40..0x4F | 16 | mcu_part ASCII | MCU_PART_0..1 / zero padding |
| 0x50..0x5B | 12 | mcu_family ASCII | MCU_FAMILY_0..1 / zero padding |
| 0x5C..0x5F | 4 | minimum_size | MINIMUM_IMAGE_SIZE |
| 0x60..0x63 | 4 | UPD1 magic | UPD1 policy |
| 0x64..0x64 | 1 | policy_version | UPD1 policy |
| 0x65..0x65 | 1 | policy_size | UPD1 policy |
| 0x66..0x66 | 1 | image_role | UPD1 policy |
| 0x67..0x67 | 1 | update_transports | UPD1 policy |
| 0x68..0x6B | 4 | irq_abi | UPD1 policy |
| 0x6C..0x6F | 4 | minimum_boot | UPD1 policy |
| 0x70..0x73 | 4 | device_uart_baud | UPD1 policy |
| 0x74..0x77 | 4 | version_control | APP_IMAGE_VERSION_CONTROL |
| 0x78..0x7F | 8 | reserved_zero | UPD1 policy |
| 0x80..0xFF | 128 | reserved_FF | reserved region |

F13 的來源符號由 ftable.inc 產生；F24 的相同欄位由 device_common.ps1 的 Get-DeviceMetadata 依 App C header／Boot config 產生。

### 逐 byte 實體位址與範例值

方括號是欄位內byte索引；LE數值的[0]是最低有效byte。ASCII依字元順序，reserved依原始順序。
範例值取配套BIN，不是所有專案的固定值；每個metadata byte皆各列一行，包含128個reserved FF。
#### Metadata 0x00..0x1F
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0x00 | 0x02100 | 43 | image_magic (ASCII CAN\0)[0] | 0x02100 | 43 | image_magic (ASCII CAN\0)[0] |
| 0x01 | 0x02101 | 41 | image_magic (ASCII CAN\0)[1] | 0x02101 | 41 | image_magic (ASCII CAN\0)[1] |
| 0x02 | 0x02102 | 4E | image_magic (ASCII CAN\0)[2] | 0x02102 | 4E | image_magic (ASCII CAN\0)[2] |
| 0x03 | 0x02103 | 00 | image_magic (ASCII CAN\0)[3] | 0x02103 | 00 | image_magic (ASCII CAN\0)[3] |
| 0x04 | 0x02104 | 06 | image_format[0] | 0x02104 | 06 | image_format[0] |
| 0x05 | 0x02105 | 80 | core_length[0] | 0x02105 | 80 | core_length[0] |
| 0x06 | 0x02106 | 03 | flags[0] | 0x02106 | 03 | flags[0] |
| 0x07 | 0x02107 | 00 | flags[1] | 0x02107 | 00 | flags[1] |
| 0x08 | 0x02108 | 01 | protocol_id[0] | 0x02108 | 01 | protocol_id[0] |
| 0x09 | 0x02109 | 00 | protocol_id[1] | 0x02109 | 00 | protocol_id[1] |
| 0x0A | 0x0210A | 05 | protocol_version[0] | 0x0210A | 05 | protocol_version[0] |
| 0x0B | 0x0210B | 01 | checksum_type[0] | 0x0210B | 01 | checksum_type[0] |
| 0x0C | 0x0210C | 3B | target_id[0] | 0x0210C | 4B | target_id[0] |
| 0x0D | 0x0210D | F1 | target_id[1] | 0x0210D | F2 | target_id[1] |
| 0x0E | 0x0210E | 01 | can_mode_mask[0] | 0x0210E | 01 | can_mode_mask[0] |
| 0x0F | 0x0210F | 00 | can_id_format[0] | 0x0210F | 00 | can_id_format[0] |
| 0x10 | 0x02110 | 01 | app_version[0] | 0x02110 | 03 | app_version[0] |
| 0x11 | 0x02111 | 06 | app_version[1] | 0x02111 | 00 | app_version[1] |
| 0x12 | 0x02112 | 01 | app_version[2] | 0x02112 | 01 | app_version[2] |
| 0x13 | 0x02113 | 00 | app_version[3] | 0x02113 | 00 | app_version[3] |
| 0x14 | 0x02114 | 99 | app_build[0] | 0x02114 | 9B | app_build[0] |
| 0x15 | 0x02115 | 28 | app_build[1] | 0x02115 | 28 | app_build[1] |
| 0x16 | 0x02116 | 35 | app_build[2] | 0x02116 | 35 | app_build[2] |
| 0x17 | 0x02117 | 01 | app_build[3] | 0x02117 | 01 | app_build[3] |
| 0x18 | 0x02118 | 54 | image_size[0] | 0x02118 | 80 | image_size[0] |
| 0x19 | 0x02119 | 4F | image_size[1] | 0x02119 | 10 | image_size[1] |
| 0x1A | 0x0211A | 00 | image_size[2] | 0x0211A | 00 | image_size[2] |
| 0x1B | 0x0211B | 00 | image_size[3] | 0x0211B | 00 | image_size[3] |
| 0x1C | 0x0211C | 00 | app_start[0] | 0x0211C | 00 | app_start[0] |
| 0x1D | 0x0211D | 20 | app_start[1] | 0x0211D | 20 | app_start[1] |
| 0x1E | 0x0211E | 00 | app_start[2] | 0x0211E | 00 | app_start[2] |
| 0x1F | 0x0211F | 00 | app_start[3] | 0x0211F | 00 | app_start[3] |
#### Metadata 0x20..0x3F
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0x20 | 0x02120 | 00 | app_capacity[0] | 0x02120 | 00 | app_capacity[0] |
| 0x21 | 0x02121 | DC | app_capacity[1] | 0x02121 | DC | app_capacity[1] |
| 0x22 | 0x02122 | 01 | app_capacity[2] | 0x02122 | 03 | app_capacity[2] |
| 0x23 | 0x02123 | 00 | app_capacity[3] | 0x02123 | 00 | app_capacity[3] |
| 0x24 | 0x02124 | 00 | flash_size[0] | 0x02124 | 00 | flash_size[0] |
| 0x25 | 0x02125 | 00 | flash_size[1] | 0x02125 | 00 | flash_size[1] |
| 0x26 | 0x02126 | 02 | flash_size[2] | 0x02126 | 04 | flash_size[2] |
| 0x27 | 0x02127 | 00 | flash_size[3] | 0x02127 | 00 | flash_size[3] |
| 0x28 | 0x02128 | 00 | boot_size[0] | 0x02128 | 00 | boot_size[0] |
| 0x29 | 0x02129 | 20 | boot_size[1] | 0x02129 | 20 | boot_size[1] |
| 0x2A | 0x0212A | 00 | boot_size[2] | 0x0212A | 00 | boot_size[2] |
| 0x2B | 0x0212B | 00 | boot_size[3] | 0x0212B | 00 | boot_size[3] |
| 0x2C | 0x0212C | 00 | erase_size[0] | 0x0212C | 00 | erase_size[0] |
| 0x2D | 0x0212D | 04 | erase_size[1] | 0x0212D | 04 | erase_size[1] |
| 0x2E | 0x0212E | 00 | erase_size[2] | 0x0212E | 00 | erase_size[2] |
| 0x2F | 0x0212F | 00 | erase_size[3] | 0x0212F | 00 | erase_size[3] |
| 0x30 | 0x02130 | 04 | nominal_rate_mask[0] | 0x02130 | 04 | nominal_rate_mask[0] |
| 0x31 | 0x02131 | 00 | nominal_rate_mask[1] | 0x02131 | 00 | nominal_rate_mask[1] |
| 0x32 | 0x02132 | 00 | nominal_rate_mask[2] | 0x02132 | 00 | nominal_rate_mask[2] |
| 0x33 | 0x02133 | 00 | nominal_rate_mask[3] | 0x02133 | 00 | nominal_rate_mask[3] |
| 0x34 | 0x02134 | 00 | data_rate_mask[0] | 0x02134 | 00 | data_rate_mask[0] |
| 0x35 | 0x02135 | 00 | data_rate_mask[1] | 0x02135 | 00 | data_rate_mask[1] |
| 0x36 | 0x02136 | 00 | data_rate_mask[2] | 0x02136 | 00 | data_rate_mask[2] |
| 0x37 | 0x02137 | 00 | data_rate_mask[3] | 0x02137 | 00 | data_rate_mask[3] |
| 0x38 | 0x02138 | 00 | request_id[0] | 0x02138 | 00 | request_id[0] |
| 0x39 | 0x02139 | 07 | request_id[1] | 0x02139 | 07 | request_id[1] |
| 0x3A | 0x0213A | 00 | request_id[2] | 0x0213A | 00 | request_id[2] |
| 0x3B | 0x0213B | 00 | request_id[3] | 0x0213B | 00 | request_id[3] |
| 0x3C | 0x0213C | 01 | response_id[0] | 0x0213C | 01 | response_id[0] |
| 0x3D | 0x0213D | 07 | response_id[1] | 0x0213D | 07 | response_id[1] |
| 0x3E | 0x0213E | 00 | response_id[2] | 0x0213E | 00 | response_id[2] |
| 0x3F | 0x0213F | 00 | response_id[3] | 0x0213F | 00 | response_id[3] |
#### Metadata 0x40..0x5F
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0x40 | 0x02140 | 52 | mcu_part ASCII[0] | 0x02140 | 52 | mcu_part ASCII[0] |
| 0x41 | 0x02141 | 35 | mcu_part ASCII[1] | 0x02141 | 37 | mcu_part ASCII[1] |
| 0x42 | 0x02142 | 46 | mcu_part ASCII[2] | 0x02142 | 46 | mcu_part ASCII[2] |
| 0x43 | 0x02143 | 31 | mcu_part ASCII[3] | 0x02143 | 31 | mcu_part ASCII[3] |
| 0x44 | 0x02144 | 30 | mcu_part ASCII[4] | 0x02144 | 32 | mcu_part ASCII[4] |
| 0x45 | 0x02145 | 42 | mcu_part ASCII[5] | 0x02145 | 34 | mcu_part ASCII[5] |
| 0x46 | 0x02146 | 4D | mcu_part ASCII[6] | 0x02146 | 46 | mcu_part ASCII[6] |
| 0x47 | 0x02147 | 47 | mcu_part ASCII[7] | 0x02147 | 50 | mcu_part ASCII[7] |
| 0x48 | 0x02148 | 00 | mcu_part ASCII[8] | 0x02148 | 4A | mcu_part ASCII[8] |
| 0x49 | 0x02149 | 00 | mcu_part ASCII[9] | 0x02149 | 35 | mcu_part ASCII[9] |
| 0x4A | 0x0214A | 00 | mcu_part ASCII[10] | 0x0214A | 78 | mcu_part ASCII[10] |
| 0x4B | 0x0214B | 00 | mcu_part ASCII[11] | 0x0214B | 46 | mcu_part ASCII[11] |
| 0x4C | 0x0214C | 00 | mcu_part ASCII[12] | 0x0214C | 42 | mcu_part ASCII[12] |
| 0x4D | 0x0214D | 00 | mcu_part ASCII[13] | 0x0214D | 00 | mcu_part ASCII[13] |
| 0x4E | 0x0214E | 00 | mcu_part ASCII[14] | 0x0214E | 00 | mcu_part ASCII[14] |
| 0x4F | 0x0214F | 00 | mcu_part ASCII[15] | 0x0214F | 00 | mcu_part ASCII[15] |
| 0x50 | 0x02150 | 52 | mcu_family ASCII[0] | 0x02150 | 52 | mcu_family ASCII[0] |
| 0x51 | 0x02151 | 4C | mcu_family ASCII[1] | 0x02151 | 4C | mcu_family ASCII[1] |
| 0x52 | 0x02152 | 37 | mcu_family ASCII[2] | 0x02152 | 37 | mcu_family ASCII[2] |
| 0x53 | 0x02153 | 38 | mcu_family ASCII[3] | 0x02153 | 38 | mcu_family ASCII[3] |
| 0x54 | 0x02154 | 2F | mcu_family ASCII[4] | 0x02154 | 2F | mcu_family ASCII[4] |
| 0x55 | 0x02155 | 46 | mcu_family ASCII[5] | 0x02155 | 46 | mcu_family ASCII[5] |
| 0x56 | 0x02156 | 31 | mcu_family ASCII[6] | 0x02156 | 32 | mcu_family ASCII[6] |
| 0x57 | 0x02157 | 33 | mcu_family ASCII[7] | 0x02157 | 34 | mcu_family ASCII[7] |
| 0x58 | 0x02158 | 00 | mcu_family ASCII[8] | 0x02158 | 00 | mcu_family ASCII[8] |
| 0x59 | 0x02159 | 00 | mcu_family ASCII[9] | 0x02159 | 00 | mcu_family ASCII[9] |
| 0x5A | 0x0215A | 00 | mcu_family ASCII[10] | 0x0215A | 00 | mcu_family ASCII[10] |
| 0x5B | 0x0215B | 00 | mcu_family ASCII[11] | 0x0215B | 00 | mcu_family ASCII[11] |
| 0x5C | 0x0215C | 04 | minimum_size[0] | 0x0215C | 04 | minimum_size[0] |
| 0x5D | 0x0215D | 02 | minimum_size[1] | 0x0215D | 02 | minimum_size[1] |
| 0x5E | 0x0215E | 00 | minimum_size[2] | 0x0215E | 00 | minimum_size[2] |
| 0x5F | 0x0215F | 00 | minimum_size[3] | 0x0215F | 00 | minimum_size[3] |
#### Metadata 0x60..0x7F
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0x60 | 0x02160 | 55 | UPD1 magic[0] | 0x02160 | 55 | UPD1 magic[0] |
| 0x61 | 0x02161 | 50 | UPD1 magic[1] | 0x02161 | 50 | UPD1 magic[1] |
| 0x62 | 0x02162 | 44 | UPD1 magic[2] | 0x02162 | 44 | UPD1 magic[2] |
| 0x63 | 0x02163 | 31 | UPD1 magic[3] | 0x02163 | 31 | UPD1 magic[3] |
| 0x64 | 0x02164 | 03 | policy_version[0] | 0x02164 | 03 | policy_version[0] |
| 0x65 | 0x02165 | 20 | policy_size[0] | 0x02165 | 20 | policy_size[0] |
| 0x66 | 0x02166 | 01 | image_role[0] | 0x02166 | 01 | image_role[0] |
| 0x67 | 0x02167 | 01 | update_transports[0] | 0x02167 | 01 | update_transports[0] |
| 0x68 | 0x02168 | 46 | irq_abi[0] | 0x02168 | 46 | irq_abi[0] |
| 0x69 | 0x02169 | 31 | irq_abi[1] | 0x02169 | 32 | irq_abi[1] |
| 0x6A | 0x0216A | 56 | irq_abi[2] | 0x0216A | 56 | irq_abi[2] |
| 0x6B | 0x0216B | 31 | irq_abi[3] | 0x0216B | 31 | irq_abi[3] |
| 0x6C | 0x0216C | 02 | minimum_boot[0] | 0x0216C | 01 | minimum_boot[0] |
| 0x6D | 0x0216D | 07 | minimum_boot[1] | 0x0216D | 01 | minimum_boot[1] |
| 0x6E | 0x0216E | 01 | minimum_boot[2] | 0x0216E | 01 | minimum_boot[2] |
| 0x6F | 0x0216F | 00 | minimum_boot[3] | 0x0216F | 00 | minimum_boot[3] |
| 0x70 | 0x02170 | 00 | device_uart_baud[0] | 0x02170 | 00 | device_uart_baud[0] |
| 0x71 | 0x02171 | 00 | device_uart_baud[1] | 0x02171 | 00 | device_uart_baud[1] |
| 0x72 | 0x02172 | 00 | device_uart_baud[2] | 0x02172 | 00 | device_uart_baud[2] |
| 0x73 | 0x02173 | 00 | device_uart_baud[3] | 0x02173 | 00 | device_uart_baud[3] |
| 0x74 | 0x02174 | 00 | version_control[0] | 0x02174 | 00 | version_control[0] |
| 0x75 | 0x02175 | 00 | version_control[1] | 0x02175 | 00 | version_control[1] |
| 0x76 | 0x02176 | 00 | version_control[2] | 0x02176 | 00 | version_control[2] |
| 0x77 | 0x02177 | 00 | version_control[3] | 0x02177 | 00 | version_control[3] |
| 0x78 | 0x02178 | 00 | reserved_zero[0] | 0x02178 | 00 | reserved_zero[0] |
| 0x79 | 0x02179 | 00 | reserved_zero[1] | 0x02179 | 00 | reserved_zero[1] |
| 0x7A | 0x0217A | 00 | reserved_zero[2] | 0x0217A | 00 | reserved_zero[2] |
| 0x7B | 0x0217B | 00 | reserved_zero[3] | 0x0217B | 00 | reserved_zero[3] |
| 0x7C | 0x0217C | 00 | reserved_zero[4] | 0x0217C | 00 | reserved_zero[4] |
| 0x7D | 0x0217D | 00 | reserved_zero[5] | 0x0217D | 00 | reserved_zero[5] |
| 0x7E | 0x0217E | 00 | reserved_zero[6] | 0x0217E | 00 | reserved_zero[6] |
| 0x7F | 0x0217F | 00 | reserved_zero[7] | 0x0217F | 00 | reserved_zero[7] |
#### Metadata 0x80..0x9F
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0x80 | 0x02180 | FF | reserved_FF[0] | 0x02180 | FF | reserved_FF[0] |
| 0x81 | 0x02181 | FF | reserved_FF[1] | 0x02181 | FF | reserved_FF[1] |
| 0x82 | 0x02182 | FF | reserved_FF[2] | 0x02182 | FF | reserved_FF[2] |
| 0x83 | 0x02183 | FF | reserved_FF[3] | 0x02183 | FF | reserved_FF[3] |
| 0x84 | 0x02184 | FF | reserved_FF[4] | 0x02184 | FF | reserved_FF[4] |
| 0x85 | 0x02185 | FF | reserved_FF[5] | 0x02185 | FF | reserved_FF[5] |
| 0x86 | 0x02186 | FF | reserved_FF[6] | 0x02186 | FF | reserved_FF[6] |
| 0x87 | 0x02187 | FF | reserved_FF[7] | 0x02187 | FF | reserved_FF[7] |
| 0x88 | 0x02188 | FF | reserved_FF[8] | 0x02188 | FF | reserved_FF[8] |
| 0x89 | 0x02189 | FF | reserved_FF[9] | 0x02189 | FF | reserved_FF[9] |
| 0x8A | 0x0218A | FF | reserved_FF[10] | 0x0218A | FF | reserved_FF[10] |
| 0x8B | 0x0218B | FF | reserved_FF[11] | 0x0218B | FF | reserved_FF[11] |
| 0x8C | 0x0218C | FF | reserved_FF[12] | 0x0218C | FF | reserved_FF[12] |
| 0x8D | 0x0218D | FF | reserved_FF[13] | 0x0218D | FF | reserved_FF[13] |
| 0x8E | 0x0218E | FF | reserved_FF[14] | 0x0218E | FF | reserved_FF[14] |
| 0x8F | 0x0218F | FF | reserved_FF[15] | 0x0218F | FF | reserved_FF[15] |
| 0x90 | 0x02190 | FF | reserved_FF[16] | 0x02190 | FF | reserved_FF[16] |
| 0x91 | 0x02191 | FF | reserved_FF[17] | 0x02191 | FF | reserved_FF[17] |
| 0x92 | 0x02192 | FF | reserved_FF[18] | 0x02192 | FF | reserved_FF[18] |
| 0x93 | 0x02193 | FF | reserved_FF[19] | 0x02193 | FF | reserved_FF[19] |
| 0x94 | 0x02194 | FF | reserved_FF[20] | 0x02194 | FF | reserved_FF[20] |
| 0x95 | 0x02195 | FF | reserved_FF[21] | 0x02195 | FF | reserved_FF[21] |
| 0x96 | 0x02196 | FF | reserved_FF[22] | 0x02196 | FF | reserved_FF[22] |
| 0x97 | 0x02197 | FF | reserved_FF[23] | 0x02197 | FF | reserved_FF[23] |
| 0x98 | 0x02198 | FF | reserved_FF[24] | 0x02198 | FF | reserved_FF[24] |
| 0x99 | 0x02199 | FF | reserved_FF[25] | 0x02199 | FF | reserved_FF[25] |
| 0x9A | 0x0219A | FF | reserved_FF[26] | 0x0219A | FF | reserved_FF[26] |
| 0x9B | 0x0219B | FF | reserved_FF[27] | 0x0219B | FF | reserved_FF[27] |
| 0x9C | 0x0219C | FF | reserved_FF[28] | 0x0219C | FF | reserved_FF[28] |
| 0x9D | 0x0219D | FF | reserved_FF[29] | 0x0219D | FF | reserved_FF[29] |
| 0x9E | 0x0219E | FF | reserved_FF[30] | 0x0219E | FF | reserved_FF[30] |
| 0x9F | 0x0219F | FF | reserved_FF[31] | 0x0219F | FF | reserved_FF[31] |
#### Metadata 0xA0..0xBF
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0xA0 | 0x021A0 | FF | reserved_FF[32] | 0x021A0 | FF | reserved_FF[32] |
| 0xA1 | 0x021A1 | FF | reserved_FF[33] | 0x021A1 | FF | reserved_FF[33] |
| 0xA2 | 0x021A2 | FF | reserved_FF[34] | 0x021A2 | FF | reserved_FF[34] |
| 0xA3 | 0x021A3 | FF | reserved_FF[35] | 0x021A3 | FF | reserved_FF[35] |
| 0xA4 | 0x021A4 | FF | reserved_FF[36] | 0x021A4 | FF | reserved_FF[36] |
| 0xA5 | 0x021A5 | FF | reserved_FF[37] | 0x021A5 | FF | reserved_FF[37] |
| 0xA6 | 0x021A6 | FF | reserved_FF[38] | 0x021A6 | FF | reserved_FF[38] |
| 0xA7 | 0x021A7 | FF | reserved_FF[39] | 0x021A7 | FF | reserved_FF[39] |
| 0xA8 | 0x021A8 | FF | reserved_FF[40] | 0x021A8 | FF | reserved_FF[40] |
| 0xA9 | 0x021A9 | FF | reserved_FF[41] | 0x021A9 | FF | reserved_FF[41] |
| 0xAA | 0x021AA | FF | reserved_FF[42] | 0x021AA | FF | reserved_FF[42] |
| 0xAB | 0x021AB | FF | reserved_FF[43] | 0x021AB | FF | reserved_FF[43] |
| 0xAC | 0x021AC | FF | reserved_FF[44] | 0x021AC | FF | reserved_FF[44] |
| 0xAD | 0x021AD | FF | reserved_FF[45] | 0x021AD | FF | reserved_FF[45] |
| 0xAE | 0x021AE | FF | reserved_FF[46] | 0x021AE | FF | reserved_FF[46] |
| 0xAF | 0x021AF | FF | reserved_FF[47] | 0x021AF | FF | reserved_FF[47] |
| 0xB0 | 0x021B0 | FF | reserved_FF[48] | 0x021B0 | FF | reserved_FF[48] |
| 0xB1 | 0x021B1 | FF | reserved_FF[49] | 0x021B1 | FF | reserved_FF[49] |
| 0xB2 | 0x021B2 | FF | reserved_FF[50] | 0x021B2 | FF | reserved_FF[50] |
| 0xB3 | 0x021B3 | FF | reserved_FF[51] | 0x021B3 | FF | reserved_FF[51] |
| 0xB4 | 0x021B4 | FF | reserved_FF[52] | 0x021B4 | FF | reserved_FF[52] |
| 0xB5 | 0x021B5 | FF | reserved_FF[53] | 0x021B5 | FF | reserved_FF[53] |
| 0xB6 | 0x021B6 | FF | reserved_FF[54] | 0x021B6 | FF | reserved_FF[54] |
| 0xB7 | 0x021B7 | FF | reserved_FF[55] | 0x021B7 | FF | reserved_FF[55] |
| 0xB8 | 0x021B8 | FF | reserved_FF[56] | 0x021B8 | FF | reserved_FF[56] |
| 0xB9 | 0x021B9 | FF | reserved_FF[57] | 0x021B9 | FF | reserved_FF[57] |
| 0xBA | 0x021BA | FF | reserved_FF[58] | 0x021BA | FF | reserved_FF[58] |
| 0xBB | 0x021BB | FF | reserved_FF[59] | 0x021BB | FF | reserved_FF[59] |
| 0xBC | 0x021BC | FF | reserved_FF[60] | 0x021BC | FF | reserved_FF[60] |
| 0xBD | 0x021BD | FF | reserved_FF[61] | 0x021BD | FF | reserved_FF[61] |
| 0xBE | 0x021BE | FF | reserved_FF[62] | 0x021BE | FF | reserved_FF[62] |
| 0xBF | 0x021BF | FF | reserved_FF[63] | 0x021BF | FF | reserved_FF[63] |
#### Metadata 0xC0..0xDF
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0xC0 | 0x021C0 | FF | reserved_FF[64] | 0x021C0 | FF | reserved_FF[64] |
| 0xC1 | 0x021C1 | FF | reserved_FF[65] | 0x021C1 | FF | reserved_FF[65] |
| 0xC2 | 0x021C2 | FF | reserved_FF[66] | 0x021C2 | FF | reserved_FF[66] |
| 0xC3 | 0x021C3 | FF | reserved_FF[67] | 0x021C3 | FF | reserved_FF[67] |
| 0xC4 | 0x021C4 | FF | reserved_FF[68] | 0x021C4 | FF | reserved_FF[68] |
| 0xC5 | 0x021C5 | FF | reserved_FF[69] | 0x021C5 | FF | reserved_FF[69] |
| 0xC6 | 0x021C6 | FF | reserved_FF[70] | 0x021C6 | FF | reserved_FF[70] |
| 0xC7 | 0x021C7 | FF | reserved_FF[71] | 0x021C7 | FF | reserved_FF[71] |
| 0xC8 | 0x021C8 | FF | reserved_FF[72] | 0x021C8 | FF | reserved_FF[72] |
| 0xC9 | 0x021C9 | FF | reserved_FF[73] | 0x021C9 | FF | reserved_FF[73] |
| 0xCA | 0x021CA | FF | reserved_FF[74] | 0x021CA | FF | reserved_FF[74] |
| 0xCB | 0x021CB | FF | reserved_FF[75] | 0x021CB | FF | reserved_FF[75] |
| 0xCC | 0x021CC | FF | reserved_FF[76] | 0x021CC | FF | reserved_FF[76] |
| 0xCD | 0x021CD | FF | reserved_FF[77] | 0x021CD | FF | reserved_FF[77] |
| 0xCE | 0x021CE | FF | reserved_FF[78] | 0x021CE | FF | reserved_FF[78] |
| 0xCF | 0x021CF | FF | reserved_FF[79] | 0x021CF | FF | reserved_FF[79] |
| 0xD0 | 0x021D0 | FF | reserved_FF[80] | 0x021D0 | FF | reserved_FF[80] |
| 0xD1 | 0x021D1 | FF | reserved_FF[81] | 0x021D1 | FF | reserved_FF[81] |
| 0xD2 | 0x021D2 | FF | reserved_FF[82] | 0x021D2 | FF | reserved_FF[82] |
| 0xD3 | 0x021D3 | FF | reserved_FF[83] | 0x021D3 | FF | reserved_FF[83] |
| 0xD4 | 0x021D4 | FF | reserved_FF[84] | 0x021D4 | FF | reserved_FF[84] |
| 0xD5 | 0x021D5 | FF | reserved_FF[85] | 0x021D5 | FF | reserved_FF[85] |
| 0xD6 | 0x021D6 | FF | reserved_FF[86] | 0x021D6 | FF | reserved_FF[86] |
| 0xD7 | 0x021D7 | FF | reserved_FF[87] | 0x021D7 | FF | reserved_FF[87] |
| 0xD8 | 0x021D8 | FF | reserved_FF[88] | 0x021D8 | FF | reserved_FF[88] |
| 0xD9 | 0x021D9 | FF | reserved_FF[89] | 0x021D9 | FF | reserved_FF[89] |
| 0xDA | 0x021DA | FF | reserved_FF[90] | 0x021DA | FF | reserved_FF[90] |
| 0xDB | 0x021DB | FF | reserved_FF[91] | 0x021DB | FF | reserved_FF[91] |
| 0xDC | 0x021DC | FF | reserved_FF[92] | 0x021DC | FF | reserved_FF[92] |
| 0xDD | 0x021DD | FF | reserved_FF[93] | 0x021DD | FF | reserved_FF[93] |
| 0xDE | 0x021DE | FF | reserved_FF[94] | 0x021DE | FF | reserved_FF[94] |
| 0xDF | 0x021DF | FF | reserved_FF[95] | 0x021DF | FF | reserved_FF[95] |
#### Metadata 0xE0..0xFF
| offset | F13 device address | value | F13欄位[byte] | F24 device address | value | F24欄位[byte] |
| --- | --- | --- | --- | --- | --- | --- |
| 0xE0 | 0x021E0 | FF | reserved_FF[96] | 0x021E0 | FF | reserved_FF[96] |
| 0xE1 | 0x021E1 | FF | reserved_FF[97] | 0x021E1 | FF | reserved_FF[97] |
| 0xE2 | 0x021E2 | FF | reserved_FF[98] | 0x021E2 | FF | reserved_FF[98] |
| 0xE3 | 0x021E3 | FF | reserved_FF[99] | 0x021E3 | FF | reserved_FF[99] |
| 0xE4 | 0x021E4 | FF | reserved_FF[100] | 0x021E4 | FF | reserved_FF[100] |
| 0xE5 | 0x021E5 | FF | reserved_FF[101] | 0x021E5 | FF | reserved_FF[101] |
| 0xE6 | 0x021E6 | FF | reserved_FF[102] | 0x021E6 | FF | reserved_FF[102] |
| 0xE7 | 0x021E7 | FF | reserved_FF[103] | 0x021E7 | FF | reserved_FF[103] |
| 0xE8 | 0x021E8 | FF | reserved_FF[104] | 0x021E8 | FF | reserved_FF[104] |
| 0xE9 | 0x021E9 | FF | reserved_FF[105] | 0x021E9 | FF | reserved_FF[105] |
| 0xEA | 0x021EA | FF | reserved_FF[106] | 0x021EA | FF | reserved_FF[106] |
| 0xEB | 0x021EB | FF | reserved_FF[107] | 0x021EB | FF | reserved_FF[107] |
| 0xEC | 0x021EC | FF | reserved_FF[108] | 0x021EC | FF | reserved_FF[108] |
| 0xED | 0x021ED | FF | reserved_FF[109] | 0x021ED | FF | reserved_FF[109] |
| 0xEE | 0x021EE | FF | reserved_FF[110] | 0x021EE | FF | reserved_FF[110] |
| 0xEF | 0x021EF | FF | reserved_FF[111] | 0x021EF | FF | reserved_FF[111] |
| 0xF0 | 0x021F0 | FF | reserved_FF[112] | 0x021F0 | FF | reserved_FF[112] |
| 0xF1 | 0x021F1 | FF | reserved_FF[113] | 0x021F1 | FF | reserved_FF[113] |
| 0xF2 | 0x021F2 | FF | reserved_FF[114] | 0x021F2 | FF | reserved_FF[114] |
| 0xF3 | 0x021F3 | FF | reserved_FF[115] | 0x021F3 | FF | reserved_FF[115] |
| 0xF4 | 0x021F4 | FF | reserved_FF[116] | 0x021F4 | FF | reserved_FF[116] |
| 0xF5 | 0x021F5 | FF | reserved_FF[117] | 0x021F5 | FF | reserved_FF[117] |
| 0xF6 | 0x021F6 | FF | reserved_FF[118] | 0x021F6 | FF | reserved_FF[118] |
| 0xF7 | 0x021F7 | FF | reserved_FF[119] | 0x021F7 | FF | reserved_FF[119] |
| 0xF8 | 0x021F8 | FF | reserved_FF[120] | 0x021F8 | FF | reserved_FF[120] |
| 0xF9 | 0x021F9 | FF | reserved_FF[121] | 0x021F9 | FF | reserved_FF[121] |
| 0xFA | 0x021FA | FF | reserved_FF[122] | 0x021FA | FF | reserved_FF[122] |
| 0xFB | 0x021FB | FF | reserved_FF[123] | 0x021FB | FF | reserved_FF[123] |
| 0xFC | 0x021FC | FF | reserved_FF[124] | 0x021FC | FF | reserved_FF[124] |
| 0xFD | 0x021FD | FF | reserved_FF[125] | 0x021FD | FF | reserved_FF[125] |
| 0xFE | 0x021FE | FF | reserved_FF[126] | 0x021FE | FF | reserved_FF[126] |
| 0xFF | 0x021FF | FF | reserved_FF[127] | 0x021FF | FF | reserved_FF[127] |
### 本表範例BIN與CRC位置
| 項目 | F13 (MCU CAN device) | F24 (MCU CAN device) |
| --- | --- | --- |
| image_size | 0x4F54 | 0x1080 |
| stored image CRC32 | 0x0C297B5E | 0x4837111E |
| CRC32 Flash address | 0x06F50..0x06F53 | 0x0307C..0x0307F |
| metadata staging CRC32 | 0x6305ABC5 | 0x1EFB688C |
F13 device 範例BIN SHA-256：`EBF2B63264968F7D9609C9D99EE4F23DD5AE49F4AB9D15CD4EE2B8FEC136B125`。
F24 device 範例BIN SHA-256：`CD2B4A51038888FF7E35C0C70A250C598BFCBE1A5760530645C5B6F91E36388C`。
<!-- METADATA_BYTES_END -->

### 欄位的語意與修改限制

- core_length=128，metadata 整區為256 bytes；0x80..0xFF 為保留區，依契約全部填FF。
- flags=0x0003、protocol ID／version、checksum type及magic屬於固定契約。
  flags 以完整0x0003比對；調整位元定義時同步產生端與驗證端。
- CAN mode mask的bit0代表Classical；目前F13 id_format=0代表standard。nominal_rate_mask的bit2表示500K，mask不是十進位500000。
- target_id／board_id是邏輯識別；MCU part／family是零結尾、其餘零填補ASCII，不是Flash address。
- image_size是實際封裝BIN含最後4-byte CRC的長度；app_capacity是分區允許的最大容量。
- app_version為0x00MMmmpp，app_build為32-bit建置識別。
  image_size／CRC由post-build依實際建置結果產生。
- UPD1 image_role：1=DEVICE_APP、2=HOST_BRIDGE_APP；update_transports：bit0 CAN、bit1 I2C、bit2 UART。
- irq_abi是固定向量介面的識別，minimum_boot是最低相容Boot版本，不是App最低版本。
- CAN device 的 policy_version=3，device_uart_baud 為0；`version_control` 位於 `0x74..0x77`，其後 `0x78..0x7F` 為0。
  `version_control` 由 App header 產生；`0` 允許任意版本，`1` 由 Boot 在一般 START 限制為同版／新版。
  操作與維護確認見 [Tool 版本政策](https://released.github.io/slide_isp_tool_for_RL78/#force-old-version)。

## 3. 範例程式、產生端與修改位置

| 用途 | 原始碼／位置 | 要如何閱讀或修改 |
| --- | --- | --- |
| F13 metadata生成常數 | [ftable.inc](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/ftable.inc) | 此檔現為生成檔；編輯App的app_image_config.h，由App-mode generator結合Boot contract產生常數；不可手改.inc |
| F13 byte排列／policy | [ftable_RL78_F13.asm](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/ftable_RL78_F13.asm) | .appmeta從APP_MANIFEST_TABLE開始，.DB4依LE放4 bytes；尾128 bytes填FF |
| F13實際size／CRC封裝 | [generate_update_image.ps1](https://github.com/released/RL78_F13_Boot_loader_CAN_app/blob/main/generate_update_image.ps1) | 依map決定結尾、patch image_size、計算尾CRC；ExpectedTargetId等驗證亦須與新專案一致 |
| Device metadata 解碼／驗證 | [Boot 原始碼](https://github.com/released/RL78_F13_Boot_loader_CAN)內的 `image_metadata.c/.h`、`image_metadata_config.h`、`image_metadata_profile.c` | ImageMetadataRead32 解碼 LE32；ImageMetadataValidate 對照 g_image_metadata_contract；完整 API 見 [C 模組移植](https://released.github.io/slide_boot_loader_for_RL78/#device-metadata-parser) |
| CAN metadata 暫存／SEAL | [can_boot_metadata.inc](https://github.com/released/RL78_F13_Boot_loader_CAN/blob/main/can_boot_metadata.inc) | MetadataStage 核對順序／重送；MetadataSeal 呼叫共用驗證並核對 staging CRC，不在 parser 內擦寫 Flash |
| F13 CAN解碼與回覆 | [can_boot_transport.c](https://github.com/released/RL78_F13_Boot_loader_CAN/blob/main/can_boot_transport.c)／[can_boot_block.inc](https://github.com/released/RL78_F13_Boot_loader_CAN/blob/main/can_boot_block.inc) | CAN_BootReceive、CAN_BootSend、BlockBegin／Segment／Check |
| F24 device 契約與封裝 | `image_metadata_config.h`、`can_boot_config.h`、`tools/device_common.ps1`、`tools/package_images.ps1`；[工程入口](https://released.github.io/slide_boot_loader_for_RL78/#f24-can-device) | Get-DeviceMetadata 結合映像／CAN 設定產生欄位，Get-PackagedDeviceApp 核對連結內容與 CRC |
| 共用政策常數 | [image_policy.h](https://github.com/released/simple_renesas_isp_tool/blob/main/firmware/common/image_policy.h) | ROLE／CAN／I2C／UART bits、IRQ ABI、core／policy長度 |
| Tool image解析 | [firmware_update_profile.cpp](https://github.com/released/simple_renesas_isp_tool/blob/main/src/core/firmware_update_profile.cpp) | 檢查BIN、metadata、CRC及目的地 |
| Tool CAN frame編碼 | [f13_boot_profile.cpp](https://github.com/released/simple_renesas_isp_tool/blob/main/src/core/f13_boot_profile.cpp) | BuildStartRequest、BuildBlockRequest、Client::StageMetadata／SendBlock，與下方逐byte表核對 |

### F13組語常數與實際byte的關係

```asm
; Values from the paired F13 CAN example, not a new device configuration.
IMAGE_MANIFEST_FORMAT_INFO .EQU 0x00038006
IMAGE_MANIFEST_PROTOCOL    .EQU 0x01050001
IMAGE_MANIFEST_TARGET      .EQU 0x0001F13B
; .DB4 emits little-endian words:
; metadata 04..07 = 06 80 03 00
; metadata 08..0B = 01 00 05 01
; metadata 0C..0F = 3B F1 01 00
```

例如改 target_id 要核對 Boot metadata header 的 IMAGE_TARGET_ID、App 的 IMAGE_MANIFEST_TARGET、
post-build驗證及Tool live INFO，不是只修改0x0210C。改CAN ID還須保持control／response與raw720..727不重疊。

### C90示例：讀metadata而不依賴struct padding

```c
/* The input is a RAM copy beginning at metadata offset 0x00. */
static unsigned long ReadLe32(const unsigned char *p)
{
    return (unsigned long)p[0] |
           ((unsigned long)p[1] << 8) |
           ((unsigned long)p[2] << 16) |
           ((unsigned long)p[3] << 24);
}

static unsigned long ExampleDeviceAppStart(const unsigned char *metadata)
{
    return ReadLe32(metadata + 0x1C);
}
```

此示例示意 LE 及欄位 offset；完整驗證另核對 magic、format、長度與 CRC。
讀RL78遠端Flash須依實際編譯器的far pointer／讀取API搬到RAM，不能將上例near pointer直接指向所有Flash。
Flash erase／write必須走該MCU的FSL／RFD及保護流程，不能用普通pointer賦值取代。

## 4. CAN payload逐byte格式

Byte0..Byte7指CAN Data payload，不含ID、DLC、CAN硬體CRC／ACK。不是每個command都DLC8。
下表的「-」代表沒有傳送該byte，不是要求補00。所有offset／size／CRC數值皆LE。

### CAN Upgrade：control request（ID0x700）

| Command | DLC | B0 | B1 | B2 | B3 | B4 | B5 | B6 | B7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HELLO | 1 | 01 | - | - | - | - | - | - | - |
| START | 8 | 02 | protocol | target0 | target1 | size0 | size1 | size2 | size3 |
| FORCE_START | 8 | 0E | protocol | target0 | target1 | size0 | size1 | size2 | size3 |
| END | 1 | 04 | - | - | - | - | - | - | - |
| ABORT | 1 | 05 | - | - | - | - | - | - | - |
| ENTER | 1 | 06 | - | - | - | - | - | - | - |
| INFO | 2 | 07 | page | - | - | - | - | - | - |
| METADATA | 8 | 08 | metaOff0 | metaOff1 | 00 | data0 | data1 | data2 | data3 |
| SEAL | 8 | 09 | 00 | 00 | 00 | metaCrc0 | metaCrc1 | metaCrc2 | metaCrc3 |
| METADATA_RESET | 1 | 0A | - | - | - | - | - | - | - |
| BLOCK_BEGIN | 8 | 0B | imageOff0 | imageOff1 | imageOff2 | blockCrc0 | blockCrc1 | blockCrc2 | blockCrc3 |
| BLOCK_COMMIT | 8 | 0C | imageOff0 | imageOff1 | imageOff2 | blockCrc0 | blockCrc1 | blockCrc2 | blockCrc3 |

protocol目前=05；target目前=0xF13B，所以START B2／B3=3B／F1。
App只處理INFO／ENTER；HELLO與更新命令供Boot使用，已在Boot時不需再送ENTER。
本表ID為目前F13範例；Tool仍須依metadata／live INFO核對。raw data base ID與block size由INFO page0x1A宣告，
不在metadata的request_id／response_id欄位內；移植時三組ID不得重疊。
size為整個BIN長度、不是capacity。metaOff相對256-byte metadata；imageOff相對整個BIN、64-byte對齊。
data0..3是本次METADATA chunk的4個原始byte；metaCrc是完整256-byte CRC，blockCrc是本區塊實際長度CRC。
BEGIN與COMMIT必須使用相同imageOff／blockCrc；BEGIN不回ACK，COMMIT驗證並寫入成功才回ACK。

### Raw image frame（ID0x720..0x727）

| Byte | 意義 |
| --- | --- |
| B0 | BIN[imageOff + segment*8 + 0] |
| B1 | BIN[imageOff + segment*8 + 1] |
| B2 | BIN[imageOff + segment*8 + 2] |
| B3 | BIN[imageOff + segment*8 + 3] |
| B4 | BIN[imageOff + segment*8 + 4] |
| B5 | BIN[imageOff + segment*8 + 5] |
| B6 | BIN[imageOff + segment*8 + 6] |
| B7 | BIN[imageOff + segment*8 + 7] |

segment=CAN_ID-0x720，範圍0..7。這8個byte全部是image，不另放command／sequence／CRC8。
最後不足8但仍4-byte對齊時DLC4，只傳B0..B3；未使用byte不寫Flash。raw frame本身不逐筆回覆。

### Response（ID0x701）

| Response | DLC | B0 | B1 | B2 | B3 | B4 | B5 | B6 | B7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HELLO | 8 | 01 | status | protocol | format | target0 | target1 | capKiB0 | capKiB1 |
| INFO | 8 | 07 | status | page | state | value0 | value1 | value2 | value3 |
| ENTER | 2 | 06 | status | - | - | - | - | - | - |
| common ACK／NACK | 8 | echoedCmd | status | detail0 | detail1 | value0 | value1 | value2 | value3 |

status=00為成功，非零必須依command／狀態解讀；例如01 BAD_COMMAND、03 BAD_SEQUENCE、
05 FLASH_ERROR、06 CRC_ERROR、09 BAD_IMAGE。INFO state=1 App、2 Boot；INFO page0的value包含target／protocol／format，
其他page與定義見[CAN協定](https://github.com/released/RL78_F13_Boot_loader_CAN/blob/main/CAN_BOOT_PROTOCOL.md)。

| ACK command | detail（B2..3） | value（B4..7） |
| --- | --- | --- |
| START | 0 | App起點絕對Flash address |
| METADATA_RESET | 0 | 256 |
| METADATA | 下一個metadata offset | 256 |
| SEAL | 256 | 256 |
| BLOCK_COMMIT | (imageOff / 64)低16 bits | 下一個預期Flash絕對address |
| END | (image_size / 4)低16 bits | device計算的完整image CRC32 |
| ABORT | 當前expected image byte offset / 4低16 bits | 當前Flash address；不等於可斷線續傳承諾 |

只讀INFO範例：TX ID0x700／DLC2／`07 00`；Boot正常回ID0x701／DLC8／
`07 00 00 02 3B F1 05 06`，分別是command、OK、page0、Boot state、target LE16、protocol、format。
第一個64-byte block成功的ACK為`0C 00 00 00 40 20 00 00`，最後四byte解為下一個Flash address 0x02040。
ACK範例不是完整燒錄流程；必須先完成live比對、metadata staging／SEAL及START，不能直接拿任意raw frame寫入。

### 與Custom Transfer／Bridge Self Test的區別

| Byte | Transfer request 0x710 | Transfer response 0x711 | Self Test 0x123 |
| --- | --- | --- | --- |
| B0 | A5 magic | 5A magic | 11 |
| B1 | protocol 01 | protocol 01 | 22 |
| B2 | 非零sequence | 對應sequence | 33 |
| B3 | command | 對應command；錯誤為7F | 44 |
| B4 | argument0 | response0 | 55 |
| B5 | argument1 | response1 | 66 |
| B6 | argument2 | response2 | 77 |
| B7 | CRC8(Byte0..6) | CRC8(Byte0..6) | counter，每次Start從00遞增、FF後回00 |

Transfer固定DLC8，CRC8 polynomial07、init00、xorout00、不反射；命令參數見
[Transfer協定](https://github.com/released/simple_renesas_isp_tool/blob/main/docs/F13_TRANSFER_PROTOCOL.md)。
Self Test不是更新協定，也沒有Byte7 CRC；需CAN analyzer觀察實際bus訊號。

## 5. 改成自己的專案：修改順序與驗證

1. 先選定 MCU CAN device 工程，確認硬體手冊的 Flash／RAM 範圍、CAN clock 與實體向量位址。
2. 在 Boot 的 `image_metadata_config.h` 設定分區、target ID 與 IRQ ABI；
   `can_boot_config.h` 設定 CAN IDs／rate，`boot_app_handoff.h` 設定共用 RAM 交接。
   Linker 的 App 起點及向量表／metadata 配置對應同一分區。
3. 在 App 編輯 `app_image_config.h` 與 `app_irq_handlers.h`。
   F13 由 PowerShell 產生 `ftable.inc`；F24 由 `Get-DeviceMetadata` 產生 metadata INC，兩者皆由 App-local pre-build 產表。
4. 建置後核對 map、封裝 BIN 的 metadata／CRC 及所有 BR 目的地。
   App 起點是 link 設定；Tool 的 App Start Override 用於比對，不會重定位 BIN。
5. 在 Tool 載入 BIN，先做離線驗證，再以 Discover 取得 live device 資料。
   更新流程將完整 metadata staging／SEAL 後，才允許進入 START 與區塊寫入。
6. 封裝欄位或契約變動時，一併更新產生器、Boot 驗證、Tool parser 與測試。


<!-- FLASH_REFERENCE_END -->

<a id="uart-i2c-examples"></a>

## UART／I2C 範例入口

UART／I2C 參考工程的分區、startup、向量與 CRC 操作集中於 [UART／I2C 範例](uart_i2c/)。

<a id="target_MCU_flash_type"></a>
<a id="ram_flag"></a>
<a id="FALSH_TABLE"></a>
<a id="ftable_inc"></a>
<a id="map_const"></a>
<a id="boot_main"></a>
<a id="boot_hdwinit"></a>
<a id="fsy_file"></a>
<a id="vect_address"></a>
<a id="vector_table"></a>
<a id="uart／i2c-範例"></a>
<a id="flash-architecture"></a>
<a id="scenario-boot-area-boot-code"></a>
<a id="scenario-flash-area-app-code"></a>
<a id="project-boot-codeapp-code-modifictaion---ftableinc"></a>
<a id="project-boot-code-modifictaion---cstartasm"></a>
<a id="project-boot-code-modifictaion---stkinitasm"></a>
<a id="project-boot-code-modifictaion---project-tree"></a>
<a id="project-boot-code-modifictaion---add-code-flash-library"></a>
<a id="project-boot-code-modifictaion---add-crc-compare-1"></a>
<a id="project-boot-code-modifictaion---add-crc-compare-2"></a>
<a id="project-boot-code-modifictaion---use-smart-config-tool-to-generate-driver"></a>
<a id="project-boot-code-modifictaion---boot_mainc"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow-check_generic_boot_standard_interface"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow-read_device_signature"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow-read_area_information"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow-start_device_image_transfer"></a>
<a id="project-boot-code-modifictaion---i2c-command-flow-terminal-operation-master-slave"></a>
<a id="project-boot-code-modifictaion---xmodem-update-flow"></a>
<a id="project-boot-code-property-modifictaion---e2-lite-setting"></a>
<a id="project-boot-code-property-modifictaion---cc-rl-build-tool-setting"></a>
<a id="project-boot-code-property-modifictaion---cc-rl-build-tool-setting-2"></a>
<a id="project-boot-code-property-modifictaion---cc-rl-build-tool-setting-3"></a>
<a id="project-boot-code-property-modifictaion---cc-rl-build-tool-setting-4"></a>
<a id="reference---rl78f23-f24-user’s-manual-hardware---input-source-list"></a>
<a id="project-rl78f23-f24-user’s-manual-hardware---vector-table"></a>
<a id="project-boot-codeapp-code-modifictaion---ftableinc-2"></a>
<a id="project-app-code-modifictaion---cstartasm"></a>
<a id="project-app-code-modifictaion---ftableasm"></a>
<a id="project-app-code-modifictaion---fsy-file"></a>
<a id="project-app-code-modifictaion---project-tree"></a>
<a id="project-app-code-modifictaion---add-data-flash-library"></a>
<a id="project-app-code-modifictaion---use-smart-config-tool-to-generate-driver"></a>
<a id="project-app-code-modifictaion---remove-static-and-vect-define"></a>
<a id="project-app-code-modifictaion---mainc"></a>
<a id="project-app-code-property-modifictaion---e2-lite-setting"></a>
<a id="project-app-code-property-modifictaion---cc-rl-build-tool-setting"></a>
<a id="project-app-code-property-modifictaion---cc-rl-build-tool-setting-2"></a>
<a id="project-app-code-property-modifictaion---cc-rl-build-tool-setting-3"></a>
<a id="project-app-code-property-modifictaion---cc-rl-build-tool-setting-4"></a>
<a id="how-to-add-interrupt-at-boot-code"></a>
<a id="how-to-use-hardware-crc-at-boot-code-and-app-code-project"></a>

<details>
<summary>UART／I2C 章節連結</summary>

| 章節 | 範例頁位置 |
| --- | --- |
| Flash library 類型 | [閱讀章節](uart_i2c/#target_MCU_flash_type) |
| App 返回 Boot 的 RAM marker | [閱讀章節](uart_i2c/#ram_flag) |
| ftable.inc 分區設定 | [閱讀章節](uart_i2c/#FALSH_TABLE) |
| ftable.inc 欄位 | [閱讀章節](uart_i2c/#ftable_inc) |
| App 起點與 mirror 對照 | [閱讀章節](uart_i2c/#map_const) |
| Boot main | [閱讀章節](uart_i2c/#boot_main) |
| Boot 硬體初始化 | [閱讀章節](uart_i2c/#boot_hdwinit) |
| Flash symbol 檔案 | [閱讀章節](uart_i2c/#fsy_file) |
| App IRQ 向量位址 | [閱讀章節](uart_i2c/#vect_address) |
| 硬體向量表 | [閱讀章節](uart_i2c/#vector_table) |
| UART／I2C 範例 | [閱讀章節](uart_i2c/#uart／i2c-範例) |
| Flash architecture | [閱讀章節](uart_i2c/#flash-architecture) |
| Scenario : Boot area (boot code) | [閱讀章節](uart_i2c/#scenario-boot-area-boot-code) |
| Scenario : Flash area (app code) | [閱讀章節](uart_i2c/#scenario-flash-area-app-code) |
| Project : boot code/app code configuration - ftable.inc | [閱讀章節](uart_i2c/#project-boot-codeapp-code-modifictaion---ftableinc) |
| Project : boot code configuration - cstart.asm | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---cstartasm) |
| Project : boot code configuration - stkinit.asm | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---stkinitasm) |
| Project : boot code configuration - project tree | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---project-tree) |
| Project : boot code configuration - add CODE FLASH library | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---add-code-flash-library) |
| Project : boot code configuration - add CRC compare (1) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---add-crc-compare-1) |
| Project : boot code configuration - add CRC compare (2) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---add-crc-compare-2) |
| Project : boot code configuration - use smart config tool to generate driver | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---use-smart-config-tool-to-generate-driver) |
| Project : boot code configuration - boot_main.c | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---boot_mainc) |
| Project : boot code configuration - I2C command flow | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow) |
| Project : boot code configuration - I2C command flow (check_generic_boot_standard_interface) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow-check_generic_boot_standard_interface) |
| Project : boot code configuration - I2C command flow (read_device_signature) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow-read_device_signature) |
| Project : boot code configuration - I2C command flow (read_area_information) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow-read_area_information) |
| Project : boot code configuration - I2C command flow (start_device_image_transfer) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow-start_device_image_transfer) |
| Project : boot code configuration - I2C command flow terminal operation (master & slave) | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---i2c-command-flow-terminal-operation-master-slave) |
| Project : boot code configuration - xmodem update flow | [閱讀章節](uart_i2c/#project-boot-code-modifictaion---xmodem-update-flow) |
| Project : boot code property configuration - E2 lite setting | [閱讀章節](uart_i2c/#project-boot-code-property-modifictaion---e2-lite-setting) |
| Project : boot code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-boot-code-property-modifictaion---cc-rl-build-tool-setting) |
| Project : boot code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-boot-code-property-modifictaion---cc-rl-build-tool-setting-2) |
| Project : boot code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-boot-code-property-modifictaion---cc-rl-build-tool-setting-3) |
| Project : boot code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-boot-code-property-modifictaion---cc-rl-build-tool-setting-4) |
| Reference - RL78/F23, F24 User’s Manual: Hardware - Input Source List | [閱讀章節](uart_i2c/#reference---rl78f23-f24-user’s-manual-hardware---input-source-list) |
| Project : RL78/F23, F24 User’s Manual: Hardware - Vector Table | [閱讀章節](uart_i2c/#project-rl78f23-f24-user’s-manual-hardware---vector-table) |
| Project : boot code/app code configuration - ftable.inc | [閱讀章節](uart_i2c/#project-boot-codeapp-code-modifictaion---ftableinc-2) |
| Project : app code configuration - cstart.asm | [閱讀章節](uart_i2c/#project-app-code-modifictaion---cstartasm) |
| Project : app code configuration - ftable.asm | [閱讀章節](uart_i2c/#project-app-code-modifictaion---ftableasm) |
| Project : app code configuration - fsy file | [閱讀章節](uart_i2c/#project-app-code-modifictaion---fsy-file) |
| Project : app code configuration - project tree | [閱讀章節](uart_i2c/#project-app-code-modifictaion---project-tree) |
| Project : app code configuration - add DATA FLASH library | [閱讀章節](uart_i2c/#project-app-code-modifictaion---add-data-flash-library) |
| Project : app code configuration - use smart config tool to generate driver | [閱讀章節](uart_i2c/#project-app-code-modifictaion---use-smart-config-tool-to-generate-driver) |
| Project : app code configuration -  remove static and vect define | [閱讀章節](uart_i2c/#project-app-code-modifictaion---remove-static-and-vect-define) |
| Project : app code configuration - main.c | [閱讀章節](uart_i2c/#project-app-code-modifictaion---mainc) |
| Project : app code property configuration - E2 lite setting | [閱讀章節](uart_i2c/#project-app-code-property-modifictaion---e2-lite-setting) |
| Project : app code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-app-code-property-modifictaion---cc-rl-build-tool-setting) |
| Project : app code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-app-code-property-modifictaion---cc-rl-build-tool-setting-2) |
| Project : app code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-app-code-property-modifictaion---cc-rl-build-tool-setting-3) |
| Project : app code property configuration - CC-RL Build Tool setting | [閱讀章節](uart_i2c/#project-app-code-property-modifictaion---cc-rl-build-tool-setting-4) |
| How to add interrupt at boot code | [閱讀章節](uart_i2c/#how-to-add-interrupt-at-boot-code) |
| How to use hardware CRC at boot code and app code project | [閱讀章節](uart_i2c/#how-to-use-hardware-crc-at-boot-code-and-app-code-project) |

</details>

## Tool 與其他操作入口

[Tool 操作](https://released.github.io/slide_isp_tool_for_RL78/#tool-operation) · [Custom Transfer](https://released.github.io/slide_isp_tool_for_RL78/#custom-transfer) · [CAN 更新逐層導讀](https://released.github.io/slide_isp_tool_for_RL78/#can-update-walkthrough)

<!-- PUBLIC_RESOURCES_BEGIN -->
<a id="downloads"></a>

## 下載與操作入口

Tool、host／device firmware 的來源與下載檔案集中於 ISP Tool 頁。F13、F24 CAN device 的工程配置則由各自的章節說明。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#downloads)
<!-- PUBLIC_RESOURCES_END -->

<!-- F24_APP_IRQ_BEGIN -->
<a id="host-app-engineering"></a>

## F24 (MCU CAN host)：App 工程與向量設定

Host App 的工程來源、獨立產表、建置方式與 Misc 操作集中於 ISP Tool 頁。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#host-app-engineering)
<!-- F24_APP_IRQ_END -->

<!-- COMMON_IMAGE_POLICY_BEGIN -->
<a id="image-update-policy"></a>

## 更新政策與通訊速度

BIN 的更新目的地、允許介面、Boot／IRQ ABI 與 Host Link 速度，集中於 ISP Tool 的更新政策章節。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#image-update-policy)
<!-- COMMON_IMAGE_POLICY_END -->

<!-- UPDATE_EVIDENCE_BEGIN -->
<a id="update-confirmation"></a>

## 更新確認與驗證紀錄

App 確認、metadata 差異表、階段進度、取消、報告與實板測試表集中於 ISP Tool。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#update-confirmation)
<!-- UPDATE_EVIDENCE_END -->

<!-- FD_UPDATE_BEGIN -->
<a id="can-fd-update"></a>

## CAN FD App 更新操作

500K／2M、BRS、64-byte FD資料幀的Tool與Host操作集中於ISP Tool。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-update)
<!-- FD_UPDATE_END -->

<!-- FD_DEVICE_BEGIN -->
<a id="can-fd-device-engineering"></a>

## MCU CAN FD device 工程設定

F24 device 使用獨立 `RL78_F24_Boot_loader_CAN_FD` 與
`RL78_F24_Boot_loader_CAN_FD_app` 工程，放在同一父目錄。
App 引用相鄰 FD Boot 的 common／metadata 來源。
App 發行與 IRQ 編輯沿用 [C header 工作流程](https://released.github.io/slide_boot_loader_for_RL78/#device-metadata-vector-workshop)。

### 設定來源

| 可編輯來源 | 作用／此範例值 |
| --- | --- |
| App `app_image_config.h` | 版本、build、target、role、允許更新介面、版本政策 |
| App `app_irq_handlers.h` | App-local IRQ mapping；無 vect ISR |
| Boot `image_metadata_config.h` | Flash／metadata格式／IRQ ABI／最低Boot相容契約 |
| Boot `can_boot_config.h` | mode2、nominal mask4、data mask2及ID |
| Boot `common/f24_device_config.h` | 實際40MHz CAN clock timing、FD模式、64-byte RXMB及中斷來源 |
| Boot `boot_app_handoff.h` | owner Boot=AA／App=55、no-init RAM |
| `image_metadata_profile.c` | 由獨立metadata parser比對的工程契約 |
| `tools/device_common.ps1` | 讀取上述C headers、產生metadata |

mode mask 的 bit1 表示 CAN FD；nominal mask 的 bit2 表示500K；data mask 的 bit1表示2M。
這些值描述已編譯的設定，不會重新設定周邊。
變更速率時，Boot／App 的實際 timing、metadata及Tool選項需一起對應。

| Timing輸入 | Nominal | Data |
| --- | --- | --- |
| fCAN | 40MHz | 40MHz |
| BRP register | 3 | 1 |
| 實際divider | 4 | 2 |
| TSEG1／TSEG2／SJW（時間單位數） | 15／4／1 | 7／2／1 |
| 計算 | 40M/(4×(1+15+4))=500K | 40M/(2×(1+7+2))=2M |
| Sample point | 80% | 80% |

preinclude 在SC header之後覆寫CLOE=0、FDOE=1與RXMB RMPLS=7（64bytes）。
SC重新產生後仍需執行工程prepare及clean build，核對實際linked產物。
硬體來源見 [Renesas F24 Target Board](https://www.renesas.com/en/design-resources/boards-kits/rtk7f124fpc01000bj)；
4MHz resonator與周邊接線依實際板本確認。

<a id="can-fd-device-rx"></a>

### 接收與中斷

Boot 與 App 各自連結 `common/device_can.c`，使用精簡 RXMB0 ISR 與 8 筆 RAM queue。
主迴圈負責命令、metadata、CRC 及 Flash 流程；ISR 只核對幀的型態／長度並搬移資料，不解析更新命令、不輸出 UART，也不等待 TX。
主迴圈不直接輪詢 RXMB0；TX 完成狀態仍使用有上限的輪詢。

| 項目 | 設定與來源 |
| --- | --- |
| RXMB0 | `CAN_CFG_NRXMB=1`、`CAN_CFG_RMPLS=7`；RMNB=0x0701，保存完整 64-byte payload |
| 接收規則 | Boot 接收 standard 0x700 與 0x720；App 接收 0x700；exact mask 0x7FF，只存 RXMB0 |
| 硬體中斷 | RMIEC bit0=1；初始化完成後 RCANGRVCMK=0 |
| Driver ISR 設定 | `CAN_CFG_INTRCANGRVC_USE=0` 只停用 driver 自帶的 vect ISR；硬體 RXMB 中斷由 `Device_CanRxIsr` 處理 |
| 接收 FIFO | RF0／RF1 關閉，不與 RXMB0 重複存放 |
| 向量來源 | App `iodefine.h` 的 `INTRCANGRVC=0x004C`，對應此 MCU 的硬體手冊中斷表 |
| Boot owner=AA | Boot 的實體 vector 0x4C → 完整 dispatcher → Boot `Device_CanRxIsr` |
| App owner=55 | 同一實體 vector → App table 的 0x2098 槽位 → App `Device_CanRxIsr` |
| App 編輯來源 | `app_irq_handlers.h` 的 `X(0x4C, Device_CanRxIsr)`；函式使用 global、無 `vect=` 的 interrupt pragma，以 RETI 返回 |

槽位換算、Boot／App ISR 名稱及一般 IRQ 轉送規則見
[中斷所有權與向量轉送](https://released.github.io/slide_boot_loader_for_RL78/#device-irq-ownership)。
建置會檢查完整向量、實際 CAN ISR 槽位、RETI 及實體 vector 所有權。

queue 使用 9 個儲存槽提供 8 筆容量；producer 發布 head、consumer 釋放 tail 都在完成複製後進行。
queue 滿時丟棄新到訊息，保留原有順序。
ISR 確認 RMND 後讀取 RXMB0，保存／還原 CAN RAM window；讀取期間若再次收到訊息，該次副本不入列。

| 診斷 | 意義與取得方式 |
| --- | --- |
| `Device_CanRxFaults()` bit0 | queue 滿載或 CAN 尚未 ready 時的丟棄 |
| bit1 | 讀取 RXMB0 期間發生覆寫 |
| bit2 | 不符合 standard data／FD+BRS／支援長度的幀 |
| `Device_CanRxDrops()` | 丟棄觀察計數，累計到 255 後飽和；不是線上所有遺失幀的精確數量 |
| 觀察位置 | App 在 UART counter 旁顯示非零 faults／drops；Boot 可由 debugger 查看 `g_rx_faults`／`g_device_rx_drops`，位址由當次 map 查詢 |
| 重設範圍 | 上述值只在 CAN 初始化時歸零；正常一問一答應保持 0 |

### 更新區塊與 Flash 交接

一個區塊的 BEGIN8、DATA64、COMMIT8 可先入 queue，再由 Boot 主迴圈依序處理。
metadata、分區、版本政策、重送序號與區塊 CRC 檢查完成後，才允許 Flash 寫入。
Boot 的回覆由 HAL 固定為 standard response ID、FD+BRS、8-byte payload；不從收到的幀複製回覆路由或長度。

```mermaid
flowchart TD
    BUS["MCU CAN device / RXMB0 interrupt"] --> QUEUE["RAM queue / BEGIN8 + DATA64 + COMMIT8"]
    QUEUE --> MAIN["Boot 主迴圈依序取出"]
    MAIN --> GATE{"metadata / 範圍 / 序號 / CRC 通過？"}
    GATE -->|否| REJECT["拒絕寫入 / 回覆狀態"]
    GATE -->|是| RAM["DI / RAM-only Flash call chain"]
    RAM --> FLASH["必要 erase / write / 有上限完成等待"]
    FLASH --> READ["還原可讀模式 / EI"]
    READ --> ACK["COMMIT ACK / Host 才傳下一區塊"]
```

Flash 忙碌期間，RFD 呼叫鏈及必要資料位於 RAM，全域中斷關閉；恢復可讀模式後才重新開啟中斷。
8 筆 RAM queue 不代表 DI 期間硬體可額外保存 8 幀；RXMB0 仍只有一筆硬體容量。
Host 在 COMMIT ACK 前等待，不連續送下一個區塊；逾時與斷線結果保持有限重送與明確失敗，不以自動重置掩蓋。


### Flash與建置

`RL78_F24_Boot_loader_CAN_FD`、`RL78_F24_Boot_loader_CAN_FD_app` 與 `RL78_F24_CAN_FD_Transfer`
保持同層及既有名稱；App／Transfer 都需要 Boot checkout 的共用來源與 PowerShell helpers。
詳細相依與生成路徑檢查見 [工程發佈說明](https://github.com/released/simple_renesas_isp_tool/blob/main/docs/GITHUB_PUBLISH_zh-TW.md#fd-publication-layout)。
SC 重新生成後使用同一建置入口；`-CheckOnly` 檢查相對路徑及生成檔狀態。

| 絕對address | 用途 |
| --- | --- |
| 0x0000..0x1FFF | 8KiB Boot與實體vectors |
| 0x2000..0x20FF | 完整64-slot App跳轉表 |
| 0x2100..0x217F |128-byte metadata core |
| 0x2180..0x21FF |128-byte reservedFF |
| 0x2200起 | App startup／code |
| App start + image_size -4 | 全映像 CRC32 tail |
| 0x3FC00..0x3FFFF | 保護區 |

在 FD Boot 目錄執行：

```powershell
# Clean rebuild only the FD Boot/App pair.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind all
# App-only release changes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Kind app
# Artifact, metadata, IRQ, ROM/RAM and CRC guards.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test.ps1
```

MCU建置使用CS+ CC-RL、Windows PowerShell5.1／.NET，不需Python。
封裝維持至少512-byte Boot餘裕、完整IRQ表、RAM-only RFD與分區界線；
App-only建置不改Boot；操作見 [CAN FD更新](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-update)。

| 產物 | 使用方式 |
| --- | --- |
| Boot `DefaultBuild/boot0000_1FFF.hex` | 燒錄器安裝 FD Boot |
| App `DefaultBuild/flash_app_variable_CRC.hex` | 燒錄器安裝含metadata／CRC的App |
| App `boot_app.hex` | 合併Boot/App初裝 |
| App `DefaultBuild/RL78_F24_Boot_loader_CAN_FD_app_update.bin` | Tool CAN FD更新 |
| App `DefaultBuild/app_build_report.html` | 實際BIN metadata／CRC／hash／IRQ報告 |

<!-- FD_DEVICE_END -->

<!-- FD_TRANSFER_BEGIN -->
<a id="can-fd-custom-transfer"></a>

## CAN FD Custom Transfer 通訊測試

CAN FD Discover、8-byte命令、64-byte ECHO、能力與操作核對集中於ISP Tool。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-custom-transfer)
<!-- FD_TRANSFER_END -->


<!-- RH850_DEVICE_BEGIN -->
<!-- RH850_DEVICE_END -->
