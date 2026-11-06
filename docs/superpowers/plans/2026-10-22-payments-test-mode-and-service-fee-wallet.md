# Payments Test Mode, QR Ph, Whole-Peso Pricing & Service Fee Wallet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five payment methods (COD, GCash, Maya, Card, QR Ph) through one PayMongo test account with webhook confirmation, a pay-before-fulfilment guard, whole-peso subtotal/delivery pricing, and a prepaid service fee wallet that locks COD when empty.

**Architecture:** The server (Postgres functions + two Deno edge functions) stays the single source of pricing, payment state and wallet balance; Flutter clients mirror the pricing rule only for preview and display. All schema/function changes ship as idempotent SQL scripts in `supabase/scripts/`, verified by SQL test scripts run inside a transaction that is rolled back.

**Tech Stack:** Flutter/Dart (customer/owner/rider app in `lib/`, desktop admin app in `admin/lib/`), Supabase Postgres (plpgsql), Supabase Edge Functions (Deno/TypeScript), PayMongo Checkout Sessions API.

**Spec:** `docs/superpowers/specs/2026-10-22-payments-test-mode-and-service-fee-wallet-design.md`

## Global Constraints

- Supabase project id: `ormmjxtbwosnraijphra`. The **live database is the source of truth** for current function bodies, not the repo scripts (they have drifted: e.g. repo `centralized_delivery_fee_system.sql` is not applied live). Before replacing any function, fetch its live body with `select pg_get_functiondef('public.<name>'::regproc)` and edit that.
- Nothing is applied to the live database and no edge function is deployed until Task 10, and only after the owner says go. SQL tests run as `BEGIN; <script>; <test>; ROLLBACK;` through the Supabase MCP `execute_sql` tool.
- Online methods: exactly `gcash, maya, card, qrph`. Offline: `cod`, `credit` (credit counts as COD for the wallet).
- PayMongo method names: `gcash`, `paymaya` (our `maya`), `card`, `qrph`.
- Rounding: `subtotal = round(Σ price×qty, 0)`, `delivery_fee = round(raw, 0)`, `discount = round(raw, 0)`, `service_fee = round((subtotal + delivery_fee) × percent/100 + fixed, 2)` — the service fee is **not** rounded to pesos. `total = subtotal + delivery_fee + service_fee − discount`, floored at 0.
- Wallet config `system_config` key `service_fee_wallet`: `{"min_topup": 100, "low_balance_alert": 100, "cod_lock_at_or_below": 0}`.
- Copy, verbatim:
  - unpaid guard: `This order is waiting for online payment.`
  - COD locked reason: `Cash on Delivery is unavailable for this station right now.`
  - owner banner: `Cash on Delivery is off — top up your service fee balance to turn it back on.`
  - low balance notification title `Service fee balance is low`, body `Top up to keep Cash on Delivery on.`
  - test label: `Test mode — no real money`; for QR Ph add `Do not scan with a banking app.`
  - missing key error: `Payment gateway is not configured.`
- The working tree has unrelated uncommitted changes (`saved_addresses_screen.dart`, `cart_screen.dart`, `checkout_screen.dart`, `remote_catchup.sql`, `test/saved_addresses_consistency_test.dart`). Never stage them; `git add` only the files a task names. If a task must edit `checkout_screen.dart`, ask the owner first whether to commit their pending changes.
- UI follows the existing UI kit (`lib/core/widgets/app_ui_kit.dart`) and the original saturated palette — no purple/indigo.
- Flutter test command: `flutter test <file>`; admin: `cd admin && flutter test <file>`.

## Review Focus

1. **Double-processing of the same PayMongo payment** (webhook retry, or webhook + app `verify` racing) — order must be marked paid once and a top-up credited once. Pinned in Task 7 (`topup_credit_is_idempotent`) and Task 4 (webhook duplicate event test).
2. **Order delivered when the wallet is already ₱0 or negative** — delivery must still succeed and the balance go negative; never block the rider. Pinned in Task 6 (`deduction_allows_negative_balance`).
3. **Voucher discount larger than subtotal+delivery** — total floors at ₱0 and the PayMongo minimum (₱1.00) path still raises the existing "Invalid order amount" error rather than creating a ₱0 checkout. Pinned in Task 1 (`price_order_floors_total_at_zero`).
4. **Station that explicitly disabled methods before QR Ph existed** (`enabled_payment_methods` non-null without `qrph`) — QR Ph must stay off for them, not silently appear. Pinned in Task 3 (`qrph_respects_explicit_station_list`).
5. **Owner cancelling an unpaid online order** — the guard must allow `cancelled`, and a customer cancelling their own pending order must still work. Pinned in Task 5 (`guard_allows_cancel_of_unpaid_online_order`).

