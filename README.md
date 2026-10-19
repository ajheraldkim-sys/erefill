# eRefill

<p align="center">
  <img src="assets/images/splash_wordmark.png" alt="eRefill" width="220" />
</p>

<p align="center">
  <a href="https://github.com/ajheraldkim-sys/erefill/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/ajheraldkim-sys/erefill/ci.yml?branch=main&label=CI" alt="CI status" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ajheraldkim-sys/erefill" alt="License" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter" /></a>
  <a href="https://supabase.com"><img src="https://img.shields.io/badge/Supabase-Postgres-3ECF8E?logo=supabase" alt="Supabase" /></a>
</p>

A modern water refilling and delivery platform for customers, station owners, and riders. eRefill streamlines ordering, station operations, route fulfillment, payments, and live operational workflows in a single mobile-first system.

## 1. Overview

eRefill is a Flutter + Supabase application designed for local water refilling businesses. It supports the full service cycle from customer ordering to station fulfillment and rider delivery. The app is built to handle real-world operations such as live order updates, payment processing, proof of delivery, and offline resilience.

The goal is to reduce manual coordination between customers, owners, and riders while making the refill process reliable, fast, and transparent.

## 2. Why this project exists

Many water refilling stations still rely on fragmented communication methods, manual delivery coordination, and inconsistent order tracking. eRefill centralizes those workflows into a single platform with:

- customer ordering and checkout
- owner station management
- rider delivery assignment and task tracking
- notification and messaging workflows
- proof-of-delivery validation
- secure payment handling
- offline-friendly delivery operations

## 3. Features

### Customer features
- browse station listings and refill options
- place delivery orders and manage cart flow
- save and reuse delivery addresses
- review payment methods and checkout flow
- receive order updates and notifications

### Owner features
- manage station profile, pricing, and locations
- review incoming orders and dispatch workflows
- manage rider assignments and station availability
- track delivery performance and operational updates

### Rider features
- accept available delivery tasks
- navigate delivery assignments
- submit proof of delivery and status updates
- work with offline queue support during intermittent connectivity

### Admin access
- administrative tools are available only in the separate desktop app under `admin/`
- the main eRefill mobile app supports customer, station owner, and rider accounts

### Operational features
- real-time update channels through Supabase
- local SQLite synchronization for delivery tasks
- app release management and audit tracking
- secure payment integration with hosted checkout

## 4. Demo / Screenshots

Add screenshots and short walkthrough clips in this section:

```text
assets/screenshots/overview.png
assets/screenshots/customer-order.png
assets/screenshots/owner-dashboard.png
assets/screenshots/rider-delivery.png
```

If you want to showcase the app visually, insert a few image previews here with relative paths or a hosted gallery link.

## 5. Tech stack

- Flutter
- Dart
- Supabase Auth
- Supabase Postgres
- Supabase Realtime
- Supabase Storage
- Edge Functions
- SQLite for offline delivery workflows
- OpenStreetMap via `flutter_map`
- PayMongo Checkout
- Provider for app state management

## 6. Architecture

The application follows a layered structure:

- Flutter UI layer for customer, owner, and rider experiences
- service and repository layer for Supabase interaction
- local cache/offline sync layer for delivery workflows
- Edge Functions for secure payment and backend orchestration
- database-side business logic and RPCs for critical rules and status transitions

This keeps sensitive logic off the client and improves reliability in production use.

## 7. Project structure

```text
.
├── lib/                         # Flutter app source
├── admin/                      # Separate desktop-only admin Flutter app
├── supabase/
│   ├── functions/              # Edge Functions
│   └── scripts/                # SQL schema and migration scripts
├── test/                       # Automated tests
├── docs/                       # Design and implementation docs
├── assets/                     # Images, fonts, icons, animations
├── android/                    # Android native config
├── ios/                        # iOS native config
├── macos/                      # macOS native config
├── windows/                    # Windows native config
├── web/                        # Web entry files
├── .github/workflows/ci.yml    # CI pipeline
├── README.md                   # Project documentation
├── SECURITY.md                 # Security reporting policy
├── LICENSE                     # MIT license
├── .env.example                # Environment variable template
├── pubspec.yaml                # Flutter app dependencies
├── analysis_options.yaml       # Dart lint and analysis rules
└── .gitignore
```

## 8. Prerequisites

Before you start, make sure you have:

