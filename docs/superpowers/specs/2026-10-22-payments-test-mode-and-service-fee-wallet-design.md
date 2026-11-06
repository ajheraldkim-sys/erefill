# Payments in Test Mode, QR Ph, Whole-Peso Pricing, and the Service Fee Wallet

Date: 2026-10-22
Status: Draft for review

## Why

eRefill is heading to a capstone demo first and real water stations after.
Four problems block both:

1. Online payments (GCash, Maya, Card) work only by accident: the checkout
   edge function falls back to a test secret key hardcoded in git, and the
   PayMongo webhook has never processed an event, so an order is marked paid
   only if the customer comes back to the app.
2. Nothing stops a station from accepting and delivering an online order that
   was never paid. Three GCash orders in the live database were delivered with
   no checkout ever created.
3. The platform service fee is charged to customers but never collected.
   Customers pay the station directly (cash or online), and the delivery
   ledger credits the station with the full total, service fee included.
4. Amounts carry centavos everywhere, which the owner wants gone.

## Goals

- Customers can pay with **COD, GCash, Maya, Card, or QR Ph**. All online
  methods run through **one eRefill PayMongo account in test mode** for the
  demo, and are confirmed automatically by the webhook.
- The database refuses to move an unpaid online order forward.
- Subtotal and delivery fee are **whole pesos**. The service fee is the exact
  percentage (two decimals, not rounded to whole pesos).
- Each station has a **prepaid service fee wallet**: the owner tops it up
  through PayMongo, each delivered COD order deducts its service fee, and a
  station with no balance loses Cash on Delivery until it tops up (online
  payments keep working). Fully automatic; the admin only watches and
  adjusts.
- Going live later is a configuration change (live keys + live webhook), not
  a code change.

## Non-goals

- Live payments. Nothing in this work turns on live mode.
- PayMongo platform / sub-merchant split payments. This is the likely future
  for real stations (online orders would have their fee taken at checkout and
  the wallet would cover only COD fees), but it needs PayMongo approval and
  per-station verification first. This design only keeps the checkout code
  shaped so that change stays contained to how a checkout session is built.
- Stations' own payment accounts receiving customer money. In this phase all
  online customer payments land in the eRefill account.
- Paying stations out their online sales. Out of scope for the demo; flag in
  the admin screen copy that settlement to stations is not automated yet.
- Changing the rider commission logic in `proc_finalize_order_finances`.

## Anti-goals

- A test payment that silently becomes a real one: no hardcoded keys, and a
  visible "Test mode" label whenever the gateway is in test mode.
- A station losing all its orders over its wallet. Only COD is ever locked.
- Client and server disagreeing on the total. The server stays the single
  source of truth for pricing; the client preview must match it exactly.

## Current state (verified 2026-10-22)

- Pricing is computed in `create_order_atomic(p_order_data, p_items_data)`:
  subtotal from `products.price × quantity`, delivery fee from
  `owner_settings.base_delivery_fee`, service fee from
  `get_platform_fee_config()` as `round((subtotal + delivery) × percent / 100
  + fixed, 2)`. `calculate_platform_fee()` duplicates that formula.
  The column is `orders.platform_fee`; the UI calls it the service fee.
- Other pricing paths that must follow the same rules:
  `supabase/scripts/subscription_orders_server_pricing.sql`,
  `auto_generate_subscription_orders.sql`, the owner's manual order in
  `lib/features/dashboard/owner/add_order_dialog.dart`, the checkout preview
  in `lib/features/dashboard/customer/checkout_screen.dart`, and the offline
  queue in `lib/core/services/offline_order_sync_service.dart`.
- Payment methods are hardcoded as `cod, gcash, maya, card` in
  `get_station_available_payment_methods`, `is_station_payment_method_available`
  (both default to all four when `owner_settings.enabled_payment_methods` is
  null), `CheckoutRules` in `checkout_rules.dart`, the owner toggles in
  `owner_menu_screen.dart`, `payment_method_selector.dart`,
  `payment_brand_mark.dart`, `refill_components.dart`, and
  `create-payment-checkout/index.ts`.
