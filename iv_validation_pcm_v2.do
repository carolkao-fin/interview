* ============================================================
*  PCM 工具變數有效性驗證 v2（相容 Stata 13.0）
*  改用內建 ivregress + estat，不需要 ranktest / ivreg2
*
*  與 v1 差異：
*    ivreg2 → ivregress 2sls
*    KP rk Wald F → Cragg-Donald F（estat firststage）
*    Hansen J → Sargan/Basmann（estat overid）
*    C-statistic → Wu-Hausman（estat endogenous）
* ============================================================

* ——— 0. 前置設定 ———
cd "C:\Users\User\Downloads"
clear
import excel "paper_patent_final2_revenue_D_1623.xlsx", ///
    sheet("merged_2016_2023") firstrow clear

foreach v of varlist current_ratio BS L_CAR L_FATA L_MSO {
    capture confirm string variable `v'
    if !_rc destring `v', replace force
}
gen PCM2 = PCM^2

* ——— 系統外生變數聯集（不含 i.year）———
local sys_exog size Lev ROA FATA SHY_BR current_ratio age CAR ///
               MSO Stock_Pledging FHC_dummy BS


* ==============================================================
*  第一部分：第一階段 F 檢定
*  直接 OLS 回歸各內生變數，test L_CAR L_FATA L_MSO 聯合顯著性
* ==============================================================

di as text _n "======================================================"
di as text "  第一部分：第一階段 F 檢定"
di as text "======================================================"

* ── 1a. PCM 第一階段 ──
di as text _n "▶ 1a. PCM 第一階段"
reg PCM L_CAR L_FATA L_MSO `sys_exog' i.year
test L_CAR L_FATA L_MSO
scalar f_pcm = r(F)
di as result "   PCM 第一階段 F(L_CAR L_FATA L_MSO) = " f_pcm "  （應 > 10）"

* ── 1b. LI 第一階段（若有 LI 欄位，供比較）──
capture confirm variable LI
if !_rc {
    di as text _n "▶ 1b. LI 第一階段（與 PCM 比較）"
    reg LI L_CAR L_FATA L_MSO `sys_exog' i.year
    test L_CAR L_FATA L_MSO
    scalar f_li = r(F)
    di as result "   LI  第一階段 F = " f_li
    di as result "   PCM 第一階段 F = " f_pcm
    di as text   "   → f_pcm 若遠低於 f_li，代表 IV 對 PCM 較弱"
}

* ── 1c. efficiency_real 第一階段 ──
di as text _n "▶ 1c. efficiency_real 第一階段"
reg efficiency_real L_CAR L_FATA L_MSO `sys_exog' i.year
test L_CAR L_FATA L_MSO
scalar f_eff = r(F)
di as result "   efficiency_real 第一階段 F = " f_eff

* ── 1d. total_acc_app 第一階段 ──
di as text _n "▶ 1d. total_acc_app 第一階段"
reg total_acc_app L_CAR L_FATA L_MSO `sys_exog' i.year
test L_CAR L_FATA L_MSO
scalar f_pat = r(F)
di as result "   total_acc_app 第一階段 F = " f_pat


* ==============================================================
*  第二部分：ivregress 2sls + estat 逐方程式診斷
*
*  estat firststage：第一階段 F（Cragg-Donald F）與 partial R²
*  estat overid   ：Sargan / Basmann 過度識別檢定
*                   p > 0.1 → 過度識別成立（IV 外生）
*
*  各方程式 excluded instruments：
*    方程式 1（efficiency_real）：MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO
*    方程式 2（PCM）            ：FATA BS L_CAR L_FATA L_MSO
*    方程式 3（patent）         ：SHY_BR Stock_Pledging L_CAR L_FATA L_MSO
* ==============================================================

di as text _n "======================================================"
di as text "  第二部分：ivregress 逐方程式診斷（total_acc_app）"
di as text "======================================================"

* ── 方程式 1：efficiency_real ──
di as text _n "▶ 方程式 1：efficiency_real"
ivregress 2sls efficiency_real ///
    size Lev ROA FATA SHY_BR current_ratio age CAR i.year ///
    (PCM total_acc_app = MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO), ///
    robust
estat firststage
estat overid

* ── 方程式 2：PCM（關鍵方程式）──
di as text _n "▶ 方程式 2：PCM（關鍵方程式）"
ivregress 2sls PCM ///
    MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio i.year ///
    (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO), ///
    robust
