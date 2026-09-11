---
name: ic-project-report
description: Use when the user asks for a project report, progress report, verification report or meeting write-up for a Verilog/SystemVerilog project - one that walks through the architecture, shows simulation evidence as real waveform figures exported from Verdi, and states where every measured number came from. Distinct from ic-datasheet, which produces a printable A4 pin-level datasheet; this one produces a screen-readable report built around evidence.
metadata:
  short-description: Verilog project report with Verdi waveform evidence
---

# ic-project-report — Verilog 專案報告

產生一份**拿得出去講**的專案報告：架構走一遍、模擬證據用真實波形圖、每個數字都交代得出來源。
產出是**單一 HTML**，圖與樣式全部內嵌，寄出去或換台機器開都不會壞。

跟 `ic-datasheet` 的差別：那個產 A4 列印的 pin-level datasheet（module symbol、pin table）；
這個產**螢幕上讀的報告**，核心是證據而不是規格表。

---

## 這份報告要回答三個問題

| 問題 | 對應章節 |
|---|---|
| 這個系統是什麼、資料怎麼流 | 架構 |
| 你怎麼知道它是對的 | 模擬證據（波形） |
| 這些數字是怎麼量到的 | 量測方法與來源 |

第三個問題最容易被輕忽，卻是最常被追問的。**每一個數字都要能指出量測點、工具、以及交叉驗證方式**。

---

## 章節骨架

1. **報告定位與既有文件稽核** — 這份要看哪裡，既有的報告各是什麼角色，有沒有過時的數字
2. **系統架構** — 資料從哪來、怎麼擺、怎麼進去、怎麼出來
3. **路徑 A 模擬**（例如寫入）— 結果 + 波形
4. **路徑 B 模擬**（例如讀出）— 結果 + 波形
5. **全部量測數據與來源** — 每個數字怎麼來的
6. **測試環境與重現步驟** — 指令可以照抄
7. **還可以做什麼** — 缺口、下一步、規模上限分析

規模可以縮，但**第 1 章與第 5 章不要省**。稽核既有文件常會抓出過時數字；
而「數字怎麼來的」是報告可信度的全部。

---

## 波形圖：用腳本產，不要手動截圖

**這是這個 skill 最有價值的部分。** Verdi 是 GUI 工具，但它吃 Tcl 腳本，
而且可以跑在虛擬顯示上——所以波形圖可以**完全自動產生**，一個月後重跑得到同一張圖。

```sh
scripts/verdi_capture.sh <fsdb> <top> <figures-file> [outdir]
```

figures 檔一行一張圖：

```
# name        t_start   t_end     signals（相對 top 的路徑，dut/foo 可用）
launch        50000     132000    clk go busy arvalid arready ch0_araddr
data         152000     260000    clk ch0_rvalid ch0_rlast ch0_rdata len:dec
credits      400000    9000000    clk busy tags:dec inflight:analog
```

訊號後面可加顯示格式：`:dec`（無號十進位）、`:hex`（預設）、`:bin`、`:analog`（畫成曲線）。
**長度、計數、tag、指標一律用 `:dec`**——讀者不該為了驗證一句話先把 0x80 換算成 128。
`:analog` 的訊號放在該行最後，其他訊號的位置才不會移動。

腳本會依訊號數自動決定視窗高度，寬度用環境變數 `FIG_W`（預設 1280；報告裡的圖大約顯示 900 px 寬，
截得太寬字會被縮到看不清）。截完會裁掉 Verdi 的工具列與底部尺規，`CROP=0` 保留原圖。

### 會安靜失敗的地方

**① FSDB 的時間單位通常是 ps，不是 ns。** `wvZoom` 的參數用該單位。
給 ns 的數值會縮放到訊號還沒開始跳動的位置，得到一張全零的圖，而且**不會有任何錯誤**。
先確認單位：

```tcl
puts [wvGetFileTimeUnit -win $_nWave2]
puts [wvGetFileTimeRange -win $_nWave2]
```

**② `wvCreateWindow` 每次都建立新視窗，但 `$_nWave2` 仍指向第一個。**
每張圖各建一個視窗會捕捉到空白面板。開一個視窗重複使用，圖與圖之間 `wvClearAll`。

**③ `-nogui` 不會繪製波形面板。** 用它截到的是空圖。要跑完整 GUI，
但接到自己的 Xvfb（`Xvfb :99 -screen 0 1920x1200x24`），不要用使用者的螢幕。

**④ 指令名稱要實測，不要猜。** 匯出圖是 `wvCapture -win $w -file x.png`；
`wvExportBitMap` 不存在。Verdi 遇到不認得的指令**只印一行就繼續跑**，
圖會安靜地少一張。腳本已經把這個當成錯誤處理。列出真正可用的指令：

