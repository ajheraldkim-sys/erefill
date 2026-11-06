# PayMongo Test Mode Setup

How to run eRefill payments on PayMongo **test mode** for the capstone demo:
COD, GCash, Maya, Card and QR Ph, plus the station service fee wallet.
No real money moves in test mode.

## 1. Get PayMongo test keys

1. Sign up at <https://dashboard.paymongo.com>. A new account starts in test
   mode; no business verification is needed for test keys.
2. Open **Settings → Developers → API keys** and copy the **Secret key**
   (`sk_test_…`).
3. Revoke the old test key that was committed in git
   (`sk_test_DAyQ…`): **API keys → Roll / revoke**.

## 2. Add the Supabase secrets

Supabase → Project Settings → Edge Functions → Secrets:

| Secret | Value |
|---|---|
| `PAYMONGO_SECRET_KEY` | your `sk_test_…` key |
| `PAYMONGO_WEBHOOK_SIGNING_SECRET` | the `whsk_…` secret from step 3 |

`create-payment-checkout` now refuses to run without `PAYMONGO_SECRET_KEY`
("Payment gateway is not configured."). There is no fallback key.

## 3. Register the webhook

PayMongo dashboard → **Settings → Webhooks → Add endpoint**:

- URL: `https://ormmjxtbwosnraijphra.supabase.co/functions/v1/paymongo-webhook`
- Events: `checkout_session.payment.paid`, `payment.failed`

Copy the signing secret it shows (`whsk_…`) into
`PAYMONGO_WEBHOOK_SIGNING_SECRET`. The webhook confirms payments even if the
customer or owner closes the app before returning.

## 4. Apply the database changes

Run these in the Supabase SQL editor, **in this order**. Each is safe to
re-run.

1. `supabase/scripts/payments_wallet_snapshot.sql` — saves the current
   functions so the rollback can restore them
2. `supabase/scripts/whole_peso_pricing.sql`
3. `supabase/scripts/qrph_payment_method.sql`
4. `supabase/scripts/pay_before_fulfilment_guard.sql`
5. `supabase/scripts/service_fee_wallet.sql`

To undo: `supabase/scripts/payments_wallet_rollback.sql`. It does not undo
rounded prices or the three GCash orders marked paid, and it deletes all
wallet balances.

Then deploy the edge functions (each one with the `_shared` folder):
`create-payment-checkout`, `paymongo-webhook`, `payment-callback`.

### Running the SQL tests first (recommended)

Every test runs inside a transaction that is rolled back, so nothing is
saved. Each test file runs in its own batch with the scripts up to and
including its own (once the wallet script is in, test stations start with
COD locked, which the earlier tests don't expect). From the repo root:

```bash
S=supabase/scripts; T=supabase/tests
bash $T/build.sh $S/whole_peso_pricing.sql -- $T/whole_peso_pricing_test.sql > test1.sql
bash $T/build.sh $S/whole_peso_pricing.sql $S/qrph_payment_method.sql \
  -- $T/qrph_payment_method_test.sql > test2.sql
bash $T/build.sh $S/whole_peso_pricing.sql $S/qrph_payment_method.sql \
  $S/pay_before_fulfilment_guard.sql -- $T/pay_before_fulfilment_guard_test.sql > test3.sql
bash $T/build.sh $S/whole_peso_pricing.sql $S/qrph_payment_method.sql \
  $S/pay_before_fulfilment_guard.sql $S/service_fee_wallet.sql \
  -- $T/service_fee_wallet_test.sql > test4.sql
```

Paste each `testN.sql` into the SQL editor and run it. A passing run ends
with `<name>_test: all passed`; a failure stops with the name of the check
that failed. `test4.sql` (the wallet) has never been run yet.

## 5. Make test payments

| Method | How to pay in test mode |
|---|---|
| GCash / Maya | The PayMongo test page shows **Authorize** and **Fail** buttons. No real wallet needed. |
| Card | `4343 4343 4343 4345`, any future expiry, any CVC. 3-D Secure: `4120 0000 0000 0007`. Expired card: `4200 0000 0000 0018`. |
| QR Ph | Use PayMongo's **test simulation** only. Test-mode QR codes are real codes — **never scan one with a banking app**, it makes a real payment. |

The app shows "Test mode — no real money" on payment screens while the key is
a test key.

## 6. End-to-end demo script

1. **Online order:** as a customer, order with each of GCash, Maya, Card and
   QR Ph; complete the test payment. The order shows as paid and the owner
   can accept it. An unpaid online order shows "This order is waiting for
   online payment." and cannot be accepted.
2. **Wallet top-up:** as an owner, open **Service fee balance → Top up**, pay
   ₱100 in test mode. The balance rises and Cash on Delivery turns on.
3. **COD order:** order with COD, deliver it. The station's balance drops by
   the order's service fee.
4. **COD lock:** in the admin app (**Service Fees → Adjust**), bring a station
   to ₱0. Customers can no longer choose COD there; online methods still work.
5. Check in SQL that `payment_webhook_events` has `processed` rows and
   `station_fee_wallet_entries` has the top-up and fee entries.

## Before going live

1. Get the PayMongo account verified and activated for live payments.
2. Replace `PAYMONGO_SECRET_KEY` with the live `sk_live_…` key and register a
   **live** webhook with its own signing secret.
3. Reset every wallet's test balance with an admin adjustment (test top-ups
   were demo money).
4. Make one small real payment per method to confirm.
