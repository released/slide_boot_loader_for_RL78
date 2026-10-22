# RL78 MCU CAN device Boot/App 指南

- 網頁入口：<https://released.github.io/slide_boot_loader_for_RL78/>
- 內容：`index.md`；載入入口：`index.html`。
- 共用版型：`notices_can/assets/style.css`、`app.js`。

本頁提供 MCU CAN device 的 Boot/App 工程、metadata、vector、startup 與 Flash 更新說明。
F13 與 F24 各有獨立工程，概念流程使用 MCU CAN device 名稱；型號、位址與驅動差異列於工程表格。
Basic UART／I2C 範例的設定與來源集中於 [獨立範例頁](basic_uart_i2c/)，內容為 `basic_uart_i2c/index.md`。
`uart_i2c/` 保留轉址並延續章節錨點。
主頁保留原章節的 anchor 及跳轉入口。
首頁模式導覽分為 Classical CAN（F13／F24）、CAN FD（F24）及 Custom Transfer 三種範例；僅提供工程及操作跳轉。

## 主題維護

編寫與驗收依據為 [公開文件編寫準則](PUBLIC_CONTENT_GUIDELINES_zh-TW.md)。
共用原稿位於 `/web` 根目錄，適用目前與未來各類 slide；此處為獨立 repository 的同步副本。
規範同步由 `/web/scripts/sync_public_content_guidelines.ps1` 維護，並可使用 `-CheckOnly` 檢查。

原稿位於 [Tool docs](https://github.com/released/simple_renesas_isp_tool/tree/main/docs)。
同步腳本的主題歸屬由 `scripts/web_guide_sections.json` 定義：完整內容只保留在所屬頁面，其他頁面產生簡短跳轉連結。
`index.md` 的 `DEVICE_MODE_NAV` 為本站首頁導覽，連到上述原稿所屬章節，不另放完整教學。

| 本頁完整章節 | 原稿／同步腳本 |
| --- | --- |
| CAN FD device timing／工程／產物 | CAN_FD_UPDATE 的 FD_DEVICE／sync_can_fd.ps1 |
| Device Metadata／App IRQ C header 編輯與建置 | DEVICE_METADATA_VECTOR_WORKSHOP／sync_device_workshop.ps1 |
| Device CAN 速率／Boot-App ISR 所有權／App counter | 同一 workshop 的 device-can-bitrate／device-irq-ownership／device-app-runtime-log |
| App BIN 大小與更新耗時實測 | 同一 workshop 的 device-update-timing；ISP 頁僅放跳轉連結 |
| F13 Boot decision／ENTER／逾時 | F13_BOOT_UPDATE_FLOW／sync_f13_boot_decision.ps1 |
| F24 device 工程 | F24_CAN_DEVICE_DESIGN／sync_f24_device_design.ps1 |
| Boot/App 移植 | RL78_BOOT_APP_PORTING_GUIDE／sync_rl78_porting_guide.ps1 |
| Basic／golden sample 對照、Flash RAM 執行、CRC 後端 | 同一 porting guide 的 basic-vs-golden／flash-ram-execution／crc-backends |
| Boot 安裝／debug monitor／119、247 KiB 與滿容量限制 | 同一 porting guide 的 device-debug-monitor；Tool operation 僅放提醒與跳轉 |
| Flash／metadata 全部 byte／CAN frame | FLASH_METADATA_CAN_FRAME_GUIDE／sync_flash_reference.ps1 |

Tool 操作、Custom Transfer、CAN 更新逐層導讀、Host App 工程、下載及更新政策集中於
[ISP Tool 頁](https://released.github.io/slide_isp_tool_for_RL78/)。

修改原稿後執行同步及 `-CheckOnly`，同步相關 PDF。
使用 `-WebRoot` 或 `FIRMWARE_WEB_ROOT` 指定網站 checkout 父目錄。
ISP Tool 的 `scripts/verify_local.ps1` 檢查本機引用與章節連結。
