<!-- GUIDE_OVERVIEW -->
[知識庫首頁](https://released.github.io/)

<a id="article_top"></a>

# RL78 Bootloader 實作指南

依閱讀目的選擇 MCU device 工程、App 設定、移植或格式參考。
日常更新與通訊驗證見 [ISP Tool 指南](../slide_isp_tool_for_RL78/)。

## 主題指南

| 主題 | 內容 |
| --- | --- |
| [Classical CAN／CAN FD device 工程](can-device.html) | F13／F24 Classical CAN、F24 CAN FD 的 Boot／App 工程與啟動流程。 |
| [App Metadata 與 IRQ 編輯](app-development.html) | C header 編輯、產表、App 建置、驗證、CAN 速率與更新耗時。 |
| [UART／Xmodem／I2C device 工程](serial-device.html) | 四系列獨立串列工程的 Flash、Metadata、IRQ 與通訊契約。 |
| [Boot／App 移植與 Flash](porting.html) | 分區、Boot 安裝、debug monitor、Flash RAM 執行與 CRC 後端。 |
| [Flash、Metadata 與 CAN 封包參考](reference.html) | 位址、全部 Metadata bytes、對應程式與 CAN payload。 |
| [Tool 操作與通訊驗證入口](tool-guides.html) | 下載、更新、報告、MCU host 與 Custom Transfer 的主題連結。 |

## CAN 範例分類

<!-- DEVICE_MODE_NAV_BEGIN -->
Classical CAN 的 F13／F24 共用 metadata、IRQ 與更新教學，硬體設定由各自工程章節說明。
CAN FD 使用 F24 的獨立 Boot／App 與 Transfer 工程。

| 分類 | 工程／範例 | 操作入口 |
| --- | --- | --- |
| Classical CAN：F13／F24 | [F13 Boot 啟動與更新](can-device.html#f13-boot-decision)／[F24 工程配置與建置](can-device.html#f24-can-device) | [App 更新](https://released.github.io/slide_isp_tool_for_RL78/#f13-device-update) |
| CAN FD：F24 | [Boot／App 設定、timing、metadata、IRQ 與 Flash](can-device.html#can-fd-device-engineering) | [CAN FD App 更新](https://released.github.io/slide_isp_tool_for_RL78/#can-fd-update) |
| Custom Transfer | F13／F24 Classical CAN；F24 CAN FD | [範例分類與通訊測試](https://released.github.io/slide_isp_tool_for_RL78/#custom-transfer) |
<!-- DEVICE_MODE_NAV_END -->

## Basic 參考工程

[Basic UART／I2C 範例](basic_uart_i2c/)提供獨立範例的分區、startup、向量與 CRC 操作。

<!-- RH850_DEVICE_BEGIN -->
<!-- RH850_DEVICE_END -->