```tcl
set fh [open /tmp/cmds.txt w]; puts $fh [join [lsort [info commands wv*]] "\n"]; close $fh
```

以下幾項腳本都已處理，列出來是因為自己寫 Tcl 時會再踩一次，而且全部**回傳成功、不印錯誤**：

**⑤ 預設截圖只有 900×317，大約十個訊號。** 多的訊號被捲出畫面上方，圖上看不出少了東西。
`wvResizeWindow` 回傳成功但沒有效果——波形面板是嵌在主視窗裡的 dock。要改主視窗大小再把 dock 最大化：

```tcl
verdiWindowResize -win $_Verdi_1 "0" "0" "1280" "600"
verdiDockWidgetMaximize -dock windowDock_nWave_2
```

截圖高度 = 主視窗高度 − 98 px；一列數位訊號 20 px，一列類比約 100 px。

**⑥ `verdiDockWidgetMaximize` 是切換。** 每張圖都呼叫一次的話，第二、四、六……張會被還原成約 200 px 高，
大半訊號捲出畫面。只在開頭呼叫一次，之後每張圖只調 `verdiWindowResize`。

**⑦ 選訊號要傳字串 `"( \"G1\" 2 5 7 )"`，也就是 Verdi 自己記錄在 `verdiLog/verdi.cmd` 的格式。**
傳 Tcl list `{G1 2 5 7}` 也會回傳成功，但什麼都沒選，接著的 `wvSetRadix` 就安靜地不生效。

**⑧ `wvDigitalToAnalog` 不是原地轉換。** 它在最下面加一條類比副本（名稱自動加上 `DtoA_`），
原本的數位列還留著，變成一條密到看不清的匯流排。要按位置再選一次原列、`wvCut` 掉。

**⑨ 名稱欄大約只顯示 13 個字元，連 `[msb:lsb]` 一起算，超過的從左邊截掉。**
`wvSetSubWindow` 回傳成功但沒有效果；`wvSplitWindow` 會把波形面板切成上下兩半。
唯一的辦法是讓訊號名夠短，這一條要在寫 TB 輔助訊號時就考慮（見下一節）。

**⑩ Verdi 會在工作目錄寫 `verdiLog/`、`novas.rc`、`novas.conf`。** 在使用者的 repo 裡跑會把這些混進去。
腳本在暫存目錄執行 Verdi。

**⑪ 截圖底部那條尺規標的是整個波形檔的時間範圍，不是這張圖的。** 讀者會把它當成這張圖的時間軸。
腳本會把它和上方工具列一起裁掉。

### 讓波形看得懂：在 TB 裡替扁平匯流排取名字

AXI 匯流排在埠列表上是扁平的 `[16 × 寬度 − 1 : 0]`，波形檢視器只能顯示成一個極寬的十六進位值，
實務上無法閱讀。**在 testbench（不是 RTL）加一組具名訊號**，純觀察、不驅動任何邏輯：

```verilog
// 波形輔助。這些不驅動 DUT，只是為了讓波形讀得懂。
wire [AW-1:0] ch0_araddr = araddr[0*AW +: AW];
wire [DW-1:0] ch0_rdata  = rdata [0*DW +: DW];
wire          ch0_rvalid = rvalid[0];

// 把封包表頭從寬匯流排裡拆出來，讓內容在波形上直接可讀，
// 而不是一個看不懂的 512-bit 值。位移依你的訊框佈局而定。
wire [47:0]   tx_dst_mac  = tx_tdata[47:0];
wire [15:0]   tx_ethtype  = tx_tdata[111:96];
```

⚠️ **狀態指示訊號要「保持」而不是回到閒置值。**
一個顯示「最近寫入哪條通道」的訊號，若閒置時回到 −1，波形上會是一排被 `0xFFFFFFFF`
隔開的尖刺；改成保持上一個值，就變成清楚的階梯，走訪規則一眼可辨：

```verilog
always @(posedge clk)
    if (rst) ch_num <= 0;
    else for (i = 0; i < N; i = i + 1)
        if (awvalid[i] && awready[i]) ch_num <= i;   // 保持，不回閒置值
```

⚠️ **只在封包第一拍有效的欄位，要從 sop 保持到封包結束。**
PCIe TLP、乙太網 frame 的標頭只在 sop 那一拍有定義。有些 RTL 在後續每一拍都會重算標頭暫存器
（例如 Corundum 的 DMA 寫入引擎用遞減中的 DW 計數重算 length），波形上的 length 就會一路倒數，
看起來像 bug。把 sop 那一拍的值鎖住：

