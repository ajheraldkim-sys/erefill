# eRefill Production-Readiness Audit

**Status:** In progress; not a production sign-off
**Last updated:** 2026-10-16

This audit records findings that were verified in the repository or by commands
run during this pass. It distinguishes local source findings from live Supabase
configuration. The supplied audit prompt ends partway through Phase 12, so
requirements after that point may be missing.

## Verified changes

- Login now preserves password whitespace and trims only the account identifier.
- Startup renders the app after Supabase initialization, then hydrates the local
  cache and initializes notifications after the first frame.
- Cache hydration no longer overwrites a newer in-memory value with stale disk
  data.
- Profile reads use an explicit field projection and `maybeSingle()`, avoiding
  the previous zero-row `PGRST116` error shape.
- Debug-only timing diagnostics cover Supabase readiness, username lookup,
  password sign-in, and profile loading. They do not record credentials.
- A widget regression test verifies password whitespace preservation and checks
  the compact login layout for rendering exceptions.
- Android debug builds now use the standard debug signer. Release signing reads
  from ignored `android/key.properties` or `EREFILL_*` environment variables;
  release tasks fail if signing values are missing. No signing secret is stored
  in the tracked Gradle file.

## Validation performed

| Check | Result |
|---|---|
| `flutter analyze` for the root Flutter project | Passed; no issues found |
| Full Flutter test suite | 205 passed, 0 failed |
| Focused login/profile tests | 6 passed, 0 failed |
| Android debug APK build after signing changes | Passed |
| Android release APK build before signing hardening | Passed, but used the insecure configuration described below; do not distribute that artifact |
| Android release APK build after signing hardening, without external credentials | Correctly blocked by `validateReleaseSigning` |
| `git diff --check` | Passed |

The Gradle wrapper, Android Gradle Plugin, and Kotlin plugin emit Flutter
compatibility deprecation warnings. Update them in a separate, tested toolchain
change. No controlled device/network benchmark or iOS release build was run.

## Findings and release gates

### High — Supabase RLS and grants are not production-verified

A read-only live catalog query reported row-level security disabled on
`domain_events`, `ledger_entries`, `operational_metrics`, `order_items`,
`rate_limit_events`, `regions`, `remittances`, and `suspicious_activities`.
RLS-disabled status alone does not establish which API roles can access those
tables; grants, policies, and application role boundaries could not be fully
queried because temporary database-role authentication failed. Do not treat
these tables as safe for client access until grants and access paths are
verified.

**Gate:** Restore authorized, read-only catalog access. Verify table grants,
RLS, policies, exposed functions, and storage policies against the deployed
project. Then prepare narrow versioned migrations and test them in a safe
environment. No speculative policy changes were applied.

### High — Destructive database recreation scripts must not be used in production

`supabase/scripts/recreate/01_wipe_all.sql` deletes storage objects and auth
users, drops and recreates the `public` schema, and grants broad default
privileges to `anon` and `authenticated`. The paired
`supabase/scripts/recreate/02_schema.sql` also contains permissive public
profile policies and broad profile grants. These are source-script findings;
the scripts were not run against the live project, and live exposure was not
confirmed.

**Gate:** Keep recreation scripts out of production deployment workflows.
Replace production schema changes with reviewed, incremental migrations and
verify the deployed policies independently.

### High — Android release-signing credentials were embedded in tracked build configuration

The previous Gradle configuration hardcoded release passwords and used the
release signer for debug builds. The keystore file itself is locally ignored,
but hardcoded credentials in tracked source should be treated as exposed.
The build now loads signing values from ignored `android/key.properties` or
environment variables and refuses release builds without them.

**Gate:** Before distributing a release, rotate the affected upload/signing
credential using the platform's supported key-reset process, configure the new
values outside source control, and build and verify a newly signed artifact.
Do not replace a Play app-signing key without following the Play Console
rotation procedure. The APK built before this change is not a production
artifact.

### Medium — Client-side role routing is incomplete; server enforcement remains unverified

`lib/core/routing/app_router.dart` applies a client-side role check to a subset
of owner routes, while other role screens, including the admin dashboard route,
are registered without equivalent route redirects. Client routing is only a
UX boundary and cannot authorize access. The live RLS/RBAC rules that must
protect these screens' data could not be verified.

**Gate:** Verify backend authorization for every role and operation before
release. Then add role-aware route behavior using a server-controlled role
source, without treating client routing as a substitute for RLS.

### Medium — Username sign-in depends on profile-query access

Username login resolves the email by querying `profiles`. The recreation
schema contains public profile-select policies, which could expose profile
fields if that schema and its grants are deployed. Whether this is exploitable
in the live project is unknown because live grants and policies were not
verified.

**Gate:** Audit actual deployed profile policies and grants. If username
resolution is needed, use a narrowly scoped server-side lookup that returns no
email/profile data to unauthenticated callers and does not enable username
enumeration.

### Medium — Database deployment history is script-based and drift-prone

The repository has Supabase SQL scripts but no `supabase/migrations` directory.
This makes the order and provenance of production changes difficult to verify.

**Gate:** Establish a migration-based, reviewable deployment process and
reconcile it with the live schema before applying changes. Do not reset or
recreate production data.

## Remaining audit scope

The following work is not complete and must not be inferred from the checks
above:

- Verify live grants, RLS/RBAC, functions, triggers, indexes, storage policies,
  and production schema drift.
- Exercise customer, owner, rider, and admin workflows end-to-end against a
  safe staging project, including empty/error/retry/offline states.
- Inspect all screens for loading-state termination, pagination, query
  patterns, Realtime subscription lifecycle, and authorization boundaries.
- Measure login, dashboard, station search, checkout, order confirmation, and
  Realtime latency on a controlled device/network.
- Validate payment-provider production configuration, Android signing rotation,
  iOS release/signing, and release permissions on target devices.
- Review production monitoring, privacy/data retention, and dependency
  vulnerability status.

No production database was reset or modified during this audit.