---

### Task 0: Snapshot live definitions for rollback

**Files:**
- Create: `supabase/scripts/payments_wallet_rollback.sql`

- [ ] **Step 1:** Using `execute_sql`, fetch `pg_get_functiondef` for: `create_order_atomic`, `calculate_platform_fee`, `get_station_available_payment_methods`, `is_station_payment_method_available`, `transition_order_status_safely`, `confirm_delivery_safely`, `proc_finalize_order_finances`, `process_due_customer_subscriptions`, `record_payment_checkout`.
- [ ] **Step 2:** Write them into `payments_wallet_rollback.sql` inside `BEGIN; … COMMIT;`, followed by `DROP … IF EXISTS` for every object later tasks create (`price_order`, `station_fee_wallets`, `station_fee_wallet_entries`, `station_fee_topups`, `station_cod_locked`, `apply_wallet_entry`, `credit_wallet_topup`, `create_wallet_topup`, `admin_adjust_fee_wallet`, `admin_list_fee_wallets`, the wallet trigger). Header comment: does not restore rounded prices or the three orders marked paid.
- [ ] **Step 3:** Commit: `git add supabase/scripts/payments_wallet_rollback.sql && git commit -m "chore: snapshot live payment functions for rollback"`

### Task 1: Whole-peso pricing on the server

**Files:**
- Create: `supabase/scripts/whole_peso_pricing.sql`
- Test: `supabase/tests/whole_peso_pricing_test.sql`

**Interfaces:**
- Produces: `public.price_order(p_subtotal_raw numeric, p_delivery_raw numeric, p_discount_raw numeric default 0) returns table(subtotal numeric, delivery_fee numeric, service_fee numeric, discount numeric, total numeric)` — STABLE SECURITY DEFINER, reads `get_platform_fee_config()`. `calculate_platform_fee(subtotal, delivery)` keeps its signature and returns `price_order(subtotal, delivery).service_fee`.

- [ ] **Step 1: Write the failing test** (`DO` blocks that `RAISE EXCEPTION` on mismatch, with the fee config set in-transaction to `{"enabled":true,"percent":1,"fixed":0}`):
  - `price_order_rounds_subtotal_and_delivery`: `price_order(119.6, 20.4)` → subtotal 120, delivery 20, service_fee 1.40, total 141.40.
  - `price_order_keeps_fee_centavos`: `price_order(25, 0)` → service_fee 0.25, total 25.25.
  - `price_order_rounds_discount`: `price_order(120, 20, 10.5)` → discount 11, total 130.40.
  - `price_order_floors_total_at_zero`: `price_order(20, 5, 100)` → total 0.
  - `price_order_fee_disabled`: with `enabled:false`, `price_order(120,20)` → service_fee 0, total 140.
  - `create_order_atomic_uses_rule`: as a fixture customer ordering 1 × a ₱19.60 product from a fixture owner with `base_delivery_fee` 5.4 → returned `subtotal` 20, `delivery_fee` 5, `platform_fee` 0.25, `total_amount` 25.25.
  - `subscription_order_uses_rule`: a due fixture subscription with `estimated_price` 39.5 → generated order has subtotal 40, delivery_fee 0, platform_fee 0.40, total 40.40.
  - Fixtures: insert `auth.users` rows, then set `profiles.role`; impersonate with `select set_config('request.jwt.claims', json_build_object('sub', <id>, 'role', 'authenticated')::text, true)`.
