# Page override — Owner overview

> Overrides [`../MASTER.md`](../MASTER.md) for the station owner's Overview tab
> (`lib/features/dashboard/owner/owner_dashboard.dart`, `_OwnerHomeOverview`).
> Skill input: `search.py "water refill station owner operations dashboard
> minimal SaaS" --design-system` → Flat Design, single focal action, no
> clutter. Its black/gold palette and Fira fonts were rejected in favour of
> the Master tokens.

## Job of the page

Answer, in order: *Is anything waiting on me? Am I open? How is today going?
Where are my orders? Do I have stock?* Everything else is one tap away.

## Section order

| Phone (< 1024 dp), single column | Wide (≥ 1024 dp) — main 3 : side 2 |
|---|---|
| 1. Pending-orders callout (only when pending > 0) | **Main:** callout, Today, Order pipeline, Recent orders |
| 2. Station status card | **Side:** Station status, Setup (until complete), Inventory, Quick actions |
| 3. Setup checklist (only until setup is complete) | |
| 4. Today — KPI grid | |
| 5. Order pipeline | |
| 6. Inventory | |
| 7. Quick actions | |
| 8. Recent orders | |

Gap between sections: 24 dp. Content capped at 1200 dp.

## Rules specific to this page

* **One warm color at a time.** The pending callout is the only tinted
  surface; everything else is a neutral bordered card.
* **KPIs** (Revenue, Orders, Delivered, Unpaid utang): label + icon in
  secondary text, value in `displaySmall`, one footnote line. Day-over-day
  change is shown only when yesterday had data, with a trend icon *and* a
  sign so color is never the only signal. Revenue excludes cancelled and
  rejected orders, matching the 7-day figure.
* **Pipeline** uses canonical statuses (`OrderStatusColors.normalize`), so
  aliases such as `confirmed` or `assigned_to_rider` count in the right stage.
  Color only marks the stage dot; counts are text-primary, idle stages are
  muted. A short last row stretches to full width.
* **Station status**: sentence-case title, tone only on the icon tile, switch
  for open/closed and a menu for busy/maintenance. Riders and pricing state
  sit underneath as metadata.
* **Quick actions** are list rows in one card (56 dp rows, chevron), not
  tiles — labels never wrap into uneven heights.
* No tips, sparklines or decorative illustrations beyond the empty state.
