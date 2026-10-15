# RL78 Bootloader 實作指南

嵌入式系統知識庫內容。

- 發布頁面：<https://released.github.io/slide_boot_loader_for_RL78/>
- 可編輯內容：`index.md`
- 網頁入口：`index.html`
- 共用版型：`notices_can/assets/style.css` 與 `notices_can/assets/app.js`

編修內容時，原始參考連結與圖片保留於 `index.md` 正文。

2026-10-15新增「自訂 Bootloader／App 移植」入口（#boot-app-porting）。
技術內容以 tool docs/RL78_BOOT_APP_PORTING_GUIDE_zh-TW.md 的
RL78_PORTING block 為唯一來源，執行 scripts/sync_rl78_porting_guide.ps1
同步，-CheckOnly 驗證。內容包含 F13/F24 記憶體、IRQ、startup、CS+ hooks、
首次安裝與 App-only 更新，以及 F13 工程改名／路徑尚非全泛用的限制。
舊 UART／I2C callback 教材保留並加註不可混用，不改 firmware／Tool0077。

2026-10-15本機稿新增CAN bus：PC/bridge/device分工、self test與Transfer
benchmark、可變長度metadata/CRC32、Boot/App更新flow及未驗證邊界。
原UART/I2C內容保留。新操作稿在sibling `slide_isp_tool_for_RL78`。
本輪不commit/push/deploy；Device Boot/App實板步驟與新版UI截圖待補。

同步tool0.1.0.0077：Host Link128／metadata區256／core128，分段驗證後BEGIN才擦除；
舊96-host與舊image格式不相容。補充共用單畫面與Misc HOST APP UART更新的責任邊界，
F24 matching boot/app初次安裝與不同BIN不可混用；不改動既有UART／I2C教材。
功能變更時同步受影響MD／web與驗證狀態，不把build／mock當成實板PASS。

0077另補Host Link高速協商與device UART固定baud的界線；CAN／BUR1現有BIN
與F13 boot/app無變更。未來UART device需獨立profile／port driver，不能將
Host Baud當作device更新速度；Misc進BOOT使用其固定更新速度。

CAN新增完整F13 boot→app條件、ENTER marker、timer啟用／刷新／失敗分支，
以及format6固定完整RETI向量；相容app-only IRQ／版本變更不需重燒boot。
Managed區塊有三張流程圖，本輪整頁六張Mermaid已CLI render，板測仍待完成。
內容由tool guide標記區塊與sync_f13_boot_decision.ps1同步，不改既有UART/I2C範例。
UI的CAN/I2C/Misc TAB只在左側設定；中、右共用image/log區不受TAB涵蓋。

F24 新增各 app 獨立 mapping／identity／產表／封裝工程流程；A／B 實際編譯
使用不同 IRQ 名稱／版本，boot 雜湊不變。內容由 shared-console guide 的
F24_APP_IRQ block 與 sync_f24_app_irq_guide.ps1 同步；沒有新增 I2C device boot。

0076新增UPD1 Update Policy與Boot / IRQ ABI顯示；F13 protocol4／format6，
F24 bridge contract3。完整metadata在START／BEGIN前驗證，G16新版boot/app延後。
本輪native pipe重試與reset仍os error2，UI截圖／DPI為NOT RUN；不得使用示意圖。
共用政策由tool docs/COMMON_IMAGE_METADATA.md與sync_common_image_policy.ps1同步。