- [ ] **Step 2:** Run `BEGIN; <test file without the script>; ROLLBACK;` → FAIL (`function price_order does not exist`).
- [ ] **Step 3: Implement `whole_peso_pricing.sql`:** create `price_order`; redefine `calculate_platform_fee` on top of it; take the **live** `create_order_atomic` and replace its subtotal/delivery/fee/discount/total arithmetic with one `price_order` call (voucher logic still decides the raw discount); take the live `process_due_customer_subscriptions` and price each order with `price_order(sub.estimated_price, 0)`, writing `platform_fee`; one-off `UPDATE products SET price = round(price)` and `UPDATE owner_settings SET base_delivery_fee = round(base_delivery_fee)` where they have centavos.
- [ ] **Step 4:** Run `BEGIN; <script>; <test>; ROLLBACK;` → all blocks pass (no exception).
- [ ] **Step 5:** Commit both files: `feat(db): whole-peso subtotal and delivery pricing`.

### Task 2: Whole-peso pricing and display in the apps

**Files:**
- Modify: `lib/features/dashboard/customer/checkout_rules.dart` (`calculateDeliveryFee`, `calculateOrderTotal`; add `roundSubtotal`)
- Modify: `lib/core/utils/money.dart`
- Modify: `lib/features/dashboard/customer/checkout_screen.dart` (use `CheckoutRules.roundSubtotal(cart.totalAmount)` wherever `cart.totalAmount` feeds pricing — see Global Constraints about pending changes)
- Modify: `lib/features/dashboard/owner/add_order_dialog.dart`, `lib/core/services/offline_order_sync_service.dart` (route their arithmetic through `CheckoutRules`)
- Modify: owner product-price and base-delivery-fee inputs (find with `grep -rn "base_delivery_fee\|price_per_gallon" lib/features/dashboard/owner`) to digits-only.
- Test: `test/whole_peso_pricing_test.dart`; update existing expectations in `test/checkout_payment_test.dart`, `test/checkout_order_service_test.dart`, `test/receipt_service_test.dart` that assume `.00` display.

**Interfaces:**
- Produces: `static double CheckoutRules.roundSubtotal(double raw)`; `calculateDeliveryFee(...)` now returns a whole number; `calculateOrderTotal(...)` rounds `voucherDiscount` to whole pesos before subtracting; `calculatePlatformFee` unchanged (2 decimals). `formatPeso(num? amount, {bool whole = false})`: when `whole` is false, prints no decimals if the amount has no centavos, else two.

- [ ] **Step 1: Write failing tests** mirroring Task 1's examples: `roundSubtotal(119.6) == 120`; `calculateDeliveryFee(distanceKm: 2.3, ratePerKm: 2)` == 5; `calculatePlatformFee(subtotal: 120, deliveryFee: 20, enabled: true, percent: 1, fixed: 0)` == 1.40; `calculateOrderTotal(subtotal: 120, deliveryFee: 20, platformFee: 1.40, voucherDiscount: 10.5)` == 130.40; `formatPeso(120) == '₱120'`; `formatPeso(1.4) == '₱1.40'`; `formatPeso(1234.5) == '₱1,234.50'`; `formatPeso(1234.5, whole: true) == '₱1,235'`.
- [ ] **Step 2:** `flutter test test/whole_peso_pricing_test.dart` → FAIL.
- [ ] **Step 3:** Implement the signatures above; swap the remaining `toStringAsFixed(2)` peso displays in `lib/` and `admin/lib/` (`grep -rn "toStringAsFixed(2)"`) for `formatPeso` where they render money.
- [ ] **Step 4:** `flutter test` (whole suite) → PASS; `cd admin && flutter test` → PASS.
- [ ] **Step 5:** Commit: `feat: whole-peso pricing and display in apps`.

### Task 3: QR Ph as a payment method

**Files:**
- Create: `supabase/scripts/qrph_payment_method.sql`
- Test: `supabase/tests/qrph_payment_method_test.sql`
- Modify: `lib/features/dashboard/customer/checkout_rules.dart` (`onlinePaymentMethods`, `standardPaymentMethods`, `paymentLabel`)
- Modify: `lib/features/dashboard/customer/widgets/payment_method_selector.dart`, `payment_brand_mark.dart`, `lib/core/widgets/refill_components.dart`, `lib/features/dashboard/owner/owner_menu_screen.dart` (every `['cod', 'gcash', 'maya', 'card']` list and label switch)
- Modify: `supabase/functions/create-payment-checkout/index.ts` (`PaymentMethod` type and allow-list)
- Test: `test/checkout_payment_test.dart` (extend)

**Interfaces:**
- Produces: method id `qrph`, label `QR Ph`. Default methods when `enabled_payment_methods` is null: `cod, gcash, maya, card, qrph`.

