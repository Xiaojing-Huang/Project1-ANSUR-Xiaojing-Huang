* =========================
* Section 2: Data preparation
* =========================
clear all
set more off
* set working directory to current folder
cd "."
* change this to your own folder
capture log close
log using "proj1_section2.log", replace text

use "ansur2allV2.dta", clear

* ------------------------------------------------------------
* (a) unique id
* ------------------------------------------------------------
capture drop pid
gen long pid = _n
label var pid "unique id"
isid pid

* ------------------------------------------------------------
* missing values: -77/-88/-99 -> Stata special missing
* ------------------------------------------------------------
ds, has(type numeric)
local numvars `r(varlist)'
foreach v of local numvars {
    replace `v' = .a if `v' == -77
    replace `v' = .b if `v' == -88
    replace `v' = .c if `v' == -99
}
misstable summarize
* ------------------------------------------------------------
* fix obvious recording errors (extra zero)
* ------------------------------------------------------------
replace weightkg = weightkg/10 if weightkg > 400 & weightkg < .
replace thumbtipreach = thumbtipreach/10 if thumbtipreach > 2000 & thumbtipreach < .
* ------------------------------------------------------------
* remove under 18 (required)
* ------------------------------------------------------------
count if age < 18
di "under 18 count = " r(N)

preserve
    keep if age < 18
    save "ansur_under18.dta", replace
restore

drop if age < 18

* ------------------------------------------------------------
* convert key measures from mm -> cm (make new variables)
* ------------------------------------------------------------
* stature measures
foreach x in stature kneeheightmidpatella cervicaleheight trochanterionheight ///
             waistheightomphalion functionalleglength footlength thumbtipreach span ///
             chestcircumference hipbreadth hipbreadthsitting bicristalbreadth {
    capture confirm variable `x'
    if _rc==0 {
        capture drop `x'_cm
        gen double `x'_cm = `x'/10 if `x' < .
        label var `x'_cm "`x' (cm)"
    }
}

* ------------------------------------------------------------
* check weight unit and create weight_kg
* ------------------------------------------------------------
capture drop weight_kg
gen double weight_kg = weightkg if weightkg < .
label var weight_kg "measured weight (kg)"

* quick check (look at mean / max)
summ weightkg, detail



summ weight_kg, detail

* ------------------------------------------------------------
* (b) BMI continuous + categorical
* ------------------------------------------------------------
capture drop height_m bmi bmi_cat
gen double height_m = stature/1000 if stature < .
label var height_m "measured height (m)"

gen double bmi = weight_kg/(height_m^2) if weight_kg<. & height_m<. & height_m>0
label var bmi "BMI (kg/m^2)"

gen byte bmi_cat = .
replace bmi_cat = 1 if bmi < 18.5
replace bmi_cat = 2 if bmi >= 18.5 & bmi < 25
replace bmi_cat = 3 if bmi >= 25 & bmi < 30
replace bmi_cat = 4 if bmi >= 30 & bmi < .
label define bmi_cat_lbl 1 "Underweight" 2 "Normal" 3 "Overweight" 4 "Obese", replace
label values bmi_cat bmi_cat_lbl
label var bmi_cat "BMI category"

tab bmi_cat, missing
summ bmi, detail

* ------------------------------------------------------------
* suspect flag (separate from duplicates flag)
* ------------------------------------------------------------
capture drop flag_suspect
gen byte flag_suspect = 0
label var flag_suspect "suspect value (0/1)"

replace flag_suspect = 1 if bmi > 60 & bmi < .
replace flag_suspect = 1 if weight_kg > 300 & weight_kg < .
replace flag_suspect = 1 if stature < 1400 | stature > 2200

tab flag_suspect, missing

* ------------------------------------------------------------
* (c) season from date
* ------------------------------------------------------------
* make sure date is a Stata numeric date
capture confirm numeric variable date
if _rc != 0 {
    * if date is a string like "2012-03-15", change "YMD" if needed
    capture drop date_num
    gen double date_num = daily(date, "YMD")
    format date_num %td
    label var date_num "date (Stata daily date)"
}
else {
    capture drop date_num
    gen double date_num = date
    format date_num %td
}

capture drop mth season
gen byte mth = month(date_num) if date_num < .
label var mth "month of measurement"

gen byte season = .
replace season = 1 if inlist(mth,12,1,2)
replace season = 2 if inlist(mth,3,4,5)
replace season = 3 if inlist(mth,6,7,8)
replace season = 4 if inlist(mth,9,10,11)
label define season_lbl 1 "Winter" 2 "Spring" 3 "Summer" 4 "Fall", replace
label values season season_lbl
label var season "season of measurement"
tab season, missing

