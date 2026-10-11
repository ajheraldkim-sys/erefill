# eRefill Remaining Implementation Phases

This roadmap tracks production work that remains after the water-refill product
and lifecycle update.

## Phase 1: Reliable Offline Deletes

Status: Implemented

- Store deletion tombstones in SQLite for deliveries, credits, and riders.
- Push queued deletions before cloud pulls so deleted records cannot reappear.
- Preserve an honest `Needs Sync` state when cloud deletion fails.
- Restore deleted delivery logs without creating duplicate inventory or credit
  entries when Undo is selected.

Implemented in the SQLite delivery module and sync service. Local database
version `2` creates `dm_pending_deletions`; synchronization commits those
deletions before downloading cloud records.

## Phase 2: Private Proof Storage

Status: Implemented

- Convert payment proof and delivery proof buckets from public to private.
- Restrict read access to the customer, station owner, and assigned rider.
- Serve proof images through signed URLs.
- Add an optional rider delivery note alongside photo and signature evidence.

Implemented with participant-scoped storage policies, signed customer proof
links, and delivery-note capture in rider confirmation.

## Phase 3: Operational Monitoring

Status: Implemented

- Update SLA monitoring for `ready_for_pickup` and `assigned_to_rider`.
- Surface overdue preparation, assignment, and delivery alerts on owner screens.
- Track PayMongo webhook failures and synchronization failures.

Implemented for lifecycle stage SLA alerts and failed/expired payment checkout
alerts in owner notifications. Synchronization failures now retain a domain
event audit trail in addition to the delivery module `Needs Sync` badge.

## Phase 4: Integration Verification

Status: Partially implemented

- Add Supabase RPC permission and transition tests.
- Add payment callback/webhook scenario tests.
- Add proof-of-delivery upload and confirmation tests.
- Add offline synchronization conflict and recovery tests.

Added regression coverage for customer status labels, availability labels,
retryable expired payments, selectable delivery address snapshots, and offline
deletion-to-cloud routing. Sync failure observability now has a local regression
test for the owner-scoped event payload. Live Supabase RPC, storage-policy, and
PayMongo callback tests require a configured integration test project and remain
pending.

## Phase 5: Customer Completeness

Status: Implemented

- Support multiple saved delivery addresses with a checkout selector.
- Extract shared empty/loading/error components across remaining screens.
- Consolidate any remaining legacy operational ledger entry points.

Implemented multiple customer address records and checkout selection. Shared
state-component extraction has been completed for the main customer, owner, and
rider operational screens in Phase 7.

## Phase 6: Payment Callback Observability

Status: Implemented locally, deployment required

- Persist recognized PayMongo webhook outcomes and failed processing details.
- Restrict callback event visibility to the affected customer and station owner.
- Surface failed callback processing in owner notifications.

Implemented through the `payment_webhook_events` migration, webhook function
instrumentation, and owner operational alerts. The migration and updated Edge
Function must be deployed to the Supabase project.

## Phase 7: Shared Operational UI

Status: Implemented across primary and secondary operational screens

- Centralize lifecycle status badges, station availability badges, and
  dashboard metric cards.
- Centralize water type service cards and the refill order status timeline.
- Reuse common loading and empty states on customer, owner, and rider
  operational workflows.
- Continue extracting less-visible modal internals only where the duplicated UI
  causes user confusion.

Implemented for customer order tracking, customer home water education, station
details water selection, owner refill pricing, nearby station browsing,
messages, owner overview, owner order management, owner notifications, owner
reports, owner and rider delivery-management reports/logs/credits, rider
management, rider performance, the owner credits ledger, customer checkout, and
payment return.
