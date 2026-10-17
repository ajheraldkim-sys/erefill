# eRefill

eRefill is a Flutter and Supabase app for water refilling stations. It supports customer ordering, station owner operations, rider delivery workflows, chat, proof of delivery, offline delivery management, and online payment checkout.

## Stack

- Flutter for Android, iOS, web, desktop UI
- Supabase Auth, Postgres, Realtime, Storage, RPCs, and Edge Functions
- OpenStreetMap via `flutter_map`
- Local SQLite sync for the delivery management module
- PayMongo Checkout for GCash, Maya, and card payments

## Local Setup

1. Install Flutter.
2. Run `flutter pub get`.
3. Configure Supabase in `lib/core/constants.dart`.
4. Ensure the base application schema is installed in Supabase; the scripts below assume its tables already exist.
5. Apply `supabase/scripts/remote_catchup.sql` in the Supabase SQL Editor when using the repository's catch-up schema path.
6. Apply `supabase/scripts/automated_proof_of_delivery.sql` to install required proof validation, private evidence access, and atomic receipt/chat/notification creation.
7. Apply `supabase/scripts/app_version_management_system.sql` to create the app release catalog and audit tables. This is required by the App Releases screen and app update checks; without it, Supabase reports that `public.app_releases` is missing.
8. Apply `supabase/scripts/loyalty_and_referrals.sql` to install customer vouchers and loyalty tables.
9. If using subscription orders, apply `supabase/scripts/auto_generate_subscription_orders.sql` before the checkout pricing script; it changes the order idempotency column to text and replaces the order-creation function.
10. Apply `supabase/scripts/fix_customer_checkout_pricing.sql` last. It makes checkout fees and vouchers server-authoritative and makes order retries idempotent.
11. Deploy the Supabase Edge Functions in `supabase/functions`.
12. Run the app with `flutter run`.

For an existing Supabase project showing `Could not find the table 'public.app_releases' in the schema cache`, apply `supabase/scripts/app_version_management_system.sql` in the Supabase SQL Editor, then retry the App Releases screen.

### Realtime and notifications

The catch-up SQL adds existing application tables to the `supabase_realtime`
publication. Apply the updated `supabase/scripts/remote_catchup.sql` in the
Supabase SQL Editor for live order, profile, product, and notification updates.
The app displays OS local notifications for notification rows received while
its realtime connection is active. These are not remote push notifications:
delivery while the app is backgrounded or terminated requires a configured
push provider (Firebase Cloud Messaging/APNs) and a server-side sender, which
this repository does not currently configure.

### Profile recovery

When repairing users whose profile rows are missing, apply
[`supabase/scripts/fix_missing_profiles_and_addresses.sql`](./supabase/scripts/fix_missing_profiles_and_addresses.sql)
in the Supabase SQL Editor. Self-service profile creation only permits the
customer, owner, and rider signup roles; admin roles and rider-to-owner
associations cannot be supplied through Auth user metadata. Admin roles require
trusted provisioning, and rider associations are created through the
server-validated owner workflow.

## Payment Setup

The app uses a server-side PayMongo Checkout flow for GCash, Maya, and card payments. Do not put PayMongo secret keys in Flutter code.

Required Supabase Edge Function secrets:

```bash
supabase secrets set PAYMONGO_SECRET_KEY=sk_live_or_test_key
supabase secrets set APP_PUBLIC_URL=https://your-app-domain.example
supabase secrets set PAYMENT_WEBHOOK_TOKEN=use-a-long-random-token
supabase secrets set PAYMENT_DATA_ENCRYPTION_KEY=use-a-long-random-encryption-passphrase
```

Optional PayMongo webhook signing verification:

```bash
supabase secrets set PAYMONGO_WEBHOOK_SIGNING_SECRET=your_paymongo_webhook_signing_secret
```

If configured, the webhook function will verify PayMongo request signatures from `paymongo-signature` or `x-paymongo-signature` before processing.

Deploy the functions:

```bash
supabase functions deploy create-payment-checkout
supabase functions deploy paymongo-webhook
supabase functions deploy manage-payment-settings
```

In the PayMongo dashboard, configure a webhook endpoint that points to:

```text
https://<project-ref>.functions.supabase.co/paymongo-webhook?token=<PAYMENT_WEBHOOK_TOKEN>
```

The checkout flow is:

1. Customer selects Cash, GCash, Maya, or Card.
2. Flutter creates the order through `create_order_atomic`.
3. For GCash, Maya, or Card, Flutter calls `create-payment-checkout`.
4. The Edge Function creates a PayMongo Checkout Session and returns a secure checkout URL.
5. Customer completes payment in PayMongo.
6. PayMongo calls `paymongo-webhook`.
7. The webhook updates `orders.payment_status`.

## Payment Settings

eRefill supports role-based payment settings:

- Customers can manage preferred payment methods from Account > Quick Actions > Payment Methods.
- Owners can manage receiving accounts from Account > Business Configuration > Payout Accounts.
- Riders do not have access to payment method or payout account settings.

The app uses PayMongo test mode during development. Use a `sk_test_...` key as `PAYMONGO_SECRET_KEY` in Supabase Edge Function secrets. Do not place PayMongo secret keys in Flutter code.

Security rules:

- Do not store full card numbers, CVV, or raw card details.
- Card support must use a payment gateway token or hosted checkout. eRefill stores only token references and safe display fields such as card brand and last four digits.
- GCash, Maya, and bank payout account values are masked in the app.
- Owner payout account references are encrypted in the `manage-payment-settings` Edge Function before being saved.
- Customer payment method access is restricted to customers.
- Owner payout account access is restricted to owners.
- Riders cannot access either payment settings feature.

## Owner / Water Station Setup

To register as a station owner:

1. Open the app.
2. Choose the owner or water station registration path.
3. Enter owner name, station name, mobile number, email, password, town, barangay, and station address.
4. Set the exact station pin on the map.
5. Submit the registration form.
6. After login, open `Account`.
7. Complete or verify:
   - Station name
   - Owner contact details
   - Station town and barangay
   - Station map pin
   - Base delivery fee
   - Price per gallon
   - Station photo/logo
8. Open the refill pricing screen and add available water refill options.
9. Add rider accounts under rider management.
10. Toggle station availability to open when ready to accept orders.

Operational checklist before accepting orders:

- Station location is accurate.
- Purified, Mineral, and Alkaline refill prices are correct and available.
- Delivery fee is correct.
- At least one rider account exists.
- Online payment keys and webhooks are configured if accepting GCash, Maya, or card.
- Test one cash order and one online payment order in sandbox mode.

## Security Notes

- Online payment secrets belong only in Supabase Edge Function secrets.
- Payment proofs, delivery proofs, and chat attachments should use private buckets and signed URLs.
- Order totals must be calculated by database RPCs, not trusted from Flutter.
- Order status transitions should be controlled by RPCs.
- RLS policies should be tested for customer, owner, rider, anonymous, and service-role access.

### Account email verification

Email changes use Supabase Auth's native email-change verification. Configure
the Supabase **Authentication > Email Templates > Change Email** template to
include `{{ .Token }}` so users receive the six-digit code expected by the app.
If resending a new-account confirmation, the **Confirm signup** template must
also include `{{ .Token }}`. With secure email changes enabled, users may need
to confirm both the new address and their current address.
After deploying the updated app, apply
`supabase/scripts/gmail_verification_otp.sql` to remove the legacy client-visible
OTP implementation and keep `profiles.email` synchronized with Auth.

## Quality Checks

Run static analysis:

```bash
dart analyze
```

Run tests:

```bash
flutter test
```