* ------------------------------------------------------------
* (d) encode gender and preferred hand
* ------------------------------------------------------------
capture drop gender_n hand_n
capture confirm string variable gender
if _rc==0 {
    encode gender, gen(gender_n)
    label var gender_n "gender (numeric)"
}

capture confirm string variable writingpreference
if _rc==0 {
    encode writingpreference, gen(hand_n)
    label var hand_n "preferred hand (numeric)"
}

* ------------------------------------------------------------
* duplicates: flag + save a copy + drop (keep first)
* ------------------------------------------------------------
capture drop flag_possibledup dup_tag
gen byte flag_possibledup = 0
label var flag_possibledup "possible duplicate (0/1)"

* choose a set of variables to define duplicates
duplicates tag subjectnumeric date_num gender stature weightkg, gen(dup_tag)
replace flag_possibledup = 1 if dup_tag > 0
tab flag_possibledup, missing

preserve
    keep if dup_tag > 0
    save "ansur_dups.dta", replace
restore

sort subjectnumeric date_num gender stature weightkg pid
duplicates drop subjectnumeric date_num gender stature weightkg, force


capture drop gender_n
encode gender, gen(gender_n)
label var gender_n "gender (numeric)"
* ------------------------------------------------------------
* (e) body type (3-6 types; different rules for women and men)
* simple: within each sex, split height and BMI into 3 groups
* ------------------------------------------------------------

capture drop h3 b3 bodytype tmph tmpb
gen byte h3 = .
gen byte b3 = .

levelsof gender_n, local(glist)
foreach g of local glist {

    xtile tmph = stature_cm if gender_n==`g', n(3)
    replace h3 = tmph if gender_n==`g'
    drop tmph

    xtile tmpb = bmi if gender_n==`g', n(3)
    replace b3 = tmpb if gender_n==`g'
    drop tmpb
}

gen byte bodytype = .

replace bodytype = 1 if h3==1 & b3==1
replace bodytype = 2 if h3==1 & b3>=2
replace bodytype = 3 if h3==2
replace bodytype = 4 if h3==3 & b3<=2
replace bodytype = 5 if h3==3 & b3==3

label define bodytype_lbl ///
1 "short + lean" ///
2 "short + heavier" ///
3 "average" ///
4 "tall + lean/avg" ///
5 "tall + heavy", replace
label values bodytype bodytype_lbl
label var bodytype "body type based on height and BMI"

tab bodytype gender, missing

tab bodytype gender, missing
* ------------------------------------------------------------
* (f) 7101: t-shirt size (XS-XXL) based on chest circumference (cm)
* NOTE: you must cite a unisex size guide in the report text
* ------------------------------------------------------------
capture drop tshirt
gen byte tshirt = .

* use Chestcircumference_cm if available
capture confirm variable Chestcircumference_cm
if _rc==0 {
    * simple cutpoints (example). adjust after you pick a sizing guide.
    replace tshirt = 1 if Chestcircumference_cm < 86
    replace tshirt = 2 if Chestcircumference_cm >= 86 & Chestcircumference_cm < 96
    replace tshirt = 3 if Chestcircumference_cm >= 96 & Chestcircumference_cm < 106
    replace tshirt = 4 if Chestcircumference_cm >= 106 & Chestcircumference_cm < 116
    replace tshirt = 5 if Chestcircumference_cm >= 116 & Chestcircumference_cm < 126
    replace tshirt = 6 if Chestcircumference_cm >= 126 & Chestcircumference_cm < .
}

label define tshirt_lbl 1 "XS" 2 "S" 3 "M" 4 "L" 5 "XL" 6 "XXL", replace
label values tshirt tshirt_lbl
label var tshirt "t-shirt size (unisex guide)"

tab tshirt, missing

* ------------------------------------------------------------
* save analysis dataset for later sections
* ------------------------------------------------------------
save "ansur_analysis.dta", replace

log close


* =========================
* Section 3: Sample characteristics
* =========================
* ------------------------------------------------------------
* 3.1(a) Generate statistics describing the anthropometric measures of the sample
* ------------------------------------------------------------

use "ansur_analysis.dta", clear

* use cm variables for body measures
local trunk chestcircumference_cm hipbreadth_cm hipbreadthsitting_cm bicristalbreadth_cm