- `create-payment-checkout` creates PayMongo Checkout Sessions, records them
  via `record_payment_checkout`, and has a `verify` action the app calls on
  return. `paymongo-webhook` verifies the PayMongo signature and updates
  `payment_checkouts` and `orders`; it looks checkouts up by
  `provider_checkout_id`, then by `eRefill order <uuid>` in the description.
- Order status changes go through `transition_order_status_safely` and
  `confirm_delivery_safely`. Neither checks payment status.
- `proc_finalize_order_finances` (AFTER UPDATE trigger on `orders`) writes a
  `SALE` ledger entry of `total_amount` for the owner on delivery.
- `orders.payment_status` enum: `pending, processing, success, failed,
  refunded`.

## Design

### 1. PayMongo test mode, done properly

- `create-payment-checkout` reads `PAYMONGO_SECRET_KEY` only. If it is
  missing, it fails with a clear error. Remove the hardcoded `sk_test_…`
  fallback. (The committed key should also be revoked in PayMongo.)
- The function derives mode from the key prefix (`sk_test_` vs `sk_live_`)
  and returns `livemode: false|true` with every checkout and verify response.
- The app shows a small "Test mode — no real money" label on the checkout
  payment step, the payment return screen, and the owner top-up sheet while
  `livemode` is false.
- Webhook: the owner registers one endpoint in the PayMongo dashboard
  (Settings → Webhooks) pointing to
  `https://ormmjxtbwosnraijphra.supabase.co/functions/v1/paymongo-webhook`,
  subscribed to `checkout_session.payment.paid` and `payment.failed`, and
  stores the returned signing secret as `PAYMONGO_WEBHOOK_SIGNING_SECRET`.
  The existing handler already treats any event type containing `paid` as a
  success and reads the checkout session id from `data.attributes.data.id`;
  confirm against a real test event and fix if the shape differs.
- `docs/` gets a short setup page covering: getting test keys, the two
  secrets, the webhook, and how to make each kind of test payment (below).

### 2. QR Ph as a fifth payment method

- Add `qrph` (label "QR Ph") everywhere the method lists live (see Current
  state). In PayMongo it is `payment_method_types: ["qrph"]` on the Checkout
  Session, exactly like the others.
- `qrph` is an online method: `CheckoutRules.isOnlinePayment` includes it,
  and it follows the same pay-before-accept rule.
- Station defaults: when `enabled_payment_methods` is null, all five methods
  are available. Owners can still turn any off.
- **Test-mode hazard:** PayMongo's docs say test mode generates real QR Ph
  codes and scanning one processes a real payment; tests must use the
  simulation (`test_url`) instead. The builder must find out what the hosted
  checkout page offers for simulating a QR Ph payment in test mode, and the
  test-mode label for QR Ph must say "Do not scan with a banking app."

Test payments for the demo:
- GCash / Maya: the test page has Authorize and Fail buttons.
- Card: `4343 4343 4343 4345`, any future expiry, any CVC (3-D Secure:
  `4120 0000 0000 0007`; expired card: `4200 0000 0000 0018`).
- QR Ph: PayMongo's test simulation only, never a real scan.

### 3. Online orders must be paid before they move

- In `transition_order_status_safely`: for an order whose `payment_method` is
  online (`gcash, maya, card, qrph`), any owner or rider transition other
  than `cancelled` requires `payment_status = 'success'`. Otherwise raise
  "This order is waiting for online payment." Customers cancelling a pending
  order and admins are unaffected.
- `confirm_delivery_safely` applies the same check.
- The owner order screens already show "Awaiting payment"; make sure the
  Accept button is disabled for unpaid online orders and the error above is
  shown if the call is attempted anyway.
- Abandoned unpaid online orders: out of scope to auto-cancel in this work;
  they stay `pending` and the customer can retry or cancel.

### 4. Whole-peso pricing

Rule, applied on the server:

