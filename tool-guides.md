[知識庫首頁](https://released.github.io/) · [RL78 Bootloader](index.html)

<a id="article_top"></a>

# Tool 操作與通訊驗證入口

下載、更新、報告、MCU host 與 Custom Transfer 的主題連結。

<!-- BOOTLOADER_TOPICS_BEGIN -->
## 本頁主題

| 章節／規格 | 本頁 | 另一平台 |
| --- | --- | --- |
| Tool 與其他操作入口 | [閱讀](#tool-links) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#tool-links) |
| 下載與操作入口 | [閱讀](#downloads) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#downloads) |
| F24 (MCU CAN host)：App 工程與向量設定 | [閱讀](#host-app-engineering) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#host-app-engineering) |
| 更新政策與通訊速度 | [閱讀](#image-update-policy) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#image-update-policy) |
| 更新確認與驗證紀錄 | [閱讀](#update-confirmation) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#update-confirmation) |
| CAN FD App 更新操作 | [閱讀](#can-fd-update) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#can-fd-update) |
| CAN FD Custom Transfer 通訊測試 | [閱讀](#can-fd-custom-transfer) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#can-fd-custom-transfer) |
| UART／Xmodem／I2C device 操作 | [閱讀](#uart-device-operation) | [RH850](../slide_boot_loader_for_RH850/tool-guides.html#uart-device-operation) |
<!-- BOOTLOADER_TOPICS_END -->

<a id="tool-links"></a>

## Tool 與其他操作入口

[Tool 操作](https://released.github.io/slide_simple_renesas_isp_tool/#tool-operation) · [Custom Transfer](https://released.github.io/slide_simple_renesas_isp_tool/#custom-transfer) · [CAN 更新逐層導讀](https://released.github.io/slide_simple_renesas_isp_tool/#can-update-walkthrough)

<!-- PUBLIC_RESOURCES_BEGIN -->
<a id="downloads"></a>

## 下載與操作入口

Tool、host／device firmware 的來源與下載檔案集中於 ISP Tool 頁。F13、F24 CAN device 的工程配置則由各自的章節說明。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#downloads)
<!-- PUBLIC_RESOURCES_END -->

<!-- F24_APP_IRQ_BEGIN -->
<a id="host-app-engineering"></a>

## F24 (MCU CAN host)：App 工程與向量設定

Host App 的工程來源、獨立產表、建置方式與 Misc 操作集中於 ISP Tool 頁。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#host-app-engineering)
<!-- F24_APP_IRQ_END -->

<!-- COMMON_IMAGE_POLICY_BEGIN -->
<a id="image-update-policy"></a>

## 更新政策與通訊速度

BIN 的更新目的地、允許介面、Boot／IRQ ABI 與 Host Link 速度，集中於 ISP Tool 的更新政策章節。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#image-update-policy)
<!-- COMMON_IMAGE_POLICY_END -->

<!-- UPDATE_EVIDENCE_BEGIN -->
<a id="update-confirmation"></a>

## 更新確認與驗證紀錄

App 確認、metadata 差異表、階段進度、取消、報告與實板測試表集中於 ISP Tool。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#update-confirmation)
<!-- UPDATE_EVIDENCE_END -->

<!-- FD_UPDATE_BEGIN -->
<a id="can-fd-update"></a>

## CAN FD App 更新操作

500K／2M、BRS、64-byte FD資料幀的Tool與Host操作集中於ISP Tool。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#can-fd-update)
<!-- FD_UPDATE_END -->

<!-- FD_TRANSFER_BEGIN -->
<a id="can-fd-custom-transfer"></a>

## CAN FD Custom Transfer 通訊測試

CAN FD Discover、8-byte命令、64-byte ECHO、能力與操作核對集中於ISP Tool。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#can-fd-custom-transfer)
<!-- FD_TRANSFER_END -->

<!-- UART_TOOL_GUIDE_BEGIN -->
<a id="uart-device-operation"></a>

## UART／Xmodem／I2C device 操作

四系列串列 ISP、獨立診斷 UART、接線、更新與 Custom Transfer 集中於 ISP Tool 頁。
[閱讀完整章節](https://released.github.io/slide_simple_renesas_isp_tool/#uart-device-operation)
<!-- UART_TOOL_GUIDE_END -->

---

[上一主題：Flash、Metadata 與 CAN 封包參考](reference.html) · [指南入口](index.html)