local staturemeas stature_cm kneeheightmidpatella_cm cervicaleheight_cm ///
                  trochanterionheight_cm waistheightomphalion_cm ///
                  functionalleglength_cm footlength_cm thumbtipreach_cm span_cm

local weight weight_kg

local self weightlbs heightin

capture postutil clear
postfile handle str20 group str30 varname ///
    int N int N_miss int N_suspect ///
    double mean double sd double min double max ///
    using "table3_1a.dta", replace

foreach v of local trunk {
    quietly summarize `v'
    local N = r(N)
    local mean = r(mean)
    local sd = r(sd)
    local min = r(min)
    local max = r(max)

    quietly count if missing(`v')
    local Nmiss = r(N)

    quietly count if flag_suspect==1 & `v'<.
    local Nsusp = r(N)

    post handle ("Trunk") ("`v'") (`N') (`Nmiss') (`Nsusp') ///
        (`mean') (`sd') (`min') (`max')
}

foreach v of local staturemeas {
    quietly summarize `v'
    local N = r(N)
    local mean = r(mean)
    local sd = r(sd)
    local min = r(min)
    local max = r(max)

    quietly count if missing(`v')
    local Nmiss = r(N)

    quietly count if flag_suspect==1 & `v'<.
    local Nsusp = r(N)

    post handle ("Stature/Length") ("`v'") (`N') (`Nmiss') (`Nsusp') ///
        (`mean') (`sd') (`min') (`max')
}

foreach v of local weight {
    quietly summarize `v'
    local N = r(N)
    local mean = r(mean)
    local sd = r(sd)
    local min = r(min)
    local max = r(max)

    quietly count if missing(`v')
    local Nmiss = r(N)

    quietly count if flag_suspect==1 & `v'<.
    local Nsusp = r(N)

    post handle ("Weight") ("`v'") (`N') (`Nmiss') (`Nsusp') ///
        (`mean') (`sd') (`min') (`max')
}

foreach v of local self {
    capture confirm variable `v'
    if _rc==0 {
        quietly summarize `v'
        local N = r(N)
        local mean = r(mean)
        local sd = r(sd)
        local min = r(min)
        local max = r(max)

        quietly count if missing(`v')
        local Nmiss = r(N)

        quietly count if flag_suspect==1 & `v'<.
        local Nsusp = r(N)

        post handle ("Self-reported") ("`v'") (`N') (`Nmiss') (`Nsusp') ///
            (`mean') (`sd') (`min') (`max')
    }
}

postclose handle

use "table3_1a.dta", clear
sort group varname
format mean sd %9.2f
format min max %9.1f

export excel using "Table_3_1-1_anthro_summary.xlsx", firstrow(variables) replace
* ------------------------------------------------------------
* 3.1(b) Figure: height to hip as % of total stature, by sex
* ------------------------------------------------------------

use "ansur_analysis.dta", clear

* make sure hip_pct exists
capture drop hip_pct
gen double hip_pct = (trochanterionheight / stature) * 100 ///
    if trochanterionheight < . & stature < . & stature > 0
label var hip_pct "Height to hip as % of total stature"

* quick check
summ hip_pct, detail
by gender, sort: summ hip_pct

* clean looking boxplot
graph box hip_pct, over(gender, label(labsize(small))) ///
    ytitle("Percent of total height (%)", size(small)) ///
    title("Height to hip as percent of total stature, by sex", size(medium)) ///
    scheme(s2color) ///
    box(1, color(navy)) box(2, color(maroon)) ///
    graphregion(color(white)) ///
    bgcolor(white)

graph export "Fig_3_1-1_hip_pct_by_sex.png", replace

* =========================
* Section 4: Relationships
* =========================
* ------------------------------------------------------------
* 4.1(a) 
* ------------------------------------------------------------
use "ansur_analysis.dta", clear

pwcorr stature_cm kneeheightmidpatella_cm cervicaleheight_cm ///
       trochanterionheight_cm waistheightomphalion_cm ///
       functionalleglength_cm footlength_cm ///
       thumbtipreach_cm span_cm, sig
	   
twoway (scatter cervicaleheight_cm stature_cm) ///
       (lfit cervicaleheight_cm stature_cm), ///
       ytitle("Cervicale height (cm)") ///
       xtitle("Stature (cm)") ///
       title("Relationship between stature and cervicale height") ///
       legend(off) ///
       scheme(s2color)

graph export "Figure_4_1-1.png", replace as(png)

* ------------------------------------------------------------
* 4.1(b) 
* ------------------------------------------------------------
* Females
pwcorr stature_cm kneeheightmidpatella_cm cervicaleheight_cm ///
       trochanterionheight_cm waistheightomphalion_cm ///
       functionalleglength_cm footlength_cm ///
       thumbtipreach_cm span_cm if gender_n==1, sig

* Males
pwcorr stature_cm kneeheightmidpatella_cm cervicaleheight_cm ///
       trochanterionheight_cm waistheightomphalion_cm ///
       functionalleglength_cm footlength_cm ///
       thumbtipreach_cm span_cm if gender_n==2, sig
	   
* ------------------------------------------------------------
* 4.2(a) 
* ------------------------------------------------------------	   
	 use "ansur_analysis.dta", clear

* convert reported weight from lbs to kg
capture drop weight_reported_kg
gen double weight_reported_kg = weightlbs * 0.453592 if weightlbs < .
label var weight_reported_kg "self-reported weight (kg)"
capture drop weight_diff
gen double weight_diff = weight_reported_kg - weight_kg if weight_reported_kg<. & weight_kg<.
label var weight_diff "reported minus measured weight (kg)"
summ weight_diff, detail
histogram weight_diff, normal ///
    xtitle("Difference (kg)") ///
    ytitle("Frequency") ///
    title("Difference between reported and measured weight") ///
    scheme(s2color)

graph export "Figure_4_2-1.png", replace width(2000)  


* ------------------------------------------------------------
* 4.2(b) 
* ------------------------------------------------------------	   
by gender_n, sort: summ weight_diff, detail
graph box weight_diff, over(gender_n) ///
    ytitle("Reported minus measured weight (kg)") ///
    title("Difference between reported and measured weight by sex") ///
    scheme(s2color)
	graph export "Figure_4_2-2.png", replace
	
	
	* 4.2(c)
* ------------------------------------------------

capture drop height_reported_cm
gen double height_reported_cm = heightin * 2.54 if heightin < .
label var height_reported_cm "self-reported height (cm)"
capture drop height_diff
gen double height_diff = height_reported_cm - stature_cm ///
    if height_reported_cm < . & stature_cm < .

label var height_diff "reported minus measured height (cm)"
summ height_diff, detail
histogram height_diff, normal ///
    xtitle("Difference (cm)") ///
    ytitle("Frequency") ///
    title("Difference between reported and measured height") ///
    scheme(s2color)
	graph export "Figure_4_2-3.png", replace
	
	
	* ------------------------------------------------
* 4.3 Body type vs weight and BMI
* ------------------------------------------------

tabstat weight_kg bmi, by(bodytype) ///
    stat(n mean sd min max)
graph box bmi, over(bodytype) ///
    ytitle("BMI (kg/m^2)") ///
    title("BMI distribution by body type") ///
    scheme(s2color)

graph export "Figure_4_3-1.png", replace
graph box weight_kg, over(bodytype) ///
    ytitle("Weight (kg)") ///
    title("Weight distribution by body type") ///
    scheme(s2color)

graph export "Figure_4_3-2.png", replace

* 5(a)
* ----------------------------------------------

twoway ///
    (scatter bmi age if gender_n==1, mcolor(blue)) ///
    (lfit bmi age if gender_n==1, lcolor(blue)) ///
    (scatter bmi age if gender_n==2, mcolor(red)) ///
    (lfit bmi age if gender_n==2, lcolor(red)), ///
    legend(order(1 "Female" 3 "Male")) ///
    ytitle("BMI (kg/m^2)") ///
    xtitle("Age (years)") ///
    title("Association between age and BMI by sex") ///
    scheme(s2color)

graph export "Figure_5_a-1.png", replace

reg bmi age if gender_n==1
reg bmi age if gender_n==2

* 5(b)
* ----------------------------------------------
capture drop age_cat
gen age_cat = .
replace age_cat = 1 if age >=18 & age <=24
replace age_cat = 2 if age >=25 & age <=44
replace age_cat = 3 if age >=45 & age <=64
replace age_cat = 4 if age >=65

label define age_cat_lbl ///
1 "18-24" ///
2 "25-44" ///
3 "45-64" ///
4 "65+", replace

label values age_cat age_cat_lbl
by gender_n age_cat, sort: tabstat bmi, stat(n mean sd)
graph box bmi, over(age_cat) by(gender_n) ///
    ytitle("BMI (kg/m^2)") ///
    title("BMI by age category and sex") ///
    scheme(s2color)

graph export "Figure_5_b-1.png", replace