```verilog
reg  [9:0] len_q = 0;                                   // 初值給 0，否則開頭一段是紅色 X
always @(posedge clk) if (valid && ready && sop) len_q <= hdr[105:96];
wire [9:0] tlp_len = (valid && sop) ? hdr[105:96] : len_q;
```

⚠️ **輔助訊號名連 `[msb:lsb]` 在內控制在 13 個字元以內**（原因見上一節 ⑨）。
`desc_len[15:0]` 已經 14 個字元，會被截成 `esc_len[15:0]`；改叫 `d_len`。報告的圖說再寫一次名稱對照。

**不改 DUT 也不包 wrapper 的做法：** 輔助訊號放在一個獨立的頂層模組，以階層參照讀 DUT
（`wire x = dut_top.some_reg;`），與 DUT 一起編譯成兩個 root。cocotb 的 TOPLEVEL 仍是 DUT，
Icarus 加 `-s <輔助模組>` 即可；它也可以順便負責 `$dumpfile` / `$dumpvars`。

### 一張圖只證明一件事

訊號放太多會擠成一團。每張圖只放**證明那一件事所需**的 5–8 個訊號。
好的圖說要寫出「這張圖證明了什麼」，而不是描述畫面上有什麼。

**最有說服力的三類圖**：

| 類型 | 做法 |
|---|---|
| **規則直接可見** | 把索引訊號與它推導出的目標訊號並排，讓兩者的對應關係在波形上逐格可驗。
 位址映射、輪替順序這類「算式」用這種方式呈現，比任何文字說明都有力 |
| **平行度直接可見** | 用 one-hot 的 valid 向量。同一個週期內有幾個位元同時為高，
 就是有幾路同時在動——不需要解釋 |
| **數字直接可讀** | 把設計內部的計數器放進波形，讓它停在最終值、與完成訊號同時。
 報告裡引用的時間數字因此可以在圖上直接讀到，不需要相信任何轉述 |

---

## FSDB 產生方式

```sh
# compile。VERDI_HOME 指向你的 Verdi 安裝目錄，通常 `dirname $(dirname $(which verdi))`
export VERDI_HOME=/path/to/verdi
vcs ... -debug_access+all ...

# testbench，用 plusarg 保護，迴歸行為不受影響
initial if ($test$plusargs("fsdb")) begin
    $fsdbDumpfile("tb.fsdb");
    $fsdbDumpvars(0, tb);
    $fsdbDumpMDA();          // 記憶體陣列
end
```

⚠️ **Verdi 2024.09 廢止了 `-P novas.tab pli.a`。** 用舊旗標時
**VCS 仍能正常編譯與執行，但每個 `$fsdbDump*` 都失敗、不產生任何檔案**，
只留一行容易漏看的訊息。

### 不用 VCS：cocotb + Icarus 的波形

開源流程（cocotb 的測試平台、Icarus 模擬）一樣能用 Verdi 出圖。Icarus 只寫 FST，Verdi 只讀 FSDB，
沒有直接轉換的工具，要經過 VCD：

```sh
fst2vcd -f waves.fst -o waves.vcd          # GTKWave 附帶
grep -A1 '^\$timescale' waves.vcd          # cocotb 預設 1ps；figures 檔的時間就用 ps
vcd2fsdb waves.vcd -o waves.fsdb           # Verdi 附帶
```

figures 檔的時間窗最好不要手算：讓測試程式把每個情境的關鍵事件（握手、第一個請求、狀態）
連同 cycle 數寫進 JSON，時間窗從 JSON 取，報告引用的數字也從同一個 JSON 取。

兩個容易卡住的地方：

- **cocotb-test 0.2.x 與 cocotb 1.7 不相容，import 就失敗。** 很多上游測試檔開頭會
  `import cocotb_test.simulator`（給 pytest 用）。自己寫的測試不要 import 它，用 make 跑。
- **上游 tb 目錄常用 symlink 共用模型檔**（例如 Corundum 的 `pcie_if.py -> ../pcie_if.py`）。
  只複製單一 tb 目錄時 symlink 會斷，cocotb 只報 `No module named ...`。把模型檔實際複製過來。

---

## 量測數據的紀律

### 先分清楚每種手段量的是什麼

不同量測點的數字**不可混用**。報告要先把這件事講清楚，例如：

| 手段 | 量測點 | 注意 |
|---|---|---|
| 模擬 | RTL 邏輯行為 | 記憶體模型是理想化的，不代表真實時序 |
| 硬體計數器 | 設計內部某段忙碌期間 | 要寫清楚起訖點，通常**不含**下游排空 |
| 主機計時 | 含 MMIO 往返與輪詢 | 與硬體計數器對照可量出開銷佔比 |
| 對端計數器 | 收端實際收到多少 | **獨立於發送端**，是丟包與否的權威 |
| 線上擷取 | 實際內容與長度 | 高速下會漏抓，**只能驗內容不能算速率** |

