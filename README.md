# RL78 Bootloader 實作指南

- 網頁入口：<https://released.github.io/slide_boot_loader_for_RL78/>
- 可編輯內容：`index.md`；網頁載入入口：`index.html`。
- 共用版型：`notices_can/assets/style.css`與`notices_can/assets/app.js`。

本頁涵蓋RL78 Boot/App記憶體配置、向量轉送、startup、Flash更新與驗證，
保留UART／I2C教材並加入CAN流程。不同project的BIN、CRC、layout與clock
契約不能混用；Tool與bridge操作另見sibling `slide_isp_tool_for_RL78`。

公開導覽與介紹不綁定Tool／firmware版號、交付階段或單次效能數字；
精確配套版本與雜湊由交付說明提供。必要的protocol／image format／IRQ ABI
及尚未完成的實板驗證仍須明確列出。

## 共用內容維護

- `#boot-app-porting`：以Tool的`docs/RL78_BOOT_APP_PORTING_GUIDE_zh-TW.md`
  中`RL78_PORTING`區塊為原稿，執行`sync_rl78_porting_guide.ps1`。
- F13 Boot→App、ENTER與timer：由`docs/F13_BOOT_UPDATE_FLOW_zh-TW.md`
  與`sync_f13_boot_decision.ps1`同步，不套用到舊UART／I2C教材。
- F24各App獨立產表：由`docs/SHARED_CONSOLE_BRIDGE_GUIDE_zh-TW.md`
  與`sync_f24_app_irq_guide.ps1`同步。
- 共用metadata與跨介面防呆：由`docs/COMMON_IMAGE_METADATA.md`
  與`sync_common_image_policy.ps1`同步。

修改原稿後執行同步與`-CheckOnly`，保留既有參考連結、圖片和必要的硬體限制。
功能變更同時更新相關MD／PDF、web與驗證狀態，不把build／mock當成實板通過。
頁面引用與預覽可使用ISP Tool頁的`scripts/verify_local.ps1`檢查。