- [ ] **Step 1: Failing tests.** SQL: `qrph_available_by_default` (owner with null settings → `is_station_payment_method_available(owner,'qrph')` true and `get_station_available_payment_methods` returns 5 rows); `qrph_respects_explicit_station_list` (owner with `{cod,gcash}` → qrph false). Dart: `CheckoutRules.isOnlinePayment('qrph')` true; `paymentLabel('qrph') == 'QR Ph'`; widget test "renders all 5 payment methods" replacing the 4-method test.
- [ ] **Step 2:** Run both → FAIL.
- [ ] **Step 3:** Implement: SQL redefines the two availability functions from their live bodies with the 5-method list (Task 6 extends them again for the COD lock). Brand mark for QR Ph uses `Icons.qr_code_2` on the existing mark style. Edge function accepts `qrph` and maps it to `qrph`.
- [ ] **Step 4:** SQL test passes in a rolled-back transaction; `flutter test test/checkout_payment_test.dart` → PASS; `npx --yes deno check supabase/functions/create-payment-checkout/index.ts` → no errors.
- [ ] **Step 5:** Commit: `feat: add QR Ph payment method`.

### Task 4: PayMongo test mode done properly

**Files:**
- Create: `supabase/functions/_shared/paymongo.ts`
- Modify: `supabase/functions/create-payment-checkout/index.ts`, `supabase/functions/paymongo-webhook/index.ts`
- Modify: `lib/core/services/payment_checkout_service.dart`
- Create: `lib/features/dashboard/customer/widgets/test_mode_label.dart`
- Modify: `lib/features/dashboard/customer/payment_return_screen.dart`, the checkout payment step in `checkout_screen.dart`
- Test: `test/payment_checkout_service_test.dart` (extend), `test/test_mode_label_test.dart`

**Interfaces:**
- Produces (TS, `_shared/paymongo.ts`): `paymongoSecretKey(): string` (throws `Error("Payment gateway is not configured.")` when `PAYMONGO_SECRET_KEY` is unset), `isLiveKey(key: string): boolean` (`sk_live_` prefix), `paymongoMethod(method: PaymentMethod): string`, `type PaymentMethod = "gcash" | "maya" | "card" | "qrph"`, `type CheckoutKind = "order" | "wallet_topup"`.
- Produces (Dart): `PaymentVerification.livemode` (bool, default false); `PaymentCheckoutService.createCheckout` returns `CheckoutSession {String url; bool livemode}` instead of `String` — update its three callers. `TestModeLabel({required bool qrph})` widget renders the Global Constraints copy.
- Checkout Session metadata: `{ kind: "order", order_id }`.

- [ ] **Step 1: Failing tests.** Dart: fake functions client returning `{checkout_url, checkout_id, livemode:false}` → `createCheckout` yields `livemode == false`; `verify` parses `livemode`. Widget: `TestModeLabel(qrph: true)` shows both strings; `qrph: false` shows only the first.
- [ ] **Step 2:** `flutter test test/payment_checkout_service_test.dart test/test_mode_label_test.dart` → FAIL.
- [ ] **Step 3:** Implement. Remove the hardcoded `sk_test_…` and the hardcoded project URL fallback from `create-payment-checkout`; return `livemode: isLiveKey(key)` from create and verify. Webhook: route on `resource.attributes.metadata.kind` (default `order` when missing, keeping the existing description fallback); leave `wallet_topup` as a TODO-free branch that returns 200 after recording the event — Task 7 fills it. Show `TestModeLabel` on the payment step and return screen when `livemode` is false.
- [ ] **Step 4:** Flutter tests PASS; `npx --yes deno check` on both functions → no errors.
- [ ] **Step 5:** Commit: `fix(payments): require configured PayMongo key and show test mode`.

### Task 5: Pay before fulfilment

**Files:**
- Create: `supabase/scripts/pay_before_fulfilment_guard.sql`
- Test: `supabase/tests/pay_before_fulfilment_guard_test.sql`
- Modify: `lib/features/dashboard/owner/widgets/owner_order_detail_sheet.dart`, `lib/features/dashboard/owner/widgets/new_order_alert_sheet.dart` (disable Accept when `!CheckoutRules.canTrackOrder(order)`, show the guard copy)
- Test: `test/owner_order_detail_sheet_test.dart` (extend)