estat firststage
estat overid

* ── 方程式 3：total_acc_app ──
di as text _n "▶ 方程式 3：total_acc_app"
ivregress 2sls total_acc_app ///
    size MSO FHC_dummy FATA current_ratio age BS Lev ROA CAR i.year ///
    (efficiency_real PCM = SHY_BR Stock_Pledging L_CAR L_FATA L_MSO), ///
    robust
estat firststage
estat overid

* ── 其他專利類型（方程式 3 規格，只換 LHS）──
di as text _n "▶ 其他專利類型（方程式 3）"
foreach pat in invention_acc_app new_acc_app design_acc_app {
    di as text _n "   --- `pat' ---"
    ivregress 2sls `pat' ///
        size MSO FHC_dummy FATA current_ratio age BS Lev ROA CAR i.year ///
        (efficiency_real PCM = SHY_BR Stock_Pledging L_CAR L_FATA L_MSO), ///
        robust
    estat overid
}


* ==============================================================
*  第三部分：PCM 內生性檢定（Wu-Hausman / DWH）
*
*  注意：robust 模式下 estat endogenous 不接受指定單一變數。
*  解法 A（快速）：不加變數名 → 同時測所有內生變數，支援 robust。
*  解法 B（精確）：拿掉 robust，單獨測 PCM，再另跑 robust 版看係數。
*  本腳本同時示範兩種，視需要擇一參考。
* ==============================================================

di as text _n "======================================================"
di as text "  第三部分：PCM 內生性檢定（Wu-Hausman）"
di as text "======================================================"

* ── 3a-A. 解法 A：保留 robust，測所有內生變數（PCM + total_acc_app）──
di as text _n "▶ 3a-A. 所有內生變數聯合內生性（robust，efficiency_real 方程式）"
ivregress 2sls efficiency_real ///
    size Lev ROA FATA SHY_BR current_ratio age CAR i.year ///
    (PCM total_acc_app = MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO), ///
    robust
estat endogenous
* H0：PCM 與 total_acc_app 均外生；p < 0.05 → 至少一個內生

* ── 3a-B. 解法 B：拿掉 robust，單獨測 PCM ──
di as text _n "▶ 3a-B. 單獨測 PCM 內生性（不加 robust）"
ivregress 2sls efficiency_real ///
    size Lev ROA FATA SHY_BR current_ratio age CAR i.year ///
    (PCM total_acc_app = MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO)
estat endogenous PCM
* p < 0.05 → PCM 確實內生，需要 IV

* ── 3b. PCM 方程式角度：測 efficiency_real + total_acc_app（robust）──
di as text _n "▶ 3b. efficiency_real + total_acc_app 聯合內生性（PCM 方程式，robust）"
ivregress 2sls PCM ///
    MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio i.year ///
    (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO), ///
    robust
estat endogenous


* ==============================================================
*  第四部分：LI vs PCM 相似度（若有 LI 欄位）
* ==============================================================

capture confirm variable LI
if !_rc {
    di as text _n "======================================================"
    di as text "  第四部分：LI vs PCM 相似度分析"
    di as text "======================================================"

    di as text _n "▶ 4a. 相關係數"
    pwcorr LI PCM, sig
    di as text "   相關係數 < 0.7 → 差異較大，IV 可能需要重新設計"

    di as text _n "▶ 4b. PCM = f(LI) 的 R²"
    reg PCM LI `sys_exog' i.year
    di as text "   R² 低（< 0.5）→ PCM 不是 LI 的單純替代，需重新考量 IV"

    di as text _n "▶ 4c. LI 版方程式 2（供比較）"
    ivregress 2sls LI ///
        MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio i.year ///
        (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO), ///
        robust
    estat firststage
    estat overid
}


* ==============================================================
*  結果判斷標準摘要
* ==============================================================

di as text _n "======================================================"
di as text "  判斷標準摘要"
di as text "======================================================"
di as text " 指標                              | 通過基準"
di as text " ----------------------------------|------------------------------"
di as text " 第一階段 F（PCM，Part 1）         | > 10"
di as text " Cragg-Donald F（estat firststage）| > 10（嚴格：~16.38）"
di as text " Sargan p-value（estat overid）    | > 0.1 → IV 外生"
di as text " Wu-Hausman p-value（PCM）         | < 0.05 → PCM 確實內生"
di as text " LI vs PCM 相關係數                | > 0.7 → IV 可共用"
