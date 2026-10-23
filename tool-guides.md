[知識庫首頁](https://released.github.io/) · [RL78 Bootloader 實作指南](index.html)

<a id="article_top"></a>

# Tool 操作與通訊驗證入口

下載、更新、報告、MCU host 與 Custom Transfer 的主題連結。

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

<!-- FD_TRANSFER_BEGIN -->
<a id="can-fd-custom-transfer"></a>

## CAN FD Custom Transfer 通訊測試

CAN FD Discover、8-byte命令、64-byte ECHO、能力與操作核對集中於ISP Tool。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-custom-transfer)
<!-- FD_TRANSFER_END -->

<!-- UART_TOOL_GUIDE_BEGIN -->
<a id="uart-device-operation"></a>

## UART／Xmodem／I2C device 操作

四系列串列 ISP、獨立診斷 UART、接線、更新與 Custom Transfer 集中於 ISP Tool 頁。
[閱讀完整章節](https://released.github.io/slide_isp_tool_for_RL78/#uart-device-operation)
<!-- UART_TOOL_GUIDE_END -->

---

[上一主題：Flash、Metadata 與 CAN 封包參考](reference.html) · [指南入口](index.html)
