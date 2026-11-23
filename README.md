# SAP Seasonal Forward Buying (ABAP)

Find **seasonal products**, the **raw materials** in their bills of material, and the **months in which those raw materials are cheapest** - so purchasing can buy ahead in the cheap months, within shelf life.

One read-only ABAP report for SAP S/4HANA. No custom tables, no extra infrastructure: it reads standard tables, calculates in ABAP and shows the result in ALV lists and a chart window inside SAP GUI. Nothing is changed in SAP.

## What the user sees

The selection screen has two tabs. **F8** runs the tab that is open.

### Tab 1 - Seasonal products

| Column | Meaning |
|---|---|
| Jan % … Dec % | Share of each calendar month in the product's production (top-3 months coloured: dark green = peak, light green = 2nd / 3rd) |
| Top-3 % / Peak | Share of the 3 biggest months / biggest month |
| Years produced / Years OK | Years with production / years in which the same 3 months held at least the minimum share |
| Orders / Months | Production orders and calendar months with production |
| Seasonal | *Seasonal*, *Not seasonal*, *Not repeated*, *Too few years*, *Too few orders* |

A product is **seasonal** only if its top-3 share is high **and** the pattern repeats over the years **and** it has enough production orders (a few one-off batches are not a season).

**Click a product** → popup with the raw materials of its **multi-level BOM**. If the product has no active BOM, the raw materials actually issued to its production orders (and, by share, to the orders of its semi-finished products) are used. For each raw material: cheapest, 2nd cheapest and dearest month, gap %, months between the cheapest month and the product's peak, shelf life and an advice (green = can be bought ahead within shelf life).

### Tab 2 - Raw-material prices

Average purchase price per calendar month (Jan price … Dec price), cheapest / 2nd cheapest / dearest month, gap %, years in which the pattern held, number of purchase months, shelf life. Checkbox: *only raw materials with a seasonal price pattern*.

### Chart window

Click a raw material (or select a row and press **Chart**) → bar chart of the average price per month (green = cheapest, light green = 2nd cheapest, red = dearest), a table of the average price **per year and month**, and a price-index table per year.

## How it works

**Production** - goods receipts 101 − 102 from production orders (`MATDOC`, posting date), per product, year and month.

**Purchase price** - goods receipts 101 − 102 on purchase orders (`MATDOC-DMBTR / MENGE`), per raw material, year and month, in base unit and company-code currency. Left out: stock transfers from own plants (`EKKO-RESWK`) and consignment (special stock K).

| Step | Rule |
|---|---|
| Average price per month | value / quantity of that calendar month over all years |
| Cheapest / dearest | lowest / highest average price; *Diff 1-2 %* and *Gap %* in % of the cheapest price |
| Years OK | per year, the cheapest month really was cheaper than the dearest (years with ≥ 6 purchase months) |
| Seasonal price | gap ≥ min. gap % **and** years OK ≥ min. years |

**Product → raw materials** - `CS_BOM_EXPL_MAT_V2` (application PP01, multi-level); material types read from `MARA`; fallback to real goods issues 261 − 262 via `AFPO`.

**Shelf life** - `MARA-MHDHB` in the period of `MARA-IPRKZ`.

## Technical highlights

- ABAP 7.5+ syntax: SQL expressions (`CASE`, `SUBSTRING`, aggregates, `GROUP BY`) so totals are calculated in the database
- Tabbed selection screen with sub-screens, own labels and a Help function key
- SALV full-screen list in a container, own toolbar buttons, hotspots, double-click, cell-level colours, popup drill-down
- Chart window: selection screen as a window + docking container + `CL_GUI_HTML_VIEWER` with generated HTML/SVG
- Authority check on the plant (`M_MSEG_WMB`, activity 03), because purchase prices are shown

## Installation

1. SE38 / ADT: create program `ZMM_SEASONAL` (type executable), paste `ZMM_SEASONAL.abap`, activate.
2. Optional: create a transaction for it and give it to purchasing / costing only.
3. No DDIC objects or text elements are needed (all labels are set in the code).

Defaults on the screen (change them for your system): plant `1000`, product type `FERT`, raw-material type `ROH`, last 3 full years, min. top-3 share 60 %, min. gap 5 %, min. years 2, min. production orders 12.

## Requirements

- SAP S/4HANA (table `MATDOC`), ABAP 7.50 or higher
- SAP GUI for Windows for the chart window

## Limitations

- Price at goods receipt (purchase-order price); invoice differences and separately posted delivery costs are not included.
- Today's BOM is used for the product → raw-material link.
- Average prices mix all years: if prices rose strongly, months bought mainly in an expensive year look more expensive. *Years OK* compares months inside each year to guard against this.

## How it was built

Designed and tested by me on a real SAP S/4HANA system; code developed with AI pair-programming (Claude).

## License

MIT - see [LICENSE](LICENSE).