- [ ] **Step 1: Failing tests.** SQL: `guard_blocks_accept_of_unpaid_online_order` (owner `pending→accepted` on a `gcash`/`pending` order raises the guard copy); `guard_allows_paid_online_order`; `guard_allows_cod`; `guard_allows_cancel_of_unpaid_online_order` (owner and customer both); `guard_blocks_confirm_delivery_unpaid`; `three_orders_marked_paid` (the three ids have `payment_status='success'`). Widget: unpaid gcash order → Accept disabled and guard copy visible.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Script, in order: `UPDATE orders SET payment_status='success', payment_error='Marked paid as test data (2026-10-22)' WHERE id IN ('8d2dc6e9-c8c3-4fd1-aa97-be2bbc4f60c8','74ba3859-06d0-4b77-b086-a84078bfdfdf','0ce436d4-a5c7-4d1f-96af-035985f71cfe') AND payment_status <> 'success'`; then redefine live `transition_order_status_safely` and `confirm_delivery_safely`, adding — for owner and rider branches only, when `payment_method` is online and `p_new_status <> 'cancelled'` and `payment_status <> 'success'` — `RAISE EXCEPTION 'This order is waiting for online payment.'`.
- [ ] **Step 4:** SQL test passes rolled back; `flutter test test/owner_order_detail_sheet_test.dart` → PASS.
- [ ] **Step 5:** Commit: `feat: block fulfilment of unpaid online orders`.

### Task 6: Service fee wallet — ledger, deduction, COD lock

**Files:**
- Create: `supabase/scripts/service_fee_wallet.sql`
- Test: `supabase/tests/service_fee_wallet_test.sql`

**Interfaces:**
- Produces tables `station_fee_wallets`, `station_fee_wallet_entries`, `station_fee_topups` exactly as in the spec §5 (entries: partial unique index on `(order_id) WHERE kind = 'service_fee'`; topups also get `unique (provider_checkout_id)`).
- Produces `public.apply_wallet_entry(p_owner_id uuid, p_amount numeric, p_kind text, p_order_id uuid default null, p_topup_id uuid default null, p_note text default null) returns numeric` (new balance; upserts the wallet row; sends the low-balance notification when the balance crosses from ≥ to < `low_balance_alert`; revoked from `anon, authenticated`).
- Produces `public.station_cod_locked(p_owner_id uuid) returns boolean` — true when the platform fee is enabled and balance (missing wallet = 0) ≤ `cod_lock_at_or_below`. Granted to `authenticated`.
- `system_config` row `service_fee_wallet` inserted with the Global Constraints value if absent.

- [ ] **Step 1: Failing tests:** `deducts_fee_on_cod_delivery` (COD order with platform_fee 1.40 delivered → entry −1.40, balance −1.40); `no_deduction_for_online_order`; `deduction_is_idempotent` (re-running the trigger path for the same order leaves one entry); `deduction_allows_negative_balance`; `sale_entry_excludes_fee` (ledger `SALE` = total − fee, plus a `SERVICE_FEE` entry of fee with `account_id` = owner and `metadata->>'payee' = 'platform'`); `cod_locked_at_zero` (`is_station_payment_method_available(owner,'cod')` false, reason text matches copy in `get_station_available_payment_methods`, online still true); `cod_unlocked_after_credit` (`apply_wallet_entry(owner, 100, 'topup')` → cod true); `cod_never_locked_when_fee_disabled`; `low_balance_notifies_once`; `subscription_skips_cod_when_locked` (no order created; one `system_notifications` row each for owner and customer); RLS: owner reads own wallet only, `insert` into entries as owner fails.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement: tables + RLS (owner `select` own rows, `is_admin()` select all, no write policies); `apply_wallet_entry`; extend live `proc_finalize_order_finances` (COD/credit + fee > 0 → `apply_wallet_entry(owner, -platform_fee, 'service_fee', order)`; SALE amount and SERVICE_FEE entry per test); redefine the two availability functions (from Task 3's versions) so `cod` is unavailable when `station_cod_locked`; `create_order_atomic` needs no change because it already calls `is_station_payment_method_available`; `process_due_customer_subscriptions` (Task 1's version) skips locked COD subscriptions and notifies, without advancing their schedule.
- [ ] **Step 4:** Run `BEGIN; whole_peso_pricing.sql; qrph_payment_method.sql; service_fee_wallet.sql; <test>; ROLLBACK;` → pass.
- [ ] **Step 5:** Commit: `feat(db): service fee wallet with COD lock`.