### 測試平台有隨機成分時，報統計而不是單一數字

TB 若用 `$urandom` 模擬回壓，週期數會隨亂數序列變動。**同一執行檔可重現，但改動 TB 就會變**。
掃描數個種子，報平均與標準差：

```sh
for s in 1 7 42 123 999 31337; do ./simv +ntb_random_seed=$s; done
```

並在報告裡明講**這是測試平台的性質，不是設計的性質**。
沒有隨機成分的 TB 則相反——確認種子無關之後，可以當確定值引用。

### 模擬與實機不一致時，說明方向與原因

兩者不一致很正常，但**要說清楚往哪個方向、為什麼**，而且最好兩個方向都有例子：
一條路徑模擬比實機悲觀（TB 模型供料慢），另一條比實機樂觀（模擬沒有下游回壓）。
後者尤其重要——它往往正是「已經打滿上限」的另一種說法，附上反證會更有力：
若模擬值在實機成真，換算會超過物理上限，所以實機的數字不是退化而是必然。

### 規模會影響數字時，列出多個規模

固定成本（管線填充、記憶體延遲）在小規模下佔比過大。
列出三個規模讓收斂趨勢自己說話，比單一數字有說服力得多，也能解釋
為什麼早期記錄的數字偏高。

---

## 自我檢查（不可跳過）

1. **每個推導數字重算一遍。** 寫一段腳本把報告裡的乘除都驗過，不要靠眼睛。
2. **引用的檔案要存在。** 報告提到的腳本、log、路徑逐一確認。
3. **引用的 log 內容要與實際輸出一致**，不要憑印象寫。
4. **波形圖要打開來看。** 檔案存在不等於內容正確——空白面板也是合法的 PNG。
   檔案大小全部相同是空白的徵兆。
5. **標籤平衡、無殘留佔位符、無 emoji。**
6. **整份渲染出來目視檢查。**
7. **與既有報告交叉比對**，同一個數字在不同文件裡不能互相矛盾。
   舊值若出現，確認它是在「說明更正歷程」而不是殘留的錯誤宣稱。

```sh
P=$(mktemp -d)    # a private profile: an open Firefox cannot lock it or take the request over
MOZ_HEADLESS=1 firefox --headless --no-remote --profile "$P" --screenshot "$PWD/out.png" \
  --window-size=1200,30000 "file://$PWD/report.html"
```
⚠️ `--screenshot` 給相對路徑時 firefox **不會報錯也不產生檔案**，一律用絕對路徑。
⚠️ 不加 `--no-remote --profile` 時，若使用者已經開著 Firefox，預設 profile 會被鎖住或請求被接走，
結果同樣是沒有圖、也沒有錯誤訊息。

---

## 組檔

先寫成 `report.html` + `report.css` + `figures/*.png`，最後合成單一檔案：

```sh
python3 scripts/embed.py report.html -o report_standalone.html
```

樣式用 `assets/report.css`：黑白學術風、serif 內文、圖滿版、
`.box` 放重點、`.mono` 標識別字、螢幕優先但列印也乾淨。**禁 emoji。**
內文兩端對齊，但含 `<code>` 或 `.mono` 的段落改為靠左：行尾一長串不能斷行的識別字被推到下一行時，
兩端對齊會把前一行的中文逐字拉開。自訂 CSS 時保留 `p:has(code),p:has(.mono){text-align:left}`
（Firefox 121+、Chrome 105+ 支援 `:has`）。

⚠️ 用 Python 的 `%` 格式化組合中文報告會出事——中文段落裡的「%」會被當成格式指示字元。
用 `str.replace()` 的佔位符替換，並在最後 assert 沒有殘留佔位符。

---

## 附帶的檔案

| 檔案 | 說明 |
|---|---|
| `scripts/verdi_capture.sh` | 由 figures 檔驅動 Verdi 匯出波形：自動調整視窗大小、每個訊號可指定進位制或類比顯示、裁掉工具列與整檔尺規、在暫存目錄執行。完全通用 |
| `scripts/embed.py` | 把 CSS 與圖內嵌成單一 HTML；引用不到會失敗而不是默默略過 |
| `assets/report.css` | 報告樣式 |

**規模參考**：一份成熟的報告大約是七章、十張 Verdi 波形、單一檔案 500 KB 上下。
波形佔掉絕大部分體積，文字本身通常不到 30 KB。
