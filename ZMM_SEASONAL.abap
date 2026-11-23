*&---------------------------------------------------------------------*
*& Report ZMM_SEASONAL
*&---------------------------------------------------------------------*
*& Seasonal forward buying of raw materials - SAP S/4HANA (ABAP 7.5+)
*& Read-only: the report changes nothing in SAP.
*&
*& BUSINESS QUESTION
*&   Some products are produced mainly in a few months of the year, and
*&   some raw materials are cheaper in certain months. Which raw materials
*&   of seasonal products can be bought ahead in their cheap months,
*&   within their shelf life?
*&
*& TAB 1 "Seasonal products"
*&   Products (default type FERT) with their production per calendar
*&   month (goods receipts 101-102 from production orders), the share of
*&   the 3 biggest months ("top-3 share") and the peak month.
*&   SEASONAL = top-3 share >= min. % AND the same 3 months hold >= min. %
*&   of production in at least "min. years" years AND at least
*&   "min. production orders" orders (one-off batches are not seasons).
*&   Click a product -> raw materials of its MULTI-LEVEL BOM
*&   (CS_BOM_EXPL_MAT_V2, PP01). Without an active BOM, the raw materials
*&   actually issued (261-262) to its orders and to the orders of its
*&   semi-finished products (by their share) are used instead.
*&   Per raw material: cheapest, 2nd cheapest and dearest month, months
*&   between cheapest month and product peak, shelf life and an advice.
*&   Click a raw material -> price chart.
*&
*& TAB 2 "Raw-material prices"
*&   Raw materials (default type ROH) with the AVERAGE PURCHASE PRICE per
*&   calendar month. Checkbox: only raw materials with a seasonal pattern.
*&   Click a row or button [Chart] -> price chart.
*&
*& PRICE LOGIC (per raw material)
*&   1. Purchases = goods receipts 101 - 102 on purchase orders (MATDOC),
*&      base unit, company code currency. Left out: stock transfers from
*&      own plants (EKKO-RESWK) and consignment (special stock K).
*&   2. Average price per calendar month = value / quantity (all years).
*&   3. Cheapest / 2nd cheapest / dearest month from step 2; Diff 1st-2nd
*&      and Gap in % of the cheapest month's price.
*&   4. Per year: index = month price / average price of that year
*&      (years with >= 6 purchase months). Years OK = years in which the
*&      cheapest month was cheaper than the dearest month.
*&   5. SEASONAL = gap >= min. gap % AND years OK >= min. years.
*&
*& UI: tabbed selection screen, SALV lists with hotspots and cell colours
*&   (dark green = cheapest / peak, light green = 2nd, red = dearest),
*&   popup drill-down, HTML/SVG chart window with prices and index per
*&   year, Help buttons explaining every field and column.
*&
*& AUTHORIZATION: prices are shown -> authority check M_MSEG_WMB
*&   (activity 03) on the plant. Give the transaction to purchasing only.
*&
*& LIMITATIONS
*&   - Price at goods receipt (PO price); invoice differences and
*&     separately posted delivery costs are not included.
*&   - Today's BOM is used for the product -> raw material link.
*&   - Chart needs SAP GUI for Windows (HTML control).
*&---------------------------------------------------------------------*
REPORT zmm_seasonal.

TABLES sscrfields.

*----------------------------------------------------------------------*
* Helper fields used only to type the SELECT-OPTIONS
*----------------------------------------------------------------------*
DATA: gv_sel_matnr TYPE mara-matnr,
      gv_sel_mtart TYPE mara-mtart,
      gv_sel_budat TYPE matdoc-budat.

TYPES ty_qty TYPE p LENGTH 16 DECIMALS 3.
TYPES ty_q6  TYPE p LENGTH 16 DECIMALS 6.
TYPES ty_val TYPE p LENGTH 16 DECIMALS 2.
TYPES ty_prc TYPE p LENGTH 16 DECIMALS 4.
TYPES ty_pct TYPE p LENGTH 6 DECIMALS 1.
TYPES ty_pc2 TYPE p LENGTH 6 DECIMALS 2.
TYPES tr_matnr TYPE RANGE OF mara-matnr.
TYPES tr_mtart TYPE RANGE OF mara-mtart.

CONSTANTS gc_min_months TYPE i VALUE 6.   " purchase months for a year to count

*----------------------------------------------------------------------*
* Selection screen
*   Toolbar button [Help] (F-key 1) explains every field and button.
*----------------------------------------------------------------------*
SELECTION-SCREEN FUNCTION KEY 1.

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME TITLE t_b0.
  PARAMETERS     p_werks  TYPE t001w-werks OBLIGATORY DEFAULT '1000'.
  SELECT-OPTIONS s_budat  FOR gv_sel_budat OBLIGATORY.
  SELECT-OPTIONS s_rmtart FOR gv_sel_mtart.
  PARAMETERS     p_gap    TYPE ty_pc2 DEFAULT 5.
  PARAMETERS     p_years  TYPE i DEFAULT 2.
SELECTION-SCREEN END OF BLOCK b0.

" Fields of the tabs are placed in lines with their own label (COMMENT):
" in a tab (subscreen) labels set with %_..._APP_% are not shown.
SELECTION-SCREEN BEGIN OF SCREEN 101 AS SUBSCREEN.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) c_pmtart FOR FIELD s_pmtart.
    SELECT-OPTIONS s_pmtart FOR gv_sel_mtart.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) c_pmatnr FOR FIELD s_pmatnr.
    SELECT-OPTIONS s_pmatnr FOR gv_sel_matnr.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) c_top3 FOR FIELD p_top3.
    PARAMETERS p_top3 TYPE ty_pct DEFAULT 60.
  SELECTION-SCREEN END OF LINE.
  " minimum number of production orders in the period
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) c_minord FOR FIELD p_minord.
    PARAMETERS p_minord TYPE i DEFAULT 12.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_onlyp AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 3(40) c_onlyp FOR FIELD p_onlyp.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF SCREEN 101.

SELECTION-SCREEN BEGIN OF SCREEN 102 AS SUBSCREEN.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) c_rmatnr FOR FIELD s_rmatnr.
    SELECT-OPTIONS s_rmatnr FOR gv_sel_matnr.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_onlyr AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 3(40) c_onlyr FOR FIELD p_onlyr.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF SCREEN 102.

SELECTION-SCREEN BEGIN OF TABBED BLOCK tabs FOR 6 LINES.
  SELECTION-SCREEN TAB (30) t_tab1 USER-COMMAND tab1 DEFAULT SCREEN 101.
  SELECTION-SCREEN TAB (30) t_tab2 USER-COMMAND tab2 DEFAULT SCREEN 102.
SELECTION-SCREEN END OF BLOCK tabs.

SELECTION-SCREEN BEGIN OF BLOCK b5 WITH FRAME TITLE t_b5.
  SELECTION-SCREEN COMMENT /1(79) c_h1.
  SELECTION-SCREEN COMMENT /1(79) c_h2.
  SELECTION-SCREEN COMMENT /1(79) c_h3.
  SELECTION-SCREEN COMMENT /1(79) c_h4.
SELECTION-SCREEN END OF BLOCK b5.

" Window for the price chart (filled with an HTML control at runtime)
SELECTION-SCREEN BEGIN OF SCREEN 200 AS WINDOW TITLE t_200.
  SELECTION-SCREEN COMMENT /1(79) c_200.
SELECTION-SCREEN END OF SCREEN 200.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_ym,                  " purchases per material/year/month
         matnr TYPE mara-matnr,
         yr    TYPE c LENGTH 4,
         mon   TYPE c LENGTH 2,
         meins TYPE mara-meins,
         waers TYPE waers,
         qty   TYPE ty_qty,
         value TYPE ty_val,
       END OF ty_ym.

TYPES: BEGIN OF ty_yidx,                " price index per material/year/month
         matnr TYPE mara-matnr,
         yr    TYPE c LENGTH 4,
         mon   TYPE i,
         idx   TYPE f,
       END OF ty_yidx.

TYPES: BEGIN OF ty_stat,                " result per raw material
         matnr     TYPE mara-matnr,
         maktx     TYPE makt-maktx,
         seasonal  TYPE c LENGTH 3,
         status    TYPE c LENGTH 30,
         cheap1    TYPE c LENGTH 3,
         cheap2    TYPE c LENGTH 3,
         diff12    TYPE ty_pc2,
         dear      TYPE c LENGTH 3,
         gap       TYPE ty_pc2,
         years_ok  TYPE i,
         years_val TYPE i,
         pmonths   TYPE i,
         shelf_m   TYPE i,
         meins     TYPE mara-meins,
         waers     TYPE waers,
         m01       TYPE ty_prc,
         m02       TYPE ty_prc,
         m03       TYPE ty_prc,
         m04       TYPE ty_prc,
         m05       TYPE ty_prc,
         m06       TYPE ty_prc,
         m07       TYPE ty_prc,
         m08       TYPE ty_prc,
         m09       TYPE ty_prc,
         m10       TYPE ty_prc,
         m11       TYPE ty_prc,
         m12       TYPE ty_prc,
         c1        TYPE i,
         c2        TYPE i,
         cd        TYPE i,
         t_color   TYPE lvc_t_scol,
       END OF ty_stat.