### Task 7: Wallet top-ups through PayMongo

**Files:**
- Modify: `supabase/scripts/service_fee_wallet.sql` (append top-up functions)
- Modify: `supabase/tests/service_fee_wallet_test.sql`
- Modify: `supabase/functions/create-payment-checkout/index.ts`, `supabase/functions/paymongo-webhook/index.ts`

**Interfaces:**
- Produces `public.create_wallet_topup(p_owner_id uuid, p_amount numeric, p_payment_method text) returns uuid` (raises `Top-up must be a whole peso amount of at least ₱100.` unless `amount = round(amount)` and ≥ `min_topup`; service-role only).
- Produces `public.record_wallet_topup_checkout(p_topup_id uuid, p_provider_checkout_id text, p_checkout_url text, p_livemode boolean) returns void`.
- Produces `public.credit_wallet_topup(p_topup_id uuid) returns numeric` — sets status `paid`, `paid_at`, and calls `apply_wallet_entry(owner, amount, 'topup', null, topup)` only on the first call; later calls return the current balance (service-role only).
- Edge function actions (owner JWT, role must be `owner`): `{action:"topup", amount, payment_method}` → `{checkout_url, checkout_id, topup_id, livemode}`; `{action:"verify_topup", topup_id}` → `{verified, status, balance, livemode}`. Checkout description `eRefill wallet top-up <topup_id>`, metadata `{kind:"wallet_topup", topup_id}`, success/cancel URLs to `payment-callback` with `topup_id`.

- [ ] **Step 1: Failing SQL tests:** `topup_rejects_below_minimum` (99), `topup_rejects_centavos` (100.5), `topup_credit_is_idempotent` (two `credit_wallet_topup` calls → one `topup` entry, balance +100), `topup_unlocks_cod`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the functions, the two edge actions, and the webhook `wallet_topup` branch (paid → `credit_wallet_topup`; failed/expired → status update only). `payment-callback` passes `topup_id` through to the app deep link the same way it does `order_id` (read `supabase/functions/payment-callback/index.ts` first).
- [ ] **Step 4:** SQL test passes rolled back; `npx --yes deno check` on all three functions → no errors.
- [ ] **Step 5:** Commit: `feat: service fee wallet top-ups via PayMongo`.

### Task 8: Owner wallet screens

**Files:**
- Create: `lib/features/fee_wallet/services/fee_wallet_service.dart`, `lib/features/fee_wallet/models/fee_wallet_models.dart`, `lib/features/fee_wallet/widgets/fee_wallet_card.dart`, `lib/features/fee_wallet/widgets/fee_wallet_topup_sheet.dart`, `lib/features/fee_wallet/fee_wallet_history_screen.dart`
- Modify: `lib/features/dashboard/owner/owner_dashboard.dart` (card + COD-off banner), `lib/core/routing/app_routes.dart` / `app_router.dart` (history route; top-up return handled like the order payment return)
- Test: `test/fee_wallet_test.dart`

**Interfaces:**
- Consumes: Task 6 tables (read via RLS), Task 7 edge actions, Task 4 `TestModeLabel`.
- Produces: `FeeWalletService({SupabaseClient? client})` with `Future<FeeWalletSummary> load()`, `Future<List<FeeWalletEntry>> history({int limit = 50})`, `Future<CheckoutSession> startTopup({required int amount, required String paymentMethod})`, `Future<FeeWalletSummary> verifyTopup(String topupId)`. `FeeWalletSummary {double balance; FeeWalletStatus status; DateTime? lastTopupAt}`, `enum FeeWalletStatus { ok, low, codOff }` derived from balance and the config thresholds.