- `subtotal = round(Σ price × quantity, 0)`
- `delivery_fee = round(base_delivery_fee, 0)`
- `service_fee = round((subtotal + delivery_fee) × percent / 100 + fixed, 2)`
  — the percentage result is kept to the centavo, not rounded to pesos
- `discount` (vouchers) `= round(…, 0)`
- `total = subtotal + delivery_fee + service_fee − discount`

So ₱120 water + ₱20 delivery at 1% = ₱1.40 fee → total ₱141.40.

- Put the rule in one SQL function (e.g. `price_order(subtotal_raw,
  delivery_raw, discount_raw)` returning the four numbers) and call it from
  `create_order_atomic`, the subscription pricing functions, and
  `calculate_platform_fee`. No other code computes the fee.
- Owner inputs for product price and base delivery fee accept whole numbers
  only. Existing rows with centavos are rounded once by the migration.
- The client checkout preview, owner manual order, and offline queue use the
  same rule (a single Dart helper next to `CheckoutRules`) and are covered by
  tests that compare against the SQL rule's examples.
- Money display: whole amounts show without decimals (₱120); amounts with
  centavos show two decimals (₱1.40, ₱141.40). One formatting helper, used
  on checkout, order details, receipts (`receipt_service.dart`, delivery
  receipt snapshot), owner and admin screens.
- PayMongo amounts are `round(total × 100)` centavos, as today.

### 5. Service fee wallet

**Data**

- `station_fee_wallets (owner_id pk → profiles, balance numeric(10,2) not
  null default 0, updated_at)`.
- `station_fee_wallet_entries (id, owner_id, amount numeric(10,2)` signed,
  `kind text check in ('topup','service_fee','adjustment'),
  order_id null, topup_id null, note, actor_id, created_at)`, with a unique
  constraint on `(order_id)` where `kind = 'service_fee'` so a fee can never
  be deducted twice.
- `station_fee_topups (id, owner_id, amount, payment_method,
  provider_checkout_id, checkout_url, status pending|paid|failed|expired,
  livemode, created_at, paid_at)`.
- Config in `system_config` key `service_fee_wallet`:
  `{ "min_topup": 100, "low_balance_alert": 100, "cod_lock_at_or_below": 0 }`.
- Balance changes happen only through SECURITY DEFINER functions that insert
  an entry and update the balance in one transaction. RLS: owners read their
  own wallet, entries and top-ups; admins read all; nobody writes directly.

**Deduction**

- When an order becomes `delivered` and `platform_fee > 0`, insert a
  `service_fee` entry of `−platform_fee` and lower the balance. Do it in the
  same place the delivery ledger is written (extend
  `proc_finalize_order_finances` or add a sibling trigger). This applies to
  **COD orders only**: online orders are paid into the eRefill PayMongo
  account, so eRefill already holds their service fee. (Store credit /
  utang orders count as COD here.)
- Also fix that trigger's `SALE` entry so the station is credited
  `total_amount − platform_fee`, with the fee recorded separately as
  platform revenue (entry type `SERVICE_FEE`).
- An order already in progress always completes, even if this pushes the
  balance below zero.