- Flutter SDK installed
- Dart SDK bundled with Flutter
- a Supabase project configured
- access to the repository and a local environment for app runs
- optional: a PayMongo account for payment testing

## 9. Installation

Clone the repo:

```bash
git clone https://github.com/ajheraldkim-sys/erefill.git
cd erefill
flutter pub get
```

Install dependencies and verify Flutter is working correctly:

```bash
flutter --version
flutter doctor
```

## 10. Configuration

Set up your app configuration and secret values carefully.

### Supabase
Configure your project values in `lib/core/constants.dart` and ensure the required database schema is installed.

### Environment variables
Use `.env.example` as a template and never commit real secrets into source control.

```bash
cp .env.example .env.local
```

For payment processing, configure the required Supabase Edge Function secrets:

```bash
supabase secrets set PAYMONGO_SECRET_KEY=sk_live_or_test_key
supabase secrets set APP_PUBLIC_URL=https://your-app-domain.example
supabase secrets set PAYMENT_WEBHOOK_TOKEN=use-a-long-random-token
supabase secrets set PAYMENT_DATA_ENCRYPTION_KEY=use-a-long-random-encryption-passphrase
```

Optional signing verification:

```bash
supabase secrets set PAYMONGO_WEBHOOK_SIGNING_SECRET=your_paymongo_webhook_signing_secret
```

## 11. Running locally

Run the app in development mode:

```bash
flutter run
```

Run static analysis:

```bash
dart analyze
```

Run the test suite:

```bash
flutter test
```

## 12. Database and backend setup

This project relies on a working Supabase schema and supporting SQL scripts. Apply the required setup in the recommended order:

```text
supabase/scripts/remote_catchup.sql
supabase/scripts/automated_proof_of_delivery.sql
supabase/scripts/app_version_management_system.sql
supabase/scripts/loyalty_and_referrals.sql
supabase/scripts/auto_generate_subscription_orders.sql
supabase/scripts/fix_customer_checkout_pricing.sql
supabase/scripts/security_hardening_rls_and_rpc_guards.sql
supabase/scripts/subscription_orders_server_pricing.sql
supabase/scripts/credit_returned_empties_on_delivery.sql
supabase/scripts/views_security_invoker.sql
```

After releasing the app version that calls `generate_due_subscription_orders`
and making it the minimum required version, apply:

```text
supabase/scripts/lock_direct_order_inserts.sql
```

Each of the last five scripts has a matching `*_rollback.sql`.

Important notes:
- if app release tables are missing, run `app_version_management_system.sql`
- realtime publication must include the needed app tables
- missing profile records can be repaired with the profile and address recovery script

## 13. Usage

After setup, the app is used by three primary roles:

1. Customer
   - browse stations
   - place refill orders
   - save local addresses
   - pay and track delivery updates

2. Station owner
   - manage pricing and stock availability
   - process order requests
   - assign riders
   - review operational status

3. Rider
   - accept assignments
   - update route status
   - submit proof of delivery

## 14. Testing

This repository includes functional and UI regression tests under `test/`.

Run the suite with:

```bash
flutter test
```

Recommended checks before submitting changes:

```bash
dart analyze
flutter test
```

## 15. Roadmap

Planned improvements and expansion areas include:

- stronger role-based access validation and policy checks
- expanded notification and push support
- deeper analytics and reporting for owners and admins
- broader localization and multilingual support
- improved offline-first synchronization and conflict resolution
- release automation and deployment checks

## 16. Contributing

Contributions are welcome. To contribute:

1. fork the repository
2. create a feature branch
3. make focused changes with tests when needed
4. run validation checks
5. open a pull request with a clear summary

Suggested contribution standards:

- keep changes small and well-scoped
- avoid committing secrets or local environment data
- document setup changes and configuration updates
- validate security-sensitive changes carefully

## 17. Security

This project processes customer information, payment references, and operational delivery data. Do not expose secrets or sensitive values in logs or committed files.

Please review [SECURITY.md](./SECURITY.md) for responsible disclosure expectations and vulnerability reporting.

## 18. License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for full details.

## 19. Contact

For project questions, updates, or collaborations, use the repository's GitHub issues or reach out through the maintainer profile associated with this project.

## 20. Acknowledgements

This project builds on Flutter, Supabase, OpenStreetMap tooling, and modern mobile delivery architecture practices. Thanks to the open-source communities supporting the tools used in this repository.