TYPES: BEGIN OF ty_prod,                " result per product
         matnr   TYPE mara-matnr,
         maktx   TYPE makt-maktx,
         class   TYPE c LENGTH 15,
         top3    TYPE ty_pct,
         peak    TYPE c LENGTH 3,
         total   TYPE ty_qty,
         meins   TYPE mara-meins,
         p01     TYPE ty_pct,
         p02     TYPE ty_pct,
         p03     TYPE ty_pct,
         p04     TYPE ty_pct,
         p05     TYPE ty_pct,
         p06     TYPE ty_pct,
         p07     TYPE ty_pct,
         p08     TYPE ty_pct,
         p09     TYPE ty_pct,
         p10     TYPE ty_pct,
         p11     TYPE ty_pct,
         p12     TYPE ty_pct,
         nmonths  TYPE i,                 " months with production
         nyears   TYPE i,
         years_ok TYPE i,
         orders   TYPE i,
         peak_n  TYPE i,
         t_color  TYPE lvc_t_scol,        " coloured months
       END OF ty_prod.

TYPES: BEGIN OF ty_comp,                " raw material of a product's BOM
         idnrk    TYPE mara-matnr,
         maktx    TYPE makt-maktx,
         stufe    TYPE i,
         qty      TYPE ty_q6,
         meins    TYPE mara-meins,
         seasonal TYPE c LENGTH 3,
         cheap1   TYPE c LENGTH 3,
         cheap2   TYPE c LENGTH 3,
         diff12   TYPE ty_pc2,
         dear     TYPE c LENGTH 3,
         gap      TYPE ty_pc2,
         years_ok TYPE i,
         lead     TYPE i,
         shelf_m  TYPE i,
         advice   TYPE c LENGTH 60,
         t_color  TYPE lvc_t_scol,
       END OF ty_comp.

" goods issues per material (fallback without BOM)
TYPES: BEGIN OF ty_use,
         matnr TYPE mara-matnr,
         mtart TYPE mara-mtart,
         meins TYPE mara-meins,
         qty   TYPE ty_qty,
       END OF ty_use,
       tt_use TYPE STANDARD TABLE OF ty_use WITH EMPTY KEY.

TYPES: BEGIN OF ty_help,
         line TYPE c LENGTH 120,
       END OF ty_help.

*----------------------------------------------------------------------*
* Application class
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA gv_chart_matnr TYPE mara-matnr.
    CLASS-METHODS run_products.
    CLASS-METHODS run_rawmat.
    CLASS-METHODS build_chart.
    CLASS-METHODS show_help.
    CLASS-METHODS on_dbl_prod FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    CLASS-METHODS on_dbl_comp FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    CLASS-METHODS on_dbl_raw FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    CLASS-METHODS on_function FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
    " single click on the material number (hotspot)
    CLASS-METHODS on_link_main FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
    CLASS-METHODS on_link_comp FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
    CLASS-METHODS set_hotspot
      IMPORTING io_salv TYPE REF TO cl_salv_table
                iv_col  TYPE lvc_fname.

  PRIVATE SECTION.
    CLASS-DATA: gt_ym    TYPE SORTED TABLE OF ty_ym WITH NON-UNIQUE KEY matnr yr mon,
                gt_yidx  TYPE SORTED TABLE OF ty_yidx WITH NON-UNIQUE KEY matnr yr mon,
                gt_stat  TYPE SORTED TABLE OF ty_stat WITH UNIQUE KEY matnr,
                gt_raw   TYPE STANDARD TABLE OF ty_stat WITH EMPTY KEY,
                gt_prod  TYPE STANDARD TABLE OF ty_prod WITH EMPTY KEY,
                gt_comp  TYPE STANDARD TABLE OF ty_comp WITH EMPTY KEY,
                gt_help  TYPE STANDARD TABLE OF ty_help WITH EMPTY KEY,
                gt_html  TYPE STANDARD TABLE OF w3html WITH EMPTY KEY,
                go_main  TYPE REF TO cl_salv_table,
                go_comp  TYPE REF TO cl_salv_table,
                go_dock  TYPE REF TO cl_gui_docking_container,
                go_html  TYPE REF TO cl_gui_html_viewer,
                gv_mode  TYPE c LENGTH 1,          " P = products, R = raw materials
                gv_src   TYPE c LENGTH 1.          " B = BOM, A = actual goods issues

    CLASS-METHODS load_prices
      IMPORTING it_matnr TYPE tr_matnr
                it_mtart TYPE tr_mtart.
    CLASS-METHODS calc_stats.
    CLASS-METHODS calc_one IMPORTING iv_matnr TYPE mara-matnr.
    CLASS-METHODS show_components IMPORTING is_prod TYPE ty_prod.
    " fallback from goods issues when no active BOM
    CLASS-METHODS get_use
      IMPORTING iv_matnr      TYPE mara-matnr
      RETURNING VALUE(rt_use) TYPE tt_use.
    CLASS-METHODS actual_comps
      IMPORTING iv_matnr TYPE mara-matnr
      CHANGING  ct_range TYPE tr_matnr.
    CLASS-METHODS add_comp
      IMPORTING iv_matnr TYPE mara-matnr
                iv_meins TYPE mara-meins
                iv_qty   TYPE ty_q6
                iv_level TYPE i
      CHANGING  ct_range TYPE tr_matnr.
    CLASS-METHODS open_chart IMPORTING iv_matnr TYPE mara-matnr.
    CLASS-METHODS month_name
      IMPORTING iv_month       TYPE i
      RETURNING VALUE(rv_name) TYPE char3.
    CLASS-METHODS green RETURNING VALUE(rt_color) TYPE lvc_t_scol.
    " colours for single cells
    CLASS-METHODS cell_colors
      IMPORTING iv_c1           TYPE i
                iv_c2           TYPE i
                iv_cd           TYPE i
                iv_months       TYPE abap_bool
      RETURNING VALUE(rt_color) TYPE lvc_t_scol.
    CLASS-METHODS add IMPORTING iv_text TYPE csequence.
    CLASS-METHODS set_columns IMPORTING io_salv TYPE REF TO cl_salv_table.
    CLASS-METHODS col_text
      IMPORTING iv_name        TYPE lvc_fname
      RETURNING VALUE(rv_text) TYPE scrtext_l.
    " short header (10 characters)
    CLASS-METHODS col_short
      IMPORTING iv_name        TYPE lvc_fname
      RETURNING VALUE(rv_text) TYPE scrtext_s.
    CLASS-METHODS display_main
      CHANGING ct_table TYPE STANDARD TABLE.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

