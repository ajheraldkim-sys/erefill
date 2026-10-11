# eRefill App Audit and Update Notes

## UI/UX Issues Found

- Customer, owner, and rider dashboards used separate bottom-navigation styling.
- Some station search and filter labels still sounded generic instead of refill-focused.
- Empty station results did not clearly explain location/filter recovery.
- Legacy compatibility code still uses `products` and `product_name` database fields, even when the visible UI correctly says refill options.
- Use-case documentation still described browsing and managing products.
- Owner setup depends on all three water refill types being priced, but this requirement should remain highly visible during onboarding and pricing setup.
- Several large screens still contain local card/button styles instead of fully relying on shared components.

## Screen-by-Screen Recommendations

- `customer_home_tab.dart`: Keep the current water-type education and active-order card; next improvement is to show the cheapest available price per nearby station instead of a fallback static price.
- `station_list_screen.dart`: Keep map/list toggle, water-type filters, open-only filters, and favorite station actions; next improvement is a shared station card component used by home and list.
- `station_details.dart`: The water refill selector is aligned with Purified, Mineral, and Alkaline; next improvement is to separate container options from water type when a station offers multiple container sizes.
- `checkout_screen.dart`: Keep COD, GCash, Maya, and Card flow; next improvement is a saved-address selector as the first address section.
- `payment_return_screen.dart`: Already includes success/cancel handling, order number, amount, method, tracking, and return-home actions.
- `order_tracker.dart` and `order_status_tracker.dart`: Continue using the shared lifecycle: Pending, Accepted, Preparing, Ready for Pickup, Assigned to Rider, Out for Delivery, Delivered, Cancelled.
- `service_catalog_screen.dart`: Treat this as Water Type Management/Refill Pricing, not a marketplace catalog.
- `owner_dashboard.dart`: Keep setup checklist and availability states; next improvement is a direct action from checklist items into the matching settings screen.
- `rider_dashboard.dart`: Keep Overview, Dispatch, Logs, Messages, Account; next improvement is a clearer offline sync banner in Dispatch.
- Delivery management screens: Keep offline logs, credits, reports, and profiles; next improvement is one shared empty state and sync status placement across all DM screens.

## Updated Navigation Structure

- Customer: Home, Stations, Orders, Messages, Account.
- Station Owner: Overview, Orders, Riders, Messages, Account.
- Rider: Overview, Dispatch, Logs, Messages, Account.
- App entry: `main.dart` -> `AuthWrapper` -> welcome onboarding -> location permission -> auth entry -> role signup/login -> role dashboard.
- Payment callbacks: `/payment/success` and `/payment/cancel` both open `PaymentReturnScreen`.

## Feature Structure

- Customer features should center on station discovery, water type selection, checkout, payment, live tracking, chat, reviews, addresses, and account settings.
- Owner features should center on station availability, refill pricing, incoming orders, preparation workflow, rider assignment, reports, payout settings, messages, and reviews.
- Rider features should center on assigned jobs, pickup/customer details, map navigation, delivery status, proof of delivery, delivery logs, performance, and chat.

## Reusable Components

- Existing: `ERefillHeader`, `AppTopBar`, `WaterTypeCard`, `RefillOrderStatusTimeline`, `OrderStatusBadge`, `AvailabilityBadge`, `DashboardMetricCard`, `PrimaryButton`, `SecondaryButton`, `EmptyState`, `LoadingState`.
- Added in this update: `RoleBottomNavBar` and `RoleBottomNavItem` for consistent role-based navigation.
- Recommended next reusable component: `StationCard` shared by customer home and station search.

## Empty Screen Content

- Stations: `No refill stations found. Try another area, reset filters, or refresh your location.`
- Customer orders: `No refill orders yet. Choose a nearby station to get started.`
- Owner orders: `No active refill orders. New customer orders will appear here.`
- Rider dispatch: `No assigned deliveries right now. New dispatches will appear here.`
- Messages: `No conversations yet. Order and support messages will appear here.`
- Pricing: `Set up Purified, Mineral, and Alkaline Water prices to open your station.`

## Dashboard Layout

- Customer dashboard: greeting, current delivery location, search, quick station browsing, active order, nearby stations, and water-type education.
- Owner dashboard: station status, setup checklist, today metrics, live order stages, active riders, revenue, and quick actions.
- Rider dashboard: assigned deliveries, completed deliveries, pending deliveries, delivery credits, and active delivery card.

## Order Flow

1. Customer opens app and location guard completes.
2. Customer selects a nearby station.
3. Customer chooses Purified, Mineral, or Alkaline Water.
4. Customer selects quantity/container.
5. Customer confirms delivery address.
6. Customer chooses COD, GCash, Maya, or Card.
7. Owner accepts and prepares order.
8. Owner marks ready for pickup and assigns rider.
9. Rider starts delivery and uploads proof.
10. Customer tracks status and leaves a review after delivery.

## Water Type Management Flow

1. Owner opens Account -> Water Pricing.
2. Owner adds or updates a refill option for Purified, Mineral, or Alkaline Water.
3. Owner sets description, price, container size, preparation time, and availability.
4. Owner completes all required station setup items before opening the station.

## Flutter Recommendations

- Continue using shared theme tokens from `AppUi` and `AppTheme`.
- Gradually replace local dashboard card styles with shared reusable components.
- Keep database field compatibility wrappers where the schema still uses `products`, but expose only refill-service wording in UI.
- Add widget tests for role bottom navigation and station empty states.
- Extract `StationCard` and `PaymentSummaryCard` to reduce duplication.

## Supabase Recommendations

- Keep existing lifecycle migrations for refill order states and payment observability.
- Consider renaming future database views to `water_options` while leaving `products` as a backwards-compatible table or view.
- Add unique constraints only if each station should have one option per water type; otherwise model container size as a separate option dimension.
- Keep proof-of-delivery storage private to order participants.

## Best Next Improvements

- Replace hard-coded station card prices with the station's lowest active refill price.
- Add saved-address selection to checkout.
- Add direct setup-checklist navigation for owners.
- Add a visible offline/sync state to rider dispatch and delivery management screens.
- Finish replacing legacy product wording in non-user-facing docs and diagrams.
