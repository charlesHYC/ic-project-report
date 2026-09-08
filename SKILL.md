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
data         152000     260000    clk ch0_rvalid ch0_rlast ch0_rdata
done        4180000    4262000    clk busy done cycles
```

### 四個會安靜失敗的地方

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
MOZ_HEADLESS=1 firefox --headless --screenshot "$PWD/out.png" \
  --window-size=1200,30000 "file://$PWD/report.html"
```
⚠️ `--screenshot` 給相對路徑時 firefox **不會報錯也不產生檔案**，一律用絕對路徑。

---

## 組檔

先寫成 `report.html` + `report.css` + `figures/*.png`，最後合成單一檔案：

```sh
python3 scripts/embed.py report.html -o report_standalone.html
```

樣式用 `assets/report.css`：黑白學術風、serif 內文、圖滿版、
`.box` 放重點、`.mono` 標識別字、螢幕優先但列印也乾淨。**禁 emoji。**

⚠️ 用 Python 的 `%` 格式化組合中文報告會出事——中文段落裡的「%」會被當成格式指示字元。
用 `str.replace()` 的佔位符替換，並在最後 assert 沒有殘留佔位符。

---

## 附帶的檔案

| 檔案 | 說明 |
|---|---|
| `scripts/verdi_capture.sh` | 由 figures 檔驅動 Verdi 匯出波形。完全通用 |
| `scripts/embed.py` | 把 CSS 與圖內嵌成單一 HTML；引用不到會失敗而不是默默略過 |
| `assets/report.css` | 報告樣式 |

**規模參考**：一份成熟的報告大約是七章、十張 Verdi 波形、單一檔案 500 KB 上下。
波形佔掉絕大部分體積，文字本身通常不到 30 KB。