*----------------------------------------------------------------------*
* TAB 1: seasonal products
*----------------------------------------------------------------------*
  METHOD run_products.
    " per year as well, so that the pattern must repeat
    TYPES: BEGIN OF ty_rk, mon TYPE i, q TYPE f, END OF ty_rk.
    TYPES: BEGIN OF ty_yq, yr TYPE c LENGTH 4, mon TYPE i, q TYPE f, END OF ty_yq.
    DATA: lt_mq    TYPE STANDARD TABLE OF f WITH EMPTY KEY,
          lt_rk    TYPE STANDARD TABLE OF ty_rk WITH EMPTY KEY,
          lt_yq    TYPE STANDARD TABLE OF ty_yq WITH EMPTY KEY,
          lt_yrs   TYPE SORTED TABLE OF char4 WITH UNIQUE KEY table_line,
          ls_p     TYPE ty_prod,
          lv_tot   TYPE f,
          lv_top   TYPE f,
          lv_ytot  TYPE f,
          lv_ytop  TYPE f.

    gv_mode = 'P'.
    " Production per product, year and month
    SELECT d~matnr,
           substring( d~budat, 1, 4 )                                AS yr,
           substring( d~budat, 5, 2 )                                AS mon,
           d~meins,
           SUM( CASE WHEN d~shkzg = 'S' THEN d~menge
                     ELSE d~menge * -1 END )                         AS qty,
           COUNT( DISTINCT d~aufnr )                                 AS nord
      FROM matdoc AS d
      INNER JOIN mara AS m ON m~matnr = d~matnr
      WHERE d~record_type = 'MDOC'
        AND d~werks       = @p_werks
        AND d~budat      IN @s_budat
        AND d~bwart      IN ('101','102')
        AND d~aufnr      <> ' '
        AND m~mtart      IN @s_pmtart
        AND d~matnr      IN @s_pmatnr
      GROUP BY d~matnr, substring( d~budat, 1, 4 ), substring( d~budat, 5, 2 ), d~meins
      INTO TABLE @DATA(lt_pm).

    LOOP AT lt_pm INTO DATA(ls_pm)
         GROUP BY ( matnr = ls_pm-matnr meins = ls_pm-meins ) INTO DATA(lg_pm).
      CLEAR: ls_p, lt_yq, lt_yrs, lt_rk.
      lt_mq = VALUE #( FOR i = 1 UNTIL i > 12 ( CONV f( 0 ) ) ).
      LOOP AT GROUP lg_pm INTO DATA(ls_mm).
        DATA(lv_m) = CONV i( ls_mm-mon ).
        IF lv_m BETWEEN 1 AND 12 AND ls_mm-qty > 0.
          lt_mq[ lv_m ] = lt_mq[ lv_m ] + ls_mm-qty.
          APPEND VALUE #( yr = ls_mm-yr mon = lv_m q = ls_mm-qty ) TO lt_yq.
          INSERT ls_mm-yr INTO TABLE lt_yrs.
          ls_p-orders = ls_p-orders + ls_mm-nord.
        ENDIF.
      ENDLOOP.
      lv_tot = REDUCE f( INIT s = CONV f( 0 ) FOR w IN lt_mq NEXT s = s + w ).
      CHECK lv_tot > 0.

      " Months ranked by quantity: top 3 (only months with production)
      DO 12 TIMES.
        IF lt_mq[ sy-index ] > 0.
          APPEND VALUE #( mon = sy-index q = lt_mq[ sy-index ] ) TO lt_rk.
        ENDIF.
      ENDDO.
      SORT lt_rk BY q DESCENDING.
      DATA(lv_nmon) = lines( lt_rk ).
      DELETE lt_rk FROM 4.
      lv_top = REDUCE f( INIT s = CONV f( 0 ) FOR r IN lt_rk NEXT s = s + r-q ).

      ls_p-matnr  = lg_pm-matnr.
      ls_p-meins  = lg_pm-meins.
      ls_p-total  = lv_tot.
      ls_p-top3   = lv_top / lv_tot * 100.
      ls_p-nyears = lines( lt_yrs ).
      ls_p-nmonths = lv_nmon.
      ls_p-peak_n = lt_rk[ 1 ]-mon.
      ls_p-peak   = month_name( ls_p-peak_n ).

      " Does the pattern repeat? Per year: share of that year's production
      " in the same top-3 months must be >= min. top-3 share
      LOOP AT lt_yrs INTO DATA(lv_yr).
        CLEAR: lv_ytot, lv_ytop.
        LOOP AT lt_yq INTO DATA(ls_yq) WHERE yr = lv_yr.
          lv_ytot = lv_ytot + ls_yq-q.
          IF line_exists( lt_rk[ mon = ls_yq-mon ] ).
            lv_ytop = lv_ytop + ls_yq-q.
          ENDIF.
        ENDLOOP.
        IF lv_ytot > 0 AND lv_ytop / lv_ytot * 100 >= p_top3.
          ls_p-years_ok = ls_p-years_ok + 1.
        ENDIF.
      ENDLOOP.

      IF ls_p-top3 >= p_top3 AND ls_p-years_ok >= p_years AND ls_p-orders >= p_minord.
        ls_p-class = 'Seasonal'.
      ELSEIF ls_p-nyears < p_years.
        ls_p-class = 'Too few years'.
      ELSEIF ls_p-orders < p_minord.
        ls_p-class = 'Too few orders'.
      ELSEIF ls_p-top3 < p_top3.
        ls_p-class = 'Not seasonal'.
      ELSE.
        ls_p-class = 'Not repeated'.
      ENDIF.
      IF p_onlyp = abap_true AND ls_p-class <> 'Seasonal'.
        CONTINUE.
      ENDIF.

      " Share per month; colour: peak = dark green, 2nd/3rd month = light green
      DO 12 TIMES.
        ASSIGN COMPONENT |P{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| OF STRUCTURE ls_p
               TO FIELD-SYMBOL(<lv_share>).
        <lv_share> = lt_mq[ sy-index ] / lv_tot * 100.
      ENDDO.
      LOOP AT lt_rk INTO DATA(ls_rk).
        APPEND VALUE #( fname     = |P{ ls_rk-mon WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
                        color-col = 5
                        color-int = COND #( WHEN sy-tabix = 1 THEN 1 ELSE 0 )
                        color-inv = 0 ) TO ls_p-t_color.
      ENDLOOP.

      SELECT SINGLE maktx FROM makt
        WHERE matnr = @ls_p-matnr AND spras = @sy-langu
        INTO @ls_p-maktx.
      APPEND ls_p TO gt_prod.
    ENDLOOP.

    IF gt_prod IS INITIAL.
      MESSAGE 'No products found for this selection' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    SORT gt_prod BY years_ok DESCENDING top3 DESCENDING total DESCENDING.
    display_main( CHANGING ct_table = gt_prod ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* TAB 2: raw materials and their monthly average prices
*----------------------------------------------------------------------*
  METHOD run_rawmat.
    gv_mode = 'R'.
    load_prices( it_matnr = s_rmatnr[] it_mtart = s_rmtart[] ).
    calc_stats( ).
    gt_raw = gt_stat.
    IF p_onlyr = abap_true.
      DELETE gt_raw WHERE seasonal <> 'Yes'.
    ENDIF.
    IF gt_raw IS INITIAL.
      MESSAGE 'No raw materials found for this selection' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    SORT gt_raw BY gap DESCENDING.
    display_main( CHANGING ct_table = gt_raw ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Purchases per raw material, year and month (101-102 on POs)
*----------------------------------------------------------------------*
  METHOD load_prices.
    DATA lt_new TYPE STANDARD TABLE OF ty_ym WITH EMPTY KEY.

    SELECT d~matnr,
           substring( d~budat, 1, 4 )                                AS yr,
           substring( d~budat, 5, 2 )                                AS mon,
           d~meins,
           d~waers,
           SUM( CASE WHEN d~shkzg = 'S' THEN d~menge
                     ELSE d~menge * -1 END )                         AS qty,
           SUM( CASE WHEN d~shkzg = 'S' THEN d~dmbtr
                     ELSE d~dmbtr * -1 END )                         AS value
      FROM matdoc AS d
      INNER JOIN ekko AS k ON k~ebeln = d~ebeln
      INNER JOIN mara AS m ON m~matnr = d~matnr
      WHERE d~record_type = 'MDOC'
        AND d~werks       = @p_werks
        AND d~budat      IN @s_budat
        AND d~bwart      IN ('101','102')
        AND d~ebeln      <> ' '
        AND d~sobkz      <> 'K'
        AND k~reswk       = ' '
        AND m~mtart      IN @it_mtart
        AND d~matnr      IN @it_matnr
      GROUP BY d~matnr, substring( d~budat, 1, 4 ), substring( d~budat, 5, 2 ),
               d~meins, d~waers
      INTO CORRESPONDING FIELDS OF TABLE @lt_new.

    LOOP AT lt_new INTO DATA(ls_new).
      IF NOT line_exists( gt_stat[ matnr = ls_new-matnr ] ).
        INSERT ls_new INTO TABLE gt_ym.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD calc_stats.
    DATA lt_mat TYPE SORTED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    LOOP AT gt_ym INTO DATA(ls_y).
      INSERT ls_y-matnr INTO TABLE lt_mat.
    ENDLOOP.
    LOOP AT lt_mat INTO DATA(lv_matnr).
      IF NOT line_exists( gt_stat[ matnr = lv_matnr ] ).
        calc_one( lv_matnr ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Seasonal price pattern of one raw material (see header, steps 2-6)
*----------------------------------------------------------------------*
  METHOD calc_one.
    TYPES: BEGIN OF ty_mp, mon TYPE i, p TYPE f, END OF ty_mp.
    TYPES: BEGIN OF ty_rk, mon TYPE i, idx TYPE f, END OF ty_rk.
    DATA: lt_q     TYPE STANDARD TABLE OF f WITH EMPTY KEY,
          lt_v     TYPE STANDARD TABLE OF f WITH EMPTY KEY,
          lt_s     TYPE STANDARD TABLE OF f WITH EMPTY KEY,
          lt_n     TYPE STANDARD TABLE OF i WITH EMPTY KEY,
          lt_years TYPE SORTED TABLE OF char4 WITH UNIQUE KEY table_line,
          lt_mp    TYPE STANDARD TABLE OF ty_mp WITH EMPTY KEY,
          lt_rk    TYPE STANDARD TABLE OF ty_rk WITH EMPTY KEY,
          ls_st    TYPE ty_stat,
          lv_mean  TYPE f,
          lv_idx   TYPE f,
          lv_mhd   TYPE mara-mhdhb,
          lv_ipr   TYPE mara-iprkz,
          lv_days  TYPE i.

    lt_q = VALUE #( FOR i = 1 UNTIL i > 12 ( CONV f( 0 ) ) ).
    lt_v = lt_q.
    lt_s = lt_q.
    lt_n = VALUE #( FOR j = 1 UNTIL j > 12 ( 0 ) ).
    ls_st-matnr = iv_matnr.

    " 1) totals per calendar month, years with purchases
    LOOP AT gt_ym INTO DATA(ls_y) WHERE matnr = iv_matnr.
      DATA(lv_m) = CONV i( ls_y-mon ).
      CHECK lv_m BETWEEN 1 AND 12.
      ls_st-meins = ls_y-meins.
      ls_st-waers = ls_y-waers.
      lt_q[ lv_m ] = lt_q[ lv_m ] + ls_y-qty.
      lt_v[ lv_m ] = lt_v[ lv_m ] + ls_y-value.
      IF ls_y-qty > 0 AND ls_y-value > 0.
        ls_st-pmonths = ls_st-pmonths + 1.
        INSERT ls_y-yr INTO TABLE lt_years.
      ENDIF.
    ENDLOOP.

    " 2) average price per calendar month (all years)
    DO 12 TIMES.
      ASSIGN COMPONENT |M{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| OF STRUCTURE ls_st
             TO FIELD-SYMBOL(<lv_price>).
      IF lt_q[ sy-index ] > 0 AND lt_v[ sy-index ] > 0.
        <lv_price> = lt_v[ sy-index ] / lt_q[ sy-index ].
      ENDIF.
    ENDDO.

    " 3) index per year = month price / average price of that year
    LOOP AT lt_years INTO DATA(lv_yr).
      CLEAR lt_mp.
      LOOP AT gt_ym INTO ls_y WHERE matnr = iv_matnr AND yr = lv_yr.
        IF ls_y-qty > 0 AND ls_y-value > 0.
          APPEND VALUE #( mon = CONV i( ls_y-mon ) p = ls_y-value / ls_y-qty ) TO lt_mp.
        ENDIF.
      ENDLOOP.
      IF lines( lt_mp ) < gc_min_months.
        CONTINUE.
      ENDIF.
      ls_st-years_val = ls_st-years_val + 1.
      lv_mean = REDUCE f( INIT s = CONV f( 0 ) FOR w IN lt_mp NEXT s = s + w-p ) / lines( lt_mp ).
      LOOP AT lt_mp INTO DATA(ls_mp).
        lv_idx = ls_mp-p / lv_mean.
        INSERT VALUE #( matnr = iv_matnr yr = lv_yr mon = ls_mp-mon idx = lv_idx ) INTO TABLE gt_yidx.
        lt_s[ ls_mp-mon ] = lt_s[ ls_mp-mon ] + lv_idx.
        lt_n[ ls_mp-mon ] = lt_n[ ls_mp-mon ] + 1.
      ENDLOOP.
    ENDLOOP.

    " 4)+5) ranking by the AVERAGE PURCHASE PRICE of the month (all years
    " together = the Avg price columns): cheapest / dearest are the months
    " with the lowest / highest average price shown in the list.
    DO 12 TIMES.
      IF lt_q[ sy-index ] > 0 AND lt_v[ sy-index ] > 0.
        APPEND VALUE #( mon = sy-index idx = lt_v[ sy-index ] / lt_q[ sy-index ] ) TO lt_rk.
      ENDIF.
    ENDDO.
    SORT lt_rk BY idx ASCENDING.

    IF lines( lt_rk ) < 2.
      ls_st-seasonal = 'No'.
      ls_st-status   = 'Too few purchase months'.
    ELSE.
      DATA(ls_r1) = lt_rk[ 1 ].
      DATA(ls_r2) = lt_rk[ 2 ].
      DATA(ls_rd) = lt_rk[ lines( lt_rk ) ].
      ls_st-c1     = ls_r1-mon.
      ls_st-c2     = ls_r2-mon.
      ls_st-cd     = ls_rd-mon.
      ls_st-cheap1 = month_name( ls_st-c1 ).
      ls_st-cheap2 = month_name( ls_st-c2 ).
      ls_st-dear   = month_name( ls_st-cd ).
      " % of the cheapest month's average price
      " (capped at 9999% so that a wrong unit/price cannot cause an overflow)
      ls_st-diff12 = nmin( val1 = ( ls_r2-idx - ls_r1-idx ) / ls_r1-idx * 100 val2 = 9999 ).
      ls_st-gap    = nmin( val1 = ( ls_rd-idx - ls_r1-idx ) / ls_r1-idx * 100 val2 = 9999 ).

      " 6) in how many years was the cheapest month cheaper than the dearest?
      LOOP AT lt_years INTO lv_yr.
        READ TABLE gt_yidx INTO DATA(ls_a)
             WITH TABLE KEY matnr = iv_matnr yr = lv_yr mon = ls_st-c1.
        CHECK sy-subrc = 0.
        READ TABLE gt_yidx INTO DATA(ls_b)
             WITH TABLE KEY matnr = iv_matnr yr = lv_yr mon = ls_st-cd.
        CHECK sy-subrc = 0.
        IF ls_a-idx < ls_b-idx.
          ls_st-years_ok = ls_st-years_ok + 1.
        ENDIF.
      ENDLOOP.

      IF ls_st-gap >= p_gap AND ls_st-years_ok >= p_years.
        ls_st-seasonal = 'Yes'.
        ls_st-status   = 'Seasonal pattern'.
        " only the Seasonal / Result cells green
        ls_st-t_color  = VALUE #( ( fname = 'SEASONAL' color-col = 5 color-int = 1 )
                                  ( fname = 'STATUS'   color-col = 5 color-int = 0 ) ).
      ELSE.
        ls_st-seasonal = 'No'.
        ls_st-status   = COND #( WHEN ls_st-gap < p_gap THEN 'Gap below minimum'
                                 ELSE 'Pattern not repeated' ).
      ENDIF.
    ENDIF.

    " Description and shelf life (MARA-MHDHB in the period of MARA-IPRKZ)
    " cheapest / 2nd cheapest / dearest cells coloured
    IF ls_st-c1 > 0.
      APPEND LINES OF cell_colors( iv_c1 = ls_st-c1 iv_c2 = ls_st-c2 iv_cd = ls_st-cd
                                   iv_months = abap_true ) TO ls_st-t_color.
    ENDIF.

    SELECT SINGLE maktx FROM makt
      WHERE matnr = @iv_matnr AND spras = @sy-langu
      INTO @ls_st-maktx.
    SELECT SINGLE mhdhb, iprkz FROM mara
      WHERE matnr = @iv_matnr
      INTO (@lv_mhd, @lv_ipr).
    lv_days = SWITCH i( lv_ipr WHEN 'W' THEN lv_mhd * 7
                               WHEN 'M' THEN lv_mhd * 30
                               WHEN 'Y' THEN lv_mhd * 365
                               ELSE lv_mhd ).
    ls_st-shelf_m = lv_days DIV 30.

    INSERT ls_st INTO TABLE gt_stat.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Popup: raw materials of the product's multi-level BOM
*----------------------------------------------------------------------*
  METHOD show_components.
    DATA: lt_stb   TYPE STANDARD TABLE OF stpox,
          ls_top   TYPE cstmat,
          lt_range TYPE tr_matnr,
          ls_c     TYPE ty_comp,
          lv_rc    TYPE sy-subrc.

    CLEAR: gt_comp, lt_range.
    gv_src = 'B'.
    CALL FUNCTION 'CS_BOM_EXPL_MAT_V2'
      EXPORTING
        capid                 = 'PP01'
        datuv                 = sy-datum
        mehrs                 = abap_true          " multi-level
        mktls                 = abap_true
        mtnrv                 = is_prod-matnr
        werks                 = p_werks
      IMPORTING
        topmat                = ls_top
      TABLES
        stb                   = lt_stb
      EXCEPTIONS
        alt_not_found         = 1
        call_invalid          = 2
        material_not_found    = 3
        missing_authorization = 4
        no_bom_found          = 5
        no_plant_data         = 6
        no_suitable_bom_found = 7
        conversion_error      = 8
        OTHERS                = 9.
    lv_rc = sy-subrc.

    " Raw materials (types of the screen) of all levels, quantities added up
    LOOP AT lt_stb INTO DATA(ls_stb) WHERE postp = 'L' AND idnrk IS NOT INITIAL.
      " material type read from MARA (STPOX-MTART
      " is not always filled by the explosion)
      SELECT SINGLE mtart FROM mara WHERE matnr = @ls_stb-idnrk INTO @DATA(lv_mtart).
      CHECK lv_mtart IN s_rmtart.
      CHECK ls_stb-mnglg >= 0.                     " co-/by-products skipped
      READ TABLE gt_comp ASSIGNING FIELD-SYMBOL(<ls_c>) WITH KEY idnrk = ls_stb-idnrk.
      IF sy-subrc <> 0.
        APPEND VALUE #( idnrk = ls_stb-idnrk meins = ls_stb-mmein stufe = ls_stb-stufe )
               TO gt_comp ASSIGNING <ls_c>.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_stb-idnrk ) TO lt_range.
      ENDIF.
      <ls_c>-qty = <ls_c>-qty + ls_stb-mnglg.
      IF ls_stb-stufe < <ls_c>-stufe.
        <ls_c>-stufe = ls_stb-stufe.
      ENDIF.
    ENDLOOP.
    " no active BOM (or no raw materials in it) ->
    " raw materials from the real goods issues to the product's orders
    IF lv_rc <> 0 OR gt_comp IS INITIAL.
      gv_src = 'A'.
      CLEAR: gt_comp, lt_range, ls_top.
      actual_comps( EXPORTING iv_matnr = is_prod-matnr CHANGING ct_range = lt_range ).
      IF gt_comp IS INITIAL.
        MESSAGE |No active BOM (error { lv_rc }) and no raw materials issued to orders of { is_prod-matnr ALPHA = OUT } in the period| TYPE 'I'.
        RETURN.
      ENDIF.
    ENDIF.

    load_prices( it_matnr = lt_range it_mtart = s_rmtart[] ).
    calc_stats( ).

    LOOP AT gt_comp ASSIGNING <ls_c>.
      READ TABLE gt_stat INTO DATA(ls_st) WITH TABLE KEY matnr = <ls_c>-idnrk.
      IF sy-subrc <> 0.
        SELECT SINGLE maktx FROM makt
          WHERE matnr = @<ls_c>-idnrk AND spras = @sy-langu
          INTO @<ls_c>-maktx.
        <ls_c>-seasonal = 'No'.
        <ls_c>-advice   = 'No purchases in the period'.
        CONTINUE.
      ENDIF.
      <ls_c>-maktx    = ls_st-maktx.
      <ls_c>-seasonal = ls_st-seasonal.
      <ls_c>-cheap1   = ls_st-cheap1.
      <ls_c>-cheap2   = ls_st-cheap2.
      <ls_c>-diff12   = ls_st-diff12.
      <ls_c>-dear     = ls_st-dear.
      <ls_c>-gap      = ls_st-gap.
      <ls_c>-years_ok = ls_st-years_ok.
      <ls_c>-shelf_m  = ls_st-shelf_m.
      " coloured cells instead of the whole row
      IF ls_st-c1 > 0.
        <ls_c>-t_color = cell_colors( iv_c1 = ls_st-c1 iv_c2 = ls_st-c2 iv_cd = ls_st-cd
                                      iv_months = abap_false ).
      ENDIF.
      IF ls_st-seasonal = 'Yes'.
        APPEND VALUE #( fname = 'SEASONAL' color-col = 5 color-int = 1 ) TO <ls_c>-t_color.
      ENDIF.
      IF ls_st-c1 > 0 AND is_prod-peak_n > 0.
        " months between the cheapest month and the product's peak month
        <ls_c>-lead = ( is_prod-peak_n - ls_st-c1 + 12 ) MOD 12.
      ENDIF.
      IF ls_st-seasonal <> 'Yes'.
        <ls_c>-advice = ls_st-status.
      ELSEIF <ls_c>-lead = 0.
        <ls_c>-advice = 'Cheapest month = peak month: buy as usual'.
      ELSEIF <ls_c>-shelf_m = 0.
        <ls_c>-advice = |Buy in { ls_st-cheap1 }, { <ls_c>-lead } months before peak - no shelf life in SAP|.
      ELSEIF <ls_c>-shelf_m - 1 >= <ls_c>-lead.
        <ls_c>-advice  = |Buy in { ls_st-cheap1 }, { <ls_c>-lead } months before the peak|.
        APPEND VALUE #( fname = 'ADVICE' color-col = 5 color-int = 1 ) TO <ls_c>-t_color.
      ELSE.
        <ls_c>-advice = |Shelf life too short ({ <ls_c>-shelf_m } months) for { <ls_c>-lead } months|.
      ENDIF.
    ENDLOOP.
    SORT gt_comp BY seasonal DESCENDING gap DESCENDING.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = go_comp
                                CHANGING  t_table      = gt_comp ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.
    go_comp->get_functions( )->set_all( abap_true ).
    TRY.
        go_comp->get_columns( )->set_color_column( 'T_COLOR' ).
      CATCH cx_salv_error.
    ENDTRY.
    set_columns( go_comp ).
    " shorter title (max. 70 characters)
    go_comp->get_display_settings( )->set_list_header(
      COND lvc_title(
        WHEN gv_src = 'B'
        THEN |{ is_prod-matnr ALPHA = OUT } peak { is_prod-peak } - qty per { ls_top-bmeng } { ls_top-bmein } - click = chart|
        ELSE |{ is_prod-matnr ALPHA = OUT } peak { is_prod-peak } - real use (no active BOM) - click = chart| ) ).
    set_hotspot( io_salv = go_comp iv_col = 'IDNRK' ).
    IF gv_src = 'A'.
      TRY.
          DATA(lo_qcol) = go_comp->get_columns( )->get_column( 'QTY' ).
          lo_qcol->set_long_text( 'Qty used in the period' ).
          lo_qcol->set_medium_text( 'Qty used in period' ).
          lo_qcol->set_short_text( 'Qty used' ).
        CATCH cx_salv_not_found.
      ENDTRY.
    ENDIF.
    DATA(lo_events) = go_comp->get_event( ).
    SET HANDLER on_dbl_comp FOR lo_events.
    SET HANDLER on_link_comp FOR lo_events.
    go_comp->set_screen_popup( start_column = 3  end_column = 200
                               start_line   = 2  end_line   = 24 ).
    go_comp->display( ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Main list in the full screen, with own buttons [Chart] and [Help]
*----------------------------------------------------------------------*
  METHOD display_main.
    TRY.
        cl_salv_table=>factory( EXPORTING r_container  = cl_gui_container=>default_screen
                                IMPORTING r_salv_table = go_main
                                CHANGING  t_table      = ct_table ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    DATA(lo_func) = go_main->get_functions( ).
    lo_func->set_all( abap_true ).
    TRY.
        IF gv_mode = 'P'.
          " [Raw materials] = BOM raw materials of the selected product
          lo_func->add_function(
            name     = 'ZBOM'
            icon     = CONV string( icon_bom )
            text     = `Raw materials`
            tooltip  = `Raw materials of the BOM of the selected product (same as clicking the material)`
            position = if_salv_c_function_position=>right_of_salv_functions ).
        ENDIF.
        IF gv_mode = 'R'.
          " [Chart]: price chart of the selected raw material
          lo_func->add_function(
            name     = 'ZCHART'
            icon     = CONV string( icon_graphics )
            text     = `Chart`
            tooltip  = `Price chart of the selected raw material (same as double-click)`
            position = if_salv_c_function_position=>right_of_salv_functions ).
        ENDIF.
        " [Help]: explanation of the report, columns and buttons
        lo_func->add_function(
          name     = 'ZHELP'
          icon     = CONV string( icon_information )
          text     = `Help`
          tooltip  = `Explanation of the calculation, the columns and the buttons`
          position = if_salv_c_function_position=>right_of_salv_functions ).
      CATCH cx_salv_error.
    ENDTRY.

    go_main->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
    " colours in both lists (products: top-3 months)
    TRY.
        go_main->get_columns( )->set_color_column( 'T_COLOR' ).
      CATCH cx_salv_error.
    ENDTRY.
    set_columns( go_main ).

    go_main->get_layout( )->set_key( VALUE #( report = sy-repid handle = gv_mode ) ).
    go_main->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).
    go_main->get_display_settings( )->set_striped_pattern( abap_true ).
    " shorter titles (max. 70 characters)
    go_main->get_display_settings( )->set_list_header( COND lvc_title(
      WHEN gv_mode = 'P'
      THEN |Seasonal products { p_werks } - top-3 >= { p_top3 }% - click material = raw mat.|
      ELSE |Raw materials { p_werks } - avg price per month - click material = chart| ) ).
    set_hotspot( io_salv = go_main iv_col = 'MATNR' ).

    DATA(lo_events) = go_main->get_event( ).
    SET HANDLER on_function FOR lo_events.
    SET HANDLER on_link_main FOR lo_events.
    IF gv_mode = 'P'.
      SET HANDLER on_dbl_prod FOR lo_events.
    ELSE.
      SET HANDLER on_dbl_raw FOR lo_events.
    ENDIF.
    go_main->display( ).
  ENDMETHOD.

  METHOD on_dbl_prod.
    READ TABLE gt_prod INTO DATA(ls_p) INDEX row.
    IF sy-subrc = 0.
      show_components( ls_p ).
    ENDIF.
  ENDMETHOD.

  METHOD on_dbl_comp.
    READ TABLE gt_comp INTO DATA(ls_c) INDEX row.
    IF sy-subrc = 0.
      open_chart( ls_c-idnrk ).
    ENDIF.
  ENDMETHOD.

  METHOD on_dbl_raw.
    READ TABLE gt_raw INTO DATA(ls_r) INDEX row.
    IF sy-subrc = 0.
      open_chart( ls_r-matnr ).
    ENDIF.
  ENDMETHOD.

  METHOD on_function.
    CASE e_salv_function.
      WHEN 'ZHELP'.
        show_help( ).
      WHEN 'ZBOM'.
        DATA(lt_sel) = go_main->get_selections( )->get_selected_rows( ).
        IF lt_sel IS INITIAL.
          MESSAGE 'Select a product first (row button on the left), then press Raw materials' TYPE 'I'.
          RETURN.
        ENDIF.
        READ TABLE gt_prod INTO DATA(ls_p) INDEX lt_sel[ 1 ].
        IF sy-subrc = 0.
          show_components( ls_p ).
        ENDIF.
      WHEN 'ZCHART'.
        DATA(lt_rows) = go_main->get_selections( )->get_selected_rows( ).
        IF lt_rows IS INITIAL.
          MESSAGE 'Select a row first (row button on the left), then press Chart' TYPE 'I'.
          RETURN.
        ENDIF.
        READ TABLE gt_raw INTO DATA(ls_r) INDEX lt_rows[ 1 ].
        IF sy-subrc = 0.
          open_chart( ls_r-matnr ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Chart window (selection screen 200 with an HTML control)
*----------------------------------------------------------------------*
  METHOD get_use.
    " materials issued (261-262) to the orders of a
    " material in the period, in the base unit
    SELECT c~matnr, m~mtart, c~meins,
           SUM( CASE WHEN c~shkzg = 'H' THEN c~menge
                     ELSE c~menge * -1 END )                         AS qty
      FROM matdoc AS c
      INNER JOIN afpo AS p ON p~aufnr = c~aufnr
                          AND p~posnr = '0001'
      INNER JOIN mara AS m ON m~matnr = c~matnr
      WHERE c~record_type = 'MDOC'
        AND c~werks       = @p_werks
        AND c~budat      IN @s_budat
        AND c~bwart      IN ('261','262')
        AND p~matnr       = @iv_matnr
      GROUP BY c~matnr, m~mtart, c~meins
      INTO CORRESPONDING FIELDS OF TABLE @rt_use.
  ENDMETHOD.

  METHOD actual_comps.
    " Level 1: raw materials issued to the product's orders.
    " Level 2: raw materials issued to the orders of a semi-finished product,
    "          times the share of that semi-finished product used here.
    DATA: lv_prod TYPE ty_qty,
          lv_fac  TYPE f.
    DATA(lt_l1) = get_use( iv_matnr ).
    LOOP AT lt_l1 INTO DATA(ls_u) WHERE qty > 0.
      IF ls_u-mtart IN s_rmtart.
        add_comp( EXPORTING iv_matnr = ls_u-matnr iv_meins = ls_u-meins
                            iv_qty   = CONV ty_q6( ls_u-qty ) iv_level = 1
                  CHANGING  ct_range = ct_range ).
        CONTINUE.
      ENDIF.
      CLEAR lv_prod.
      SELECT SUM( CASE WHEN shkzg = 'S' THEN menge ELSE menge * -1 END )
        FROM matdoc
        WHERE record_type = 'MDOC'
          AND werks       = @p_werks
          AND budat      IN @s_budat
          AND bwart      IN ('101','102')
          AND aufnr      <> ' '
          AND matnr       = @ls_u-matnr
        INTO @lv_prod.
      IF lv_prod <= 0.
        CONTINUE.                       " not produced here: not a semi-finished product
      ENDIF.
      lv_fac = ls_u-qty / lv_prod.
      IF lv_fac > 1.
        lv_fac = 1.
      ENDIF.
      DATA(lt_l2) = get_use( ls_u-matnr ).
      LOOP AT lt_l2 INTO DATA(ls_u2) WHERE qty > 0 AND mtart IN s_rmtart.
        add_comp( EXPORTING iv_matnr = ls_u2-matnr iv_meins = ls_u2-meins
                            iv_qty   = CONV ty_q6( ls_u2-qty * lv_fac ) iv_level = 2
                  CHANGING  ct_range = ct_range ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_comp.
    READ TABLE gt_comp ASSIGNING FIELD-SYMBOL(<ls_c>) WITH KEY idnrk = iv_matnr.
    IF sy-subrc <> 0.
      APPEND VALUE #( idnrk = iv_matnr meins = iv_meins stufe = iv_level ) TO gt_comp ASSIGNING <ls_c>.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = iv_matnr ) TO ct_range.
    ENDIF.
    <ls_c>-qty = <ls_c>-qty + iv_qty.
    IF iv_level < <ls_c>-stufe.
      <ls_c>-stufe = iv_level.
    ENDIF.
  ENDMETHOD.

  METHOD on_link_main.
    " click on the material number
    IF gv_mode = 'P'.
      on_dbl_prod( row = row column = column ).
    ELSE.
      on_dbl_raw( row = row column = column ).
    ENDIF.
  ENDMETHOD.

  METHOD on_link_comp.
    on_dbl_comp( row = row column = column ).
  ENDMETHOD.

  METHOD set_hotspot.
    TRY.
        DATA(lo_col) = CAST cl_salv_column_table( io_salv->get_columns( )->get_column( iv_col ) ).
        lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDMETHOD.

  METHOD open_chart.
    IF NOT line_exists( gt_stat[ matnr = iv_matnr ] ).
      MESSAGE 'No purchases of this material in the period' TYPE 'I'.
      RETURN.
    ENDIF.
    gv_chart_matnr = iv_matnr.
    CALL SELECTION-SCREEN 200 STARTING AT 5 2 ENDING AT 125 30.
  ENDMETHOD.

  METHOD build_chart.
    DATA: lv_max  TYPE ty_prc,
          lv_p    TYPE ty_prc,
          lv_h    TYPE i,
          lv_x    TYPE i,
          lv_col  TYPE string,
          lv_cell TYPE string,
          lv_i3   TYPE p LENGTH 6 DECIMALS 3,
          lv_url  TYPE c LENGTH 250,
          lt_yrs  TYPE SORTED TABLE OF char4 WITH UNIQUE KEY table_line,
          lt_pyrs TYPE SORTED TABLE OF char4 WITH UNIQUE KEY table_line,
          lt_pp   TYPE STANDARD TABLE OF ty_prc WITH EMPTY KEY,
          lv_pmin TYPE ty_prc,
          lv_pmax TYPE ty_prc,
          lv_bg   TYPE string.

    READ TABLE gt_stat INTO DATA(ls) WITH TABLE KEY matnr = gv_chart_matnr.
    CHECK sy-subrc = 0.

    IF go_dock IS NOT BOUND.
      go_dock = NEW cl_gui_docking_container( repid = sy-repid
                                              dynnr = '0200'
                                              side  = cl_gui_docking_container=>dock_at_top
                                              ratio = 90 ).
      go_html = NEW cl_gui_html_viewer( parent = go_dock ).
    ENDIF.

    DO 12 TIMES.
      ASSIGN COMPONENT |M{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| OF STRUCTURE ls TO FIELD-SYMBOL(<lv_m>).
      IF <lv_m> > lv_max.
        lv_max = <lv_m>.
      ENDIF.
    ENDDO.

    CLEAR gt_html.
    add( `<html><head><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta charset="utf-8">` ).
    add( `<style>body{font-family:Arial;font-size:12px;margin:8px}` ).
    add( `table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:2px 6px;text-align:right}</style>` ).
    add( `</head><body>` ).
    add( |<b>{ escape( val = |{ ls-matnr ALPHA = OUT } { ls-maktx }| format = cl_abap_format=>e_html_text ) }</b><br>| ).
    add( |Average purchase price per month ({ ls-waers } per { ls-meins }). | ).
    add( |Seasonal: { ls-seasonal } - gap { ls-gap }% - years OK { ls-years_ok } of { ls-years_val }<br>| ).
    add( `<svg width="760" height="240" xmlns="http://www.w3.org/2000/svg">` ).
    add( `<line x1="30" y1="200" x2="740" y2="200" stroke="#999"/>` ).
    DO 12 TIMES.
      ASSIGN COMPONENT |M{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| OF STRUCTURE ls TO <lv_m>.
      lv_p = <lv_m>.
      lv_x = 40 + ( sy-index - 1 ) * 58.
      lv_col = COND #( WHEN sy-index = ls-c1 THEN `#1D9E75`
                       WHEN sy-index = ls-c2 THEN `#9FE1CB`
                       WHEN sy-index = ls-cd THEN `#E24B4A`
                       ELSE `#B4B2A9` ).
      IF lv_max > 0 AND lv_p > 0.
        lv_h = lv_p / lv_max * 170.
        add( |<rect x="{ lv_x }" y="{ 200 - lv_h }" width="44" height="{ lv_h }" fill="{ lv_col }"/>| ).
        add( |<text x="{ lv_x + 22 }" y="{ 195 - lv_h }" font-size="10" text-anchor="middle">{ lv_p DECIMALS = 3 }</text>| ).
      ELSE.
        add( |<text x="{ lv_x + 22 }" y="195" font-size="10" text-anchor="middle">-</text>| ).
      ENDIF.
      add( |<text x="{ lv_x + 22 }" y="216" font-size="11" text-anchor="middle">{ month_name( sy-index ) }</text>| ).
    ENDDO.
    add( `</svg><br>` ).
    add( `<span style="color:#1D9E75">&#9632;</span> cheapest &nbsp; <span style="color:#9FE1CB">&#9632;</span> 2nd cheapest &nbsp; ` ).
    add( `<span style="color:#E24B4A">&#9632;</span> dearest &nbsp; (- = no purchases)<br><br>` ).

    " average purchase price per year and month
    add( |<b>Average purchase price per year</b> ({ ls-waers } per { ls-meins }; | ).
    add( `green = cheapest, red = dearest month of that year)<br>` ).
    add( `<table><tr><th>Year</th>` ).
    DO 12 TIMES.
      add( |<th>{ month_name( sy-index ) }</th>| ).
    ENDDO.
    add( `</tr>` ).
    LOOP AT gt_ym INTO DATA(ls_py) WHERE matnr = gv_chart_matnr.
      INSERT ls_py-yr INTO TABLE lt_pyrs.
    ENDLOOP.
    LOOP AT lt_pyrs INTO DATA(lv_pyr).
      CLEAR: lt_pp, lv_pmin, lv_pmax.
      DO 12 TIMES.
        CLEAR lv_p.
        LOOP AT gt_ym INTO ls_py
             WHERE matnr = gv_chart_matnr AND yr = lv_pyr
               AND mon = CONV char2( |{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| ).
          IF ls_py-qty > 0 AND ls_py-value > 0.
            lv_p = ls_py-value / ls_py-qty.
          ENDIF.
          EXIT.
        ENDLOOP.
        APPEND lv_p TO lt_pp.
        IF lv_p > 0 AND ( lv_pmin = 0 OR lv_p < lv_pmin ).
          lv_pmin = lv_p.
        ENDIF.
        IF lv_p > lv_pmax.
          lv_pmax = lv_p.
        ENDIF.
      ENDDO.
      add( |<tr><th>{ lv_pyr }</th>| ).
      LOOP AT lt_pp INTO lv_p.
        IF lv_p = 0.
          add( `<td>-</td>` ).
        ELSE.
          lv_bg = COND #( WHEN lv_p = lv_pmin THEN ` style="background:#C0DD97"`
                          WHEN lv_p = lv_pmax THEN ` style="background:#F7C1C1"`
                          ELSE `` ).
          add( |<td{ lv_bg }>{ lv_p DECIMALS = 4 }</td>| ).
        ENDIF.
      ENDLOOP.
      add( `</tr>` ).
    ENDLOOP.
    add( `</table><br>` ).

    " Index per year (1.000 = average price of that year)
    add( `<b>Price index per year</b> (1.000 = average of the year; years with fewer than 6 purchase months are left out)<br>` ).
    add( `<table><tr><th>Year</th>` ).
    DO 12 TIMES.
      add( |<th>{ month_name( sy-index ) }</th>| ).
    ENDDO.
    add( `</tr>` ).
    LOOP AT gt_yidx INTO DATA(ls_yi) WHERE matnr = gv_chart_matnr.
      INSERT ls_yi-yr INTO TABLE lt_yrs.
    ENDLOOP.
    LOOP AT lt_yrs INTO DATA(lv_yr).
      add( |<tr><th>{ lv_yr }</th>| ).
      DO 12 TIMES.
        READ TABLE gt_yidx INTO ls_yi WITH TABLE KEY matnr = gv_chart_matnr yr = lv_yr mon = sy-index.
        IF sy-subrc = 0.
          lv_i3 = ls_yi-idx.
          lv_cell = |{ lv_i3 DECIMALS = 3 }|.
        ELSE.
          lv_cell = `-`.
        ENDIF.
        add( |<td>{ lv_cell }</td>| ).
      ENDDO.
      add( `</tr>` ).
    ENDLOOP.
    add( `</table></body></html>` ).

    go_html->load_data( IMPORTING  assigned_url = lv_url
                        CHANGING   data_table   = gt_html
                        EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc = 0.
      go_html->show_url( EXPORTING url = lv_url EXCEPTIONS OTHERS = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD add.
    " One HTML piece per line (each piece is shorter than 255 characters)
    APPEND VALUE #( line = iv_text ) TO gt_html.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Help, columns, small helpers
*----------------------------------------------------------------------*
  METHOD show_help.
    gt_help = VALUE #(
      ( line = 'WHAT: which raw materials are cheaper in some months every year, and which seasonal' )
      ( line = '      products use them, so purchasing can buy ahead in the cheap months.' )
      ( line = 'SELECTION (top block, used by both tabs):' )
      ( line = '  Plant / Posting date: period of production and purchases (default: last 3 full years).' )
      ( line = '  Raw-material types : default ROH. Add VERP for packaging.' )
      ( line = '  Min. gap %         : dearest minus cheapest month index must be at least this.' )
      ( line = '  Min. years OK      : number of years in which the cheapest month was really cheaper.' )
      ( line = 'TAB 1 Seasonal products: product types (default FERT), products, min. top-3 share %,' )
      ( line = '  min. production orders in the period (default 12),' )
      ( line = '  checkbox = only products at or above that share.' )
      ( line = 'TAB 2 Raw-material prices: raw materials, checkbox = only raw materials with a pattern.' )
      ( line = 'Execute (F8) runs the tab that is open.' )
      ( line = '------------------------------------------------------------------------------------' )
      ( line = 'PRICE PATTERN: purchases 101-102 on POs (no own-plant transfers, no consignment).' )
      ( line = '  Index = month price / average price of that year (removes the year price level).' )
      ( line = '  A year counts if it has purchases in at least 6 months.' )
      ( line = '  Cheapest / 2nd cheapest / dearest month = lowest / highest Avg price of the month' )
      ( line = '  (all years of the period together). Diff 1-2 % and Gap % = % of the cheapest price.' )
      ( line = '  Years OK = years in which the cheapest month was really cheaper than the dearest' )
      ( line = '  (compared inside the same year; the chart shows the index per year).' )
      ( line = '  Diff. 1st-2nd = how much cheaper the cheapest month is than the 2nd cheapest.' )
      ( line = 'PRODUCTS: top-3 share = production of the 3 biggest months / total. Peak = biggest month.' )
      ( line = '  Seasonal = top-3 share >= min. % AND in at least Min. years the same 3 months had' )
      ( line = '  >= min. % of that year (pattern repeats) AND at least Min. production orders.' )
      ( line = '  Too few years = produced in fewer years; Too few orders = only a few batches' )
      ( line = '  (slow mover: a few batches always fall into a few months, that is not a season).' )
      ( line = '  Months produced = calendar months with production (all years together).' )
      ( line = '  Colours: dark green = peak month, light green = 2nd and 3rd month.' )
      ( line = '  Month % are rounded to 1 decimal, so a row can add up to 99.9 or 100.1.' )
      ( line = 'RAW MATERIALS OF A PRODUCT: multi-level BOM of today. Months ahead = from the cheapest' )
      ( line = '  month to the product peak. Green = seasonal AND shelf life (minus 1 month) is enough.' )
      ( line = '------------------------------------------------------------------------------------' )
      ( line = 'BUTTONS / CLICKS' )
      ( line = '  Products list : click the material no. (or double-click, or select row + [Raw materials])' )
      ( line = '                  -> raw materials of its BOM (popup). If the product has no ACTIVE BOM' )
      ( line = '                  today, the raw materials come from the real goods issues of the period.' )
      ( line = '  BOM popup     : double-click a raw material -> price chart.' )
      ( line = '  Raw-material list: double-click a row, or select a row and press [Chart] -> chart.' )
      ( line = '  [Help]        : this text.  Standard ALV buttons: sort, filter, Excel, layouts.' )
      ( line = '  Chart window  : green = cheapest, light green = 2nd cheapest, red = dearest month;' )
      ( line = '                  tables = average price per year (green/red = cheapest/dearest of' )
      ( line = '                  that year) and index per year. Close with the X or Cancel.' )
      ( line = '  Colours in the lists: only the cells - Cheapest/month price dark green, 2nd cheapest' )
      ( line = '                  light green, Dearest red, Seasonal / Advice green when OK.' )
      ( line = 'NOTE: price at goods receipt; invoice differences are not included.' ) ).
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_help)
                                CHANGING  t_table      = gt_help ).
        set_columns( lo_help ).
        lo_help->set_screen_popup( start_column = 5  end_column = 130
                                   start_line   = 2  end_line   = 32 ).
        lo_help->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.

  METHOD set_columns.
    DATA(lo_cols) = io_salv->get_columns( ).
    lo_cols->set_optimize( abap_true ).
    LOOP AT lo_cols->get( ) INTO DATA(ls_col).
      CASE ls_col-columnname.
        WHEN 'C1' OR 'C2' OR 'CD' OR 'PEAK_N'.
          ls_col-r_column->set_technical( abap_true ).
          CONTINUE.
      ENDCASE.
      DATA(lv_text) = col_text( ls_col-columnname ).
      IF lv_text IS NOT INITIAL.
        ls_col-r_column->set_long_text( lv_text ).
        ls_col-r_column->set_medium_text( CONV scrtext_m( lv_text ) ).
        " readable short header instead of cut text
        DATA(lv_short) = col_short( ls_col-columnname ).
        ls_col-r_column->set_short_text( COND #( WHEN lv_short IS NOT INITIAL THEN lv_short
                                                 ELSE CONV scrtext_s( lv_text ) ) ).
        ls_col-r_column->set_tooltip( lv_text ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD col_text.
    DATA lv_n TYPE i.
    IF strlen( iv_name ) = 3 AND iv_name+1(2) CO '0123456789'.
      lv_n = iv_name+1(2).
      CASE iv_name(1).
        WHEN 'M'. rv_text = |{ month_name( lv_n ) } avg price|.
        WHEN 'P'. rv_text = |{ month_name( lv_n ) } %|.
      ENDCASE.
      RETURN.
    ENDIF.
    CASE iv_name.
      WHEN 'MATNR' OR 'IDNRK'. rv_text = 'Material'.
      WHEN 'MAKTX'.     rv_text = 'Description'.
      WHEN 'CLASS'.     rv_text = 'Seasonality'.
      WHEN 'TOP3'.      rv_text = 'Top-3 months share %'.
      WHEN 'PEAK'.      rv_text = 'Peak month'.
      WHEN 'TOTAL'.     rv_text = 'Produced qty'.
      WHEN 'MEINS'.     rv_text = 'Unit'.
      WHEN 'WAERS'.     rv_text = 'Currency'.
      WHEN 'SEASONAL'.  rv_text = 'Seasonal price'.
      WHEN 'STATUS'.    rv_text = 'Result'.
      WHEN 'CHEAP1'.    rv_text = 'Cheapest month'.
      WHEN 'CHEAP2'.    rv_text = '2nd cheapest month'.
      WHEN 'DIFF12'.    rv_text = 'Diff. 1st-2nd cheapest %'.
      WHEN 'DEAR'.      rv_text = 'Dearest month'.
      WHEN 'GAP'.       rv_text = 'Gap dearest-cheapest %'.
      WHEN 'YEARS_OK'.  rv_text = 'Years pattern OK'.
      WHEN 'YEARS_VAL'. rv_text = 'Years with data'.
      WHEN 'PMONTHS'.   rv_text = 'Purchase months'.
      WHEN 'SHELF_M'.   rv_text = 'Shelf life (months)'.
      WHEN 'STUFE'.     rv_text = 'BOM level'.
      WHEN 'NYEARS'.    rv_text = 'Years produced'.
      WHEN 'NMONTHS'.   rv_text = 'Months produced'.
      WHEN 'ORDERS'.    rv_text = 'Production orders'.
      WHEN 'QTY'.       rv_text = 'Qty per BOM base qty'.
      WHEN 'LEAD'.      rv_text = 'Months ahead of peak'.
      WHEN 'ADVICE'.    rv_text = 'Advice'.
      WHEN 'LINE'.      rv_text = 'Help'.
    ENDCASE.
  ENDMETHOD.

  METHOD col_short.
    DATA lv_n TYPE i.
    IF strlen( iv_name ) = 3 AND iv_name+1(2) CO '0123456789'.
      lv_n = iv_name+1(2).
      CASE iv_name(1).
        WHEN 'M'. rv_text = |{ month_name( lv_n ) } price|.
        WHEN 'P'. rv_text = |{ month_name( lv_n ) } %|.
      ENDCASE.
      RETURN.
    ENDIF.
    rv_text = SWITCH #( iv_name
      WHEN 'SEASONAL'  THEN 'Seasonal'
      WHEN 'STATUS'    THEN 'Result'
      WHEN 'CHEAP1'    THEN 'Cheapest'
      WHEN 'CHEAP2'    THEN '2nd cheap.'
      WHEN 'DIFF12'    THEN 'Diff 1-2 %'
      WHEN 'DEAR'      THEN 'Dearest'
      WHEN 'GAP'       THEN 'Gap %'
      WHEN 'YEARS_OK'  THEN 'Years OK'
      WHEN 'YEARS_VAL' THEN 'Years data'
      WHEN 'PMONTHS'   THEN 'Buy months'
      WHEN 'SHELF_M'   THEN 'Shelf (m)'
      WHEN 'CLASS'     THEN 'Seasonal'
      WHEN 'TOP3'      THEN 'Top-3 %'
      WHEN 'PEAK'      THEN 'Peak'
      WHEN 'TOTAL'     THEN 'Produced'
      WHEN 'NYEARS'    THEN 'Years prod'
      WHEN 'NMONTHS'   THEN 'Months'
      WHEN 'ORDERS'    THEN 'Orders'
      WHEN 'LEAD'      THEN 'Months ahd'
      WHEN 'ADVICE'    THEN 'Advice'
      WHEN 'STUFE'     THEN 'Level'
      WHEN 'QTY'       THEN 'Quantity'
      WHEN 'MEINS'     THEN 'Unit'
      WHEN 'WAERS'     THEN 'Currency' ).
  ENDMETHOD.

  METHOD month_name.
    rv_name = SWITCH #( iv_month WHEN 1 THEN 'Jan' WHEN 2 THEN 'Feb' WHEN 3 THEN 'Mar'
                                 WHEN 4 THEN 'Apr' WHEN 5 THEN 'May' WHEN 6 THEN 'Jun'
                                 WHEN 7 THEN 'Jul' WHEN 8 THEN 'Aug' WHEN 9 THEN 'Sep'
                                 WHEN 10 THEN 'Oct' WHEN 11 THEN 'Nov' WHEN 12 THEN 'Dec' ).
  ENDMETHOD.

  METHOD cell_colors.
    " Dark green = cheapest, light green = 2nd cheapest, red = dearest
    rt_color = VALUE #( ( fname = 'CHEAP1' color-col = 5 color-int = 1 )
                        ( fname = 'CHEAP2' color-col = 5 color-int = 0 )
                        ( fname = 'DEAR'   color-col = 6 color-int = 0 ) ).
    IF iv_months = abap_true.
      APPEND VALUE #( fname = |M{ iv_c1 WIDTH = 2 ALIGN = RIGHT PAD = '0' }| color-col = 5 color-int = 1 ) TO rt_color.
      APPEND VALUE #( fname = |M{ iv_c2 WIDTH = 2 ALIGN = RIGHT PAD = '0' }| color-col = 5 color-int = 0 ) TO rt_color.
      APPEND VALUE #( fname = |M{ iv_cd WIDTH = 2 ALIGN = RIGHT PAD = '0' }| color-col = 6 color-int = 0 ) TO rt_color.
    ENDIF.
  ENDMETHOD.

  METHOD green.
    rt_color = VALUE #( ( color-col = 5 color-int = 0 color-inv = 0 ) ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Texts of the selection screen (so no text elements are needed)
*----------------------------------------------------------------------*
INITIALIZATION.
  sscrfields-functxt_01 = '@0S@ Help'.
  t_b0   = 'Common selection (both tabs)'.
  t_b5   = 'Explanation'.
  t_tab1 = 'Seasonal products'.
  t_tab2 = 'Raw-material prices'.
  t_200  = 'Price chart'.
  c_200  = 'Average purchase price per month and price index per year'.
  tabs-prog      = sy-repid.
  tabs-dynnr     = 101.
  tabs-activetab = 'TAB1'.
  %_p_werks_%_app_%-text  = 'Plant'.
  %_s_budat_%_app_%-text  = 'Posting date'.
  %_s_rmtart_%_app_%-text = 'Raw-material types'.
  %_p_gap_%_app_%-text    = 'Min. gap dearest-cheapest %'.
  %_p_years_%_app_%-text  = 'Min. years pattern OK'.
  " labels of the tab fields (see selection screen)
  c_pmtart = 'Product material types'.
  c_pmatnr = 'Product'.
  c_top3   = 'Min. top-3 months share %'.
  c_onlyp  = 'Only seasonal products'.
  c_minord = 'Min. production orders'.
  c_rmatnr = 'Raw material'.
  c_onlyr  = 'Only with seasonal price pattern'.
  c_h1 = 'Tab 1: seasonal products -> double-click -> raw materials of the BOM'.
  c_h2 = '       with cheapest / 2nd cheapest month -> double-click -> chart.'.
  c_h3 = 'Tab 2: raw materials with average price per month -> double-click -> chart.'.
  c_h4 = 'F8 runs the open tab. [Help] in the toolbar explains everything.'.

  " Default period: the last 3 full calendar years (complete years only)
  s_budat = VALUE #( sign = 'I' option = 'BT'
                     low  = |{ sy-datum(4) - 3 }0101|
                     high = |{ sy-datum(4) - 1 }1231| ).
  APPEND s_budat.
  s_pmtart = VALUE #( sign = 'I' option = 'EQ' low = 'FERT' ). APPEND s_pmtart.
  s_rmtart = VALUE #( sign = 'I' option = 'EQ' low = 'ROH' ). APPEND s_rmtart.

AT SELECTION-SCREEN OUTPUT.
  IF sy-dynnr = '0200'.
    lcl_app=>build_chart( ).
  ENDIF.

AT SELECTION-SCREEN.
  IF sy-dynnr = '1000' AND sscrfields-ucomm = 'FC01'.
    lcl_app=>show_help( ).
  ENDIF.
  IF sy-dynnr = '1000' AND sscrfields-ucomm = 'ONLI' AND p_years < 1.
    MESSAGE 'Min. years pattern OK must be at least 1' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  AUTHORITY-CHECK OBJECT 'M_MSEG_WMB'
    ID 'ACTVT' FIELD '03'
    ID 'WERKS' FIELD p_werks.
  IF sy-subrc <> 0.
    MESSAGE |No authorization to display goods movements of plant { p_werks }| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF tabs-activetab = 'TAB2'.
    lcl_app=>run_rawmat( ).
  ELSE.
    lcl_app=>run_products( ).
  ENDIF.
  WRITE space.                          " shows the full-screen ALV container
