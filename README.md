# RL78 MCU CAN device Boot/App 指南

- 網頁入口：<https://released.github.io/slide_boot_loader_for_RL78/>
- 內容：`index.md`；載入入口：`index.html`。
- 共用版型：`notices_can/assets/style.css`、`app.js`。

本頁提供 MCU CAN device 的 Boot/App 工程、metadata、vector、startup 與 Flash 更新說明。
F13 與 F24 各有獨立工程，概念流程使用 MCU CAN device 名稱；型號、位址與驅動差異列於工程表格。
UART／I2C 範例保留各自的設定與來源。

## 主題維護

原稿位於 [Tool docs](https://github.com/released/simple_renesas_isp_tool/tree/main/docs)。
同步腳本的主題歸屬由 `scripts/web_guide_sections.json` 定義：完整內容只保留在所屬頁面，其他頁面產生簡短跳轉連結。

| 本頁完整章節 | 原稿／同步腳本 |
| --- | --- |
| Device Metadata／App IRQ JSON 編輯與建置 | DEVICE_METADATA_VECTOR_WORKSHOP／sync_device_workshop.ps1 |
| F13 Boot decision／ENTER／逾時 | F13_BOOT_UPDATE_FLOW／sync_f13_boot_decision.ps1 |
| F24 device 工程 | F24_CAN_DEVICE_DESIGN／sync_f24_device_design.ps1 |
| Boot/App 移植 | RL78_BOOT_APP_PORTING_GUIDE／sync_rl78_porting_guide.ps1 |
| Flash／metadata 全部 byte／CAN frame | FLASH_METADATA_CAN_FRAME_GUIDE／sync_flash_reference.ps1 |

Tool 操作、Custom Transfer、CAN 更新逐層導讀、Host App 工程、下載及更新政策集中於
[ISP Tool 頁](https://released.github.io/slide_isp_tool_for_RL78/)。

修改原稿後執行同步及 `-CheckOnly`，同步相關 PDF。
使用 `-WebRoot` 或 `FIRMWARE_WEB_ROOT` 指定網站 checkout 父目錄。
ISP Tool 的 `scripts/verify_local.ps1` 檢查本機引用與章節連結。