- Crossing below `low_balance_alert` inserts one owner notification ("Service
  fee balance is low — top up to keep Cash on Delivery on").

**COD lock** (owner decision: only COD is switched off, never the station)

- When the platform fee is enabled and the station's balance is at or below
  `cod_lock_at_or_below`, COD is unavailable for that station:
  `is_station_payment_method_available` and
  `get_station_available_payment_methods` return COD as unavailable with the
  reason "Cash on Delivery is unavailable for this station right now." Online
  methods stay available, so the station keeps receiving orders.
- `create_order_atomic` already rejects unavailable methods, so this is
  enforced on the server. Subscription auto-orders set to COD are skipped
  with an owner and customer notification while COD is locked.
- The owner sees a banner on their dashboard: "Cash on Delivery is off — top
  up your service fee balance to turn it back on."
- A successful top-up that lifts the balance above the threshold turns COD
  back on immediately.
- Every wallet starts at ₱0 (owner decision), so existing stations start
  with COD locked until their first top-up. No starting credit.

**Top-up**

- Owner taps the wallet card → top-up sheet with presets (₱100, ₱300, ₱500)
  and a custom whole-peso amount ≥ `min_topup`, and picks GCash, Maya, Card,
  or QR Ph.
- `create-payment-checkout` gains `action: "topup"` (owner role only): it
  creates a `station_fee_topups` row and a PayMongo Checkout Session with
  metadata `{ kind: "wallet_topup", topup_id }`, description
  `eRefill wallet top-up <topup_id>`, and returns the URL. Order checkouts
  get metadata `{ kind: "order", order_id }`.
- `paymongo-webhook` routes on that metadata (falling back to the existing
  order lookup for old sessions). A paid top-up calls one function that marks
  the top-up paid and inserts the `topup` entry — idempotent per top-up.
- The `verify` action gains the same for top-ups so the owner's screen
  updates on return even if the webhook is late.
- Top-ups follow the same test-mode rules and labels as customer payments.

**Owner screens**

- Wallet card (owner dashboard / menu): balance, status (OK / Low / COD off),
  Top up button.
- History: top-ups and per-order fee deductions, newest first.

**Admin screens** (`admin/lib/features/fees`, next to `platform_fees_screen`)

- Stations table: balance, status, last top-up, fees collected this month.
- Station detail: entry history.
- Manual adjustment (credit or debit) with a required reason, written to
  `audit_logs`.
- Totals: service fees collected (sum of `service_fee` entries) and top-ups
  received, filterable by date.

### 6. Tests

- SQL-level checks (run against a branch or local stack) for: whole-peso
  pricing examples, pay-before-accept guard, fee deduction idempotency,
  pausing and reopening, top-up webhook idempotency.
- Dart unit tests for the pricing helper, money formatter, `CheckoutRules`
  with `qrph`, and widget tests for the payment selector (five methods), the
  test-mode label, the wallet card states, and the top-up sheet validation.
- Update existing tests that assume four methods or two-decimal display.
- A manual end-to-end script in the setup doc: one test payment per method,
  one wallet top-up, one delivered COD order deducting its fee, one COD-locked
  station.

## Rollout

- Ship as idempotent SQL in `supabase/scripts/` (matching the repo's
  convention) plus a rollback script, then redeploy `create-payment-checkout`
  and `paymongo-webhook`.
- Applying SQL to the live Supabase project and deploying edge functions are
  done only with the owner's go-ahead.
- Existing stations get a wallet at ₱0, so COD is off for them until they top up. Warn owners before the demo.

## Left to the builder

- Exact names of new functions, tables, and widgets, following existing
  naming in the repo.
- Where the wallet card sits on the owner dashboard, styled with the existing
  UI kit and the original saturated palette.
- Whether the fee deduction extends `proc_finalize_order_finances` or is a
  new trigger.
- How customers' station lists learn COD is locked without exposing
  its balance (e.g. a boolean `is_station_accepting_orders(owner_id)` RPC or
  a column on the existing station view).

## Calls made by the designer (not confirmed by the owner)

- Wallet thresholds: minimum top-up ₱100, low-balance alert at ₱100, COD lock
  at ₱0 or below. Admin-editable in `system_config`.
- Whole amounts display without decimals; amounts with centavos show two.
- Voucher discounts are rounded to whole pesos.
- Top-ups store `livemode`. Test-mode balances are demo money: before going
  live, the admin resets every wallet with an `adjustment` entry.
- Unpaid online orders are not auto-cancelled in this work.

## Open questions (for the owner)

None. Resolved:

- Wallets start at ₱0 with no starting credit; an empty wallet locks COD
  only (owner decision).
- The three GCash orders delivered unpaid (`8d2dc6e9…`, `74ba3859…`,
  `0ce436d4…`) get `payment_status = 'success'` with
  `payment_error = 'Marked paid as test data (2026-10-22)'`, in the rollout
  script, before the pay-before-delivery guard is added. (Owner said "mark
  it"; read as "mark it paid". Delivered orders cannot be cancelled anyway.)
