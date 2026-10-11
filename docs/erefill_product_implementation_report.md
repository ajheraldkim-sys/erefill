# eRefill Product Implementation Report

## Product Direction

eRefill is now centered on ordering and delivering water refills from nearby
stations. Customer ordering and owner pricing use three service types only:
Purified Water, Mineral Water, and Alkaline Water.

## Issues Addressed

- Generic catalog language competed with the refill-service purpose.
- Duplicate station storefront and owner product manager screens could diverge.
- Order status handling skipped ready-for-pickup and assigned-to-rider states.
- Riders could effectively be assigned before preparation was complete.
- Station availability was only open or closed and could not explain downtime.
- Water choices did not consistently describe container size or preparation time.
- Owner setup treated a legacy gallon price as complete configuration.
- Reports lacked cancellation, payment method, water-type, and review insights.
- Offline delivery sync could display success after individual sync failures.
- Notifications and map messaging described the old dispatch lifecycle.

## Implemented Navigation

| Role | Tabs |
| --- | --- |
| Customer | Home, Stations, Orders, Messages, Account |
| Station Owner | Overview, Orders, Riders, Messages, Account |
| Rider | Overview, Dispatch, Logs, Messages, Account |

Entry remains protected by `AuthWrapper`: first-install welcome onboarding,
location permission, authentication, then role-based dashboards. Payment callback
routes `/payment/success` and `/payment/cancel` open the payment result screen.

## Implemented Flow

1. Customer selects a nearby open station.
2. Customer chooses Purified, Mineral, or Alkaline Water with price, container,
   and preparation estimate.
3. Customer checks out using Cash on Delivery, GCash, Maya, or Card when enabled.
4. Owner processes `Pending -> Accepted -> Preparing -> Ready for Pickup`.
5. Owner assigns a rider, producing `Assigned to Rider`.
6. Rider starts delivery, producing `Out for Delivery`, and completes with proof.
7. Customer tracks the order and may submit a review after delivery.

Cancelled orders remain a terminal branch before dispatch.

## Screen Improvements

| Area | Improvements |
| --- | --- |
| Customer home and stations | Water-type education, refill wording, station availability badges, actionable browsing |
| Station details | Three water choices, container/preparation details, focused refill order call to action |
| Checkout and payment return | Supported payment labeling, status summary, tracking and home actions |
| Tracking | Complete lifecycle labels and clearer station/rider contact timing |
| Owner overview | Four availability states, separate live order stages, three-type setup requirement |
| Owner orders | Sequential preparation/dispatch actions and ready-only rider assignment |
| Refill pricing | Water-only management with price, container, preparation, and availability |
| Reports | Delivered revenue, cancellation/completion rate, payments, leading water option, monthly ratings |
| Rider dispatch | Assigned and active-delivery states aligned with owner workflow |
| Offline logs | Honest sync state and clearer offline log wording |
| Messaging | New status labels aligned in chat and owner alerts |

## Data Model Changes

Apply the Supabase migrations in order:

- `20260528_01_water_refill_domain.sql`
  Adds water option metadata, restricts refill categories, adds station
  availability, and adds the new order enum values.
- `20260528_02_complete_refill_order_lifecycle.sql`
  Enforces the preparation and dispatch lifecycle, ready-only assignment, and
  checkout capacity/availability checks.
- `20260529_01_private_proofs_and_delivery_notes.sql`
  Locks proof storage to order participants and records optional delivery notes.
- `20260529_02_refill_sla_monitoring.sql`
  Adds lifecycle-aware overdue-order monitoring for owner operations.
- `20260529_03_customer_saved_addresses.sql`
  Adds protected customer delivery addresses selectable during checkout.
- `20260529_04_payment_webhook_observability.sql`
  Stores PayMongo callback processing results and protects operational event
  visibility for customers and station owners.

Implemented follow-up:

- Durable SQLite deletion tombstones now protect offline delivery, rider, and
  credit removals from being re-downloaded during synchronization.
- Private proof access, delivery notes, owner SLA alerts, and selectable saved
  customer addresses are implemented in the current phase set.
- Failed PayMongo callbacks and delivery-log sync failures now produce
  actionable owner alerts after the latest backend deployment is applied.
- Local regression tests now cover unified status/availability presentation,
  expired-payment retry messaging, address snapshots, and sync deletion
  routing.

Recommended production follow-ups:

- Add integration tests for Supabase RPC permissions, payment callbacks, and
  proof-of-delivery uploads.
- Deploy the payment callback observability migration and updated webhook Edge
  Function, then verify failure alerts in PayMongo test mode.

## Reusable UI Building Blocks

Continue using the shared app header and theme tokens as the basis for all new
screens. The main reusable components now available are:

- `WaterTypeCard` for customer selection and owner pricing previews.
- `RefillOrderStatusTimeline` shared by customer and operations views.
- `AvailabilityBadge` for Open, Busy, Maintenance, and Closed stations.
- `DashboardMetricCard` for role dashboards and reports.
- `EmptyState` and `LoadingState` for reusable screen states.

Implemented in this pass: shared water type cards across customer selection
and owner refill pricing, shared refill status timeline, shared lifecycle and
availability badges, owner dashboard/report metric cards, plus shared
empty/loading state usage in order, notifications, messages, delivery
management, rider management, rider performance, reports, credits, and ledger
paths. Customer checkout and payment return also use the shared loading state,
and remaining setup/help copy now refers to refill options instead of generic
products or cart items. Customer and rider order summaries now use refill
wording and water-type fallbacks while preserving existing database field names.
Owner order detail sheets now label purchased refill rows as refill details, and
rider performance scores are derived from completed delivery timing instead of
hard-coded placeholder values. Nearby station cards now show `New` for unrated
stations rather than a fake default rating.

## Empty-State Content

- Stations: `No nearby refill stations found. Try another area or refresh your location.`
- Customer orders: `No refill orders yet. Choose a nearby station to get started.`
- Owner orders: `No active refill orders. New customer orders will appear here.`
- Rider dispatch: `No assigned deliveries right now. New dispatches will appear here.`
- Messages: `No conversations yet. Messages about orders and support will show here.`
- Pricing: `Set up Purified, Mineral, and Alkaline Water prices to open your station.`