- [ ] **Step 1: Failing tests:** status derivation (`150 → ok`, `100 → ok`, `99 → low`, `0 → codOff`, `-3 → codOff`); card shows `₱150` for ok and the banner copy for codOff; top-up sheet presets ₱100/₱300/₱500, custom `99` shows the minimum error and disables Pay, custom `100.5` cannot be typed (digits only), test label visible when `livemode` false.
- [ ] **Step 2:** `flutter test test/fee_wallet_test.dart` → FAIL.
- [ ] **Step 3:** Implement with the UI kit; history lists entries newest first, labelled `Top-up`, `Service fee · Order #<first 8 of id>`, `Adjustment · <note>`.
- [ ] **Step 4:** `flutter test` (whole suite) → PASS.
- [ ] **Step 5:** Commit: `feat: owner service fee wallet`.

### Task 9: Admin wallet screens

**Files:**
- Modify: `supabase/scripts/service_fee_wallet.sql` (admin RPCs), `supabase/tests/service_fee_wallet_test.sql`
- Modify: `admin/lib/services/admin_api_service.dart`
- Create: `admin/lib/features/fees/fee_wallets_screen.dart`, `admin/lib/features/fees/fee_wallet_detail_screen.dart`
- Modify: the admin navigation that lists `PlatformFeesScreen` (find with `grep -rn PlatformFeesScreen admin/lib`)
- Test: `admin/test/fee_wallets_screen_test.dart`

**Interfaces:**
- Produces `public.admin_list_fee_wallets(p_from timestamptz default null, p_to timestamptz default null) returns table(owner_id uuid, station_name text, balance numeric, cod_locked boolean, last_topup_at timestamptz, fees_collected numeric, topups_received numeric)` and `public.admin_adjust_fee_wallet(p_owner_id uuid, p_amount numeric, p_reason text) returns numeric` (requires `is_admin()` and a non-blank reason; writes `audit_logs` action `FEE_WALLET_ADJUST`). `fees_collected` sums −amount of `service_fee` entries plus `platform_fee` of delivered online orders in range.
- Produces `AdminApiService.listFeeWallets({DateTime? from, DateTime? to})`, `adjustFeeWallet({required String ownerId, required double amount, required String reason})`.

- [ ] **Step 1: Failing tests.** SQL: non-admin calling either RPC raises; blank reason raises; adjustment writes entry + audit row. Widget: table renders a fake row's balance with `formatPeso`, a `COD off` chip when `cod_locked`, and the header note `Payouts of online sales to stations are not automated yet.`
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; detail screen shows the station's entries and an Adjust dialog (amount, required reason).
- [ ] **Step 4:** SQL passes rolled back; `cd admin && flutter test` → PASS.
- [ ] **Step 5:** Commit: `feat(admin): service fee wallet overview and adjustments`.

### Task 10: Setup guide, full verification, rollout

**Files:**
- Create: `docs/payments_test_mode_setup.md`

- [ ] **Step 1:** Write the guide: PayMongo test keys (Settings → Developers), Supabase secrets `PAYMONGO_SECRET_KEY` and `PAYMONGO_WEBHOOK_SIGNING_SECRET`, webhook URL `https://ormmjxtbwosnraijphra.supabase.co/functions/v1/paymongo-webhook` with events `checkout_session.payment.paid` and `payment.failed`, revoking the old committed test key, test payments per method (GCash/Maya Authorize/Fail; cards `4343 4343 4343 4345`, 3DS `4120 0000 0000 0007`, expired `4200 0000 0000 0018`; QR Ph via PayMongo's test simulation only — never scan), the manual end-to-end script from spec §6, and a "Before going live" section: swap to live keys and a live webhook, and reset every wallet's test balance with an admin adjustment.
- [ ] **Step 2:** Run `flutter test` and `cd admin && flutter test` → all pass. Run every SQL test together in one rolled-back transaction after all scripts → pass.
- [ ] **Step 3: Stop and ask the owner for go-ahead** to apply to the live project. Then apply, in order: `whole_peso_pricing.sql`, `qrph_payment_method.sql`, `pay_before_fulfilment_guard.sql`, `service_fee_wallet.sql`; deploy `create-payment-checkout`, `paymongo-webhook`, `payment-callback`.
- [ ] **Step 4:** After the owner sets the secrets and registers the webhook: run the manual script — one test payment per online method, one wallet top-up, one delivered COD order. Confirm with SQL that `payment_webhook_events` has `processed` rows, the wallet entries exist, and COD unlocked after the top-up. Report results with the query output.
- [ ] **Step 5:** Commit: `docs: PayMongo test mode setup and verification guide`.
