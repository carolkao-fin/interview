* ============================================================
*  PCM 工具變數有效性驗證（對應 new14，3SLS 系統）
*  驗證 L_CAR、L_FATA、L_MSO 對 PCM 是否與對 LI 同樣有效
*  執行方式：可接在 new14.do 資料載入段之後執行
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

cap ssc install ivreg2
cap ssc install ranktest

* ——— 系統外生變數聯集（不含 i.year）———
* Eq1: size Lev ROA FATA SHY_BR current_ratio age CAR
* Eq2: MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio
* Eq3: size MSO FHC_dummy FATA current_ratio age BS Lev ROA CAR
local sys_exog size Lev ROA FATA SHY_BR current_ratio age CAR ///
               MSO Stock_Pledging FHC_dummy BS


* ==============================================================
*  第一部分：第一階段 F 檢定
*  目的：L_CAR L_FATA L_MSO 對 PCM 是否夠強（F > 10）
*  以 total_acc_app 示範；其他專利類型 excluded IVs 相同
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
    di as result "   LI  第一階段 F(L_CAR L_FATA L_MSO) = " f_li
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
*  第二部分：ivreg2 逐方程式完整診斷
*  輸出：KP rk Wald F（robust 弱 IV）、Hansen J p-value（外生性）
*
*  各方程式 excluded instruments：
*    方程式 1（efficiency_real）：MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO
*    方程式 2（PCM）            ：FATA BS L_CAR L_FATA L_MSO
*    方程式 3（patent）         ：SHY_BR Stock_Pledging L_CAR L_FATA L_MSO
* ==============================================================

di as text _n "======================================================"
di as text "  第二部分：ivreg2 逐方程式診斷（total_acc_app）"
di as text "======================================================"

* ── 方程式 1：efficiency_real ──
di as text _n "▶ 方程式 1：efficiency_real"
ivreg2 efficiency_real ///
    (PCM total_acc_app = MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO) ///
    size Lev ROA FATA SHY_BR current_ratio age CAR ///
    i.year, robust first

* ── 方程式 2：PCM（關鍵方程式）──
di as text _n "▶ 方程式 2：PCM（關鍵）"
ivreg2 PCM ///
    (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO) ///
    MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio ///
    i.year, robust first

* ── 方程式 3：total_acc_app ──
di as text _n "▶ 方程式 3：total_acc_app"
ivreg2 total_acc_app ///
    (efficiency_real PCM = SHY_BR Stock_Pledging L_CAR L_FATA L_MSO) ///
    size MSO FHC_dummy FATA current_ratio age BS Lev ROA CAR ///
    i.year, robust first

* ── 其他專利類型（方程式 3 規格，只換 LHS）──
di as text _n "▶ 其他專利類型（方程式 3）"
foreach pat in invention_acc_app new_acc_app design_acc_app {
    di as text _n "   --- `pat' ---"
    ivreg2 `pat' ///
        (efficiency_real PCM = SHY_BR Stock_Pledging L_CAR L_FATA L_MSO) ///
        size MSO FHC_dummy FATA current_ratio age BS Lev ROA CAR ///
        i.year, robust
    di as result "   Hansen J p = " e(jp) "   KP rk Wald F = " e(rkf)
}


* ==============================================================
*  第三部分：PCM 內生性檢定（C-statistic / DWH）
*  H0：PCM 外生
*  p < 0.05 → PCM 確實內生，需要 IV
*  p >= 0.05 → PCM 可能外生，OLS 更有效率
* ==============================================================

di as text _n "======================================================"
di as text "  第三部分：PCM 內生性檢定（C-statistic）"
di as text "======================================================"

* ── 3a. 從 efficiency_real 方程式檢定 PCM 的內生性 ──
di as text _n "▶ 3a. PCM 內生性（efficiency_real 方程式角度）"
ivreg2 efficiency_real ///
    (PCM total_acc_app = MSO Stock_Pledging FHC_dummy BS L_CAR L_FATA L_MSO) ///
    size Lev ROA FATA SHY_BR current_ratio age CAR ///
    i.year, robust endog(PCM)

* ── 3b. 從 PCM 方程式：efficiency_real 與 total_acc_app 的內生性 ──
di as text _n "▶ 3b. efficiency_real + total_acc_app 的內生性（PCM 方程式角度）"
ivreg2 PCM ///
    (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO) ///
    MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio ///
    i.year, robust endog(efficiency_real total_acc_app)


* ==============================================================
*  第四部分：LI vs PCM 相似度（若資料中同時有 LI）
*  相關係數 < 0.7 → PCM 與 LI 差異大，原 IV 適用性存疑
* ==============================================================

capture confirm variable LI
if !_rc {
    di as text _n "======================================================"
    di as text "  第四部分：LI vs PCM 相似度分析"
    di as text "======================================================"

    * ── 4a. 相關係數 ──
    di as text _n "▶ 4a. 相關係數"
    pwcorr LI PCM, sig
    di as text "   相關係數 < 0.7 → 差異較大，IV 可能需要重新設計"

    * ── 4b. PCM 對 LI 的回歸（控制其他外生變數）──
    di as text _n "▶ 4b. PCM = f(LI) 的 R²"
    reg PCM LI `sys_exog' i.year
    di as text "   R² 低（< 0.5）→ PCM 不是 LI 的單純替代，需重新考量 IV"

    * ── 4c. LI 版方程式 2（供與 PCM 版對照 KP F 與 Hansen J）──
    di as text _n "▶ 4c. LI 版方程式 2（ivreg2，供比較）"
    ivreg2 LI ///
        (efficiency_real total_acc_app = FATA BS L_CAR L_FATA L_MSO) ///
        MSO age CAR Stock_Pledging FHC_dummy Lev ROA size SHY_BR current_ratio ///
        i.year, robust first
}


* ==============================================================
*  結果判斷標準摘要
* ==============================================================

di as text _n "======================================================"
di as text "  判斷標準摘要"
di as text "======================================================"
di as text " 指標                          | 通過基準"
di as text " ------------------------------|------------------------------"
di as text " 第一階段 F（PCM）             | > 10"
di as text " Kleibergen-Paap rk Wald F     | > 10（嚴格：~16.38）"
di as text " Hansen J p-value（PCM eq.）   | > 0.1 → IV 外生"
di as text " C-statistic p-value（PCM）    | < 0.05 → PCM 確實內生"
di as text " LI vs PCM 相關係數            | > 0.7 → IV 可共用"
