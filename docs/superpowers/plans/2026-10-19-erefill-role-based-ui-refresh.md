# eRefill Role-Based UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give eRefill a distinctive, polished interface across customer, station-owner, rider, and desktop-admin workflows without changing business behavior.

**Architecture:** Keep the existing Flutter/Material design system, navigation, and motion helpers, while updating the shared light-mode palette to the approved eRefill tones. Improve hierarchy and layout within each role's primary workflows, using shared tokens consistently and adding motion only where it clarifies a user-triggered state change. Keep the admin console desktop-first and preserve its existing role restrictions.

**Tech Stack:** Flutter, Dart, Material 3, existing Provider and Supabase integrations, existing Flutter widget/unit tests. No new packages.

**Spec:** Approved design direction is captured in the "Approved design brief" section of this plan.

## Approved design brief

- **Color:** cool mist `#F3F7F7`, white `#FFFFFF`, deep slate `#20313A`, eRefill blue `#0F71C3`, and pale water `#D8E8E5`, alongside existing contrast-safe semantic status colors.
- **Type:** retain bundled Plus Jakarta Sans; use a clearer scale for titles and key values, plain sentence-case labels, and concise user-facing copy.
- **Customer layout:** prioritize local context, nearby station discovery, prices/availability, and clear order progress.
- **Owner layout:** put pending operational work first; keep station availability and inventory close at hand.
- **Rider layout:** make the active delivery, route details, and one large next action immediately visible.
- **Admin layout:** keep data-dense workspaces, readable tables, and desktop-first navigation.
- **Motion:** use existing motion helpers and keep transitions brief and tied to an action or state change. No ambient motion, repeated entrance effects, or new autoplay. Respect reduced-motion settings and visible keyboard focus.
- **Distinctiveness:** use eRefill's real service geography, station proximity, and route context as useful information rather than generic decoration. Do not make every section an identical card grid.
- **Non-goals:** do not change backend behavior, business rules, data models, routes, authentication, or the desktop-only admin restriction. Do not add dependencies or introduce gradients, purple/indigo accents, blur, or glass effects.

## Global Constraints

- Keep `AppUi.bluePrimary` at `#0F71C3`; add the approved mist `#F3F7F7`, deep slate `#20313A`, and pale water `#D8E8E5` as shared `AppUi` tokens and retain the existing contrast-tested semantic palette.
- Keep the saturated brand, semantic, and order-status colors as they are; do not desaturate them.
- Keep Plus Jakarta Sans and the existing shared spacing, radius, and breakpoint tokens; do not introduce screen-specific hard-coded design tokens.
- Use `AppUi.motionFast`, `AppUi.motionBase`, `AppUi.motionSlow`, and `AppUi.motion(context, ...)` for any new animation; motion must stop or reduce to zero when `AppUi.reduceMotion(context)` is true.
- Maintain a minimum 48 dp touch target for general controls and 56 dp for rider primary actions.
- Preserve customer/owner/rider navigation and all existing order, payment, inventory, offline, and admin access behavior.
- Keep desktop admin access unavailable in mobile app experiences.
- Add no new packages and no gradients, purple/indigo accents, backdrop blur, or glass-style surfaces.

## Review Focus

- **Narrow phones and increased text scale:** location, station names, prices, and primary actions must remain visible without overflow. Pin at 320 dp and 1.25 text scale in customer and navigation widget tests.
- **Long or missing station data:** long names and absent station imagery must retain readable price and availability details; empty discovery results must offer a next step. Cover long-name and empty-result customer states.
- **Order status variation:** canonical and aliased statuses must retain correct labels and colors in owner queues and admin records. Keep existing order-status and queue-priority tests in the focused run.
- **Rider connectivity and job state:** active, empty, and offline states must remain actionable, with the rider's primary action at least 56 dp high. Cover these states in rider widget tests.
- **Reduced motion and keyboard use:** new transitions must respect reduced motion and preserve visible focus for role navigation and actions. Add assertions to the relevant widget tests.

---

### Task 1: Applying the approved shared palette

**Files:**
- Modify: `lib/core/constants.dart`
- Test: `test/design_tokens_contrast_test.dart`

**Interfaces:**
- Consumes: existing `AppUi` tokens used by both Flutter app and admin theme.
- Produces: shared light-mode tokens for page background, primary text, and pale-water surfaces; preserve brand blue, dark-mode tokens, and semantic feedback colors.

- [ ] **Step 1: Write failing token tests** in `test/design_tokens_contrast_test.dart` named `uses_the_approved_light_palette` and `approved_palette_tokens_keep_required_contrast`. Assert page background `#F3F7F7`, primary text `#20313A`, pale-water tint `#D8E8E5`, brand primary `#0F71C3`, and at least 4.5:1 contrast for text/brand foregrounds on the updated light surfaces.
- [ ] **Step 2: Run the focused token test** with `flutter test test/design_tokens_contrast_test.dart`; verify the new palette assertions fail before changing tokens.
- [ ] **Step 3: Add or update the named shared `AppUi` token values** in `lib/core/constants.dart`; keep screen code consuming tokens rather than hard-coding these colors.
- [ ] **Step 4: Run token and theme regression tests** with `flutter test test/design_tokens_contrast_test.dart test/dark_mode_color_helpers_test.dart`; verify exact token values, light/dark contrast, status tones, and the no-gradient/purple/glass scan pass.

### Task 2: Reworking customer discovery and ordering

**Files:**
- Modify: `lib/features/dashboard/customer/customer_home_tab.dart`
- Modify: `lib/features/dashboard/customer/station_list_screen.dart`
- Modify: `lib/features/dashboard/customer/station_details.dart`
- Modify: `lib/features/dashboard/customer/cart_screen.dart`
- Modify: `lib/features/dashboard/customer/checkout_screen.dart`
- Modify: `lib/features/dashboard/customer/customer_orders_list.dart`
- Modify: `lib/features/dashboard/customer/order_detail_screen.dart`
- Test: `test/customer_discovery_layout_test.dart`

**Interfaces:**
- Consumes: existing station, cart, order, locality, routing, and `AppUi` APIs.
- Produces: a customer discovery-to-order flow with locality-first station browsing, clear selection/checkout actions, and legible order progress. Preserve all existing data and navigation contracts.

- [ ] **Step 1: Write failing widget tests** in `test/customer_discovery_layout_test.dart` named `shows_local_context_and_station_action_at_compact_width`, `keeps_long_station_names_and_prices_visible_with_larger_text`, and `guides_customers_when_no_stations_are_available`. Assert the locality and station action remain visible at 320 dp, long names/prices do not overflow at 1.25 text scale, and empty results provide a next action.
- [ ] **Step 2: Run the focused test** with `flutter test test/customer_discovery_layout_test.dart`; verify the new assertions fail against the current layout.
- [ ] **Step 3: Implement the customer layout** across the listed screens using existing `AppUi` tokens. Prioritize location and station discovery, keep station price/availability easy to scan, and make order progress read as a useful sequence rather than a decorative card.
- [ ] **Step 4: Add action-linked motion** only to meaningful selection or progress state changes, using existing `AppUi` motion helpers and respecting reduced motion.
- [ ] **Step 5: Run customer regression tests** with `flutter test test/customer_discovery_layout_test.dart test/customer_orders_load_notice_test.dart test/customer_profile_tiles_test.dart test/station_card_test.dart`; verify all pass with no overflow or behavior regressions.

### Task 3: Prioritizing station-owner operations

**Files:**
- Modify: `lib/features/dashboard/owner/owner_dashboard.dart`
- Modify: `lib/features/dashboard/owner/owner_order_queue.dart`
- Modify: `lib/features/dashboard/owner/owner_inventory_screen.dart`
- Modify: `lib/features/dashboard/owner/widgets/owner_order_detail_sheet.dart`
- Test: `test/owner_dashboard_layout_test.dart`
- Test: `test/owner_order_queue_test.dart`

**Interfaces:**
- Consumes: existing station setup, availability, inventory, order status, and queue-priority APIs.
- Produces: a responsive owner overview where pending work is primary and availability, stock, and recent activity remain easy to reach; preserve current state transitions.

- [ ] **Step 1: Write failing widget tests** in `test/owner_dashboard_layout_test.dart` named `puts_pending_orders_before_summary_metrics`, `shows_station_availability_and_stock_near_operational_work`, and `shows_clear_empty_queue_state`. Assert pending work appears before metrics, station status and inventory are accessible without burying the queue, and zero pending orders show a useful empty state.
- [ ] **Step 2: Run focused owner tests** with `flutter test test/owner_dashboard_layout_test.dart test/owner_order_queue_test.dart`; verify the new layout assertions fail while existing queue-order rules remain covered.
- [ ] **Step 3: Implement the owner layout** using a queue-first hierarchy, with a responsive side rail on wide layouts and a readable single-column sequence on phones. Keep canonical status mapping and queue ordering unchanged.
- [ ] **Step 4: Add motion for explicit owner actions** such as availability and order-state changes only; use existing motion helpers and preserve status text/icons.
- [ ] **Step 5: Run owner tests** with `flutter test test/owner_dashboard_layout_test.dart test/owner_order_queue_test.dart test/owner_order_detail_sheet_test.dart`; verify queue behavior, empty state, and order detail behavior pass.

### Task 4: Clarifying the rider delivery workspace

**Files:**
- Modify: `lib/features/dashboard/rider/rider_dashboard.dart`
- Modify: `lib/features/dashboard/rider/widgets/rider_home_overview.dart`
- Modify: `lib/core/widgets/rider_active_delivery_card.dart`
- Modify: `lib/features/dashboard/rider/widgets/rider_swipe_to_accept_slider.dart`
- Test: `test/rider_home_layout_test.dart`
- Test: `test/app_animations_test.dart`

**Interfaces:**
- Consumes: existing active-order, online/offline, route, offline-sync, and delivery-confirmation APIs.
- Produces: an at-a-glance rider workspace centered on the current job, route context, and one large next action. Preserve offline queue and delivery transition rules.

- [ ] **Step 1: Write failing rider widget tests** in `test/rider_home_layout_test.dart` named `shows_active_delivery_and_next_action_first`, `uses_large_primary_action_target`, `shows_guidance_without_an_active_delivery`, and `keeps_offline_sync_status_visible`. Assert active job details and action are first, the action is at least 56 dp tall, the no-job state suggests the next step, and offline status remains visible.
- [ ] **Step 2: Run focused rider tests** with `flutter test test/rider_home_layout_test.dart test/app_animations_test.dart`; verify new state and target-size assertions fail where the current UI does not meet them.
- [ ] **Step 3: Implement the rider hierarchy** in the overview and active-delivery surfaces. Keep route and pickup/dropoff information easy to scan and retain existing online, notification, and sync controls.
- [ ] **Step 4: Add or refine user-triggered transition feedback** for job acceptance and completion with existing motion helpers; verify reduced-motion behavior in `test/app_animations_test.dart`.
- [ ] **Step 5: Run rider regression tests** with `flutter test test/rider_home_layout_test.dart test/app_animations_test.dart test/order_status_transition_test.dart test/queued_delivery_rules_test.dart`; verify delivery and offline behavior remain intact.

### Task 5: Refining desktop admin workspaces

**Files:**
- Modify: `admin/lib/theme/admin_theme.dart`
- Modify: `admin/lib/shell/admin_shell.dart`
- Modify: `admin/lib/features/dashboard/dashboard_screen.dart`
- Modify: `admin/lib/features/stations/stations_screen.dart`
- Modify: `admin/lib/features/orders/orders_screen.dart`
- Modify: `admin/lib/features/users/users_screen.dart`
- Test: `admin/test/admin_responsive_layout_test.dart`
- Test: `test/admin_dashboard_and_routing_test.dart`

**Interfaces:**
- Consumes: existing admin theme, shell navigation, table filtering, permissions, and dashboard data.
- Produces: a consistent, desktop-first review workspace with readable tables and filters, while preserving existing admin permissions and mobile restriction behavior.

- [ ] **Step 1: Write failing responsive admin tests** in `admin/test/admin_responsive_layout_test.dart` named `keeps_admin_navigation_and_content_usable_at_desktop_widths`, `collapses_navigation_without_clipping_at_compact_width`, and `preserves_keyboard_focus_on_admin_actions`. Assert content remains readable at 1024 dp and 1440 dp, compact shell navigation remains reachable, and focused actions show visible focus.
- [ ] **Step 2: Run the admin layout test** with `cd admin; flutter test test/admin_responsive_layout_test.dart`; verify the new layout assertions fail against the current shell or screens.
- [ ] **Step 3: Implement the admin hierarchy** across the theme, shell, dashboard, station, order, and user workspaces. Use compact table-first information design and avoid duplicating the phone-app layout.
- [ ] **Step 4: Preserve mobile admin protection** and verify existing admin desktop-only routing tests.
- [ ] **Step 5: Run admin tests** with `cd admin; flutter test test/admin_responsive_layout_test.dart test/widget_test.dart`; verify both new layout and existing behavior tests pass.

### Task 6: Document and verify the unified visual system

**Files:**
- Modify: `design-system/erefill/MASTER.md`
- Modify: `design-system/erefill/pages/owner-overview.md`
- Create: `design-system/erefill/pages/customer-home.md`
- Test: `test/design_tokens_contrast_test.dart`
- Test: `test/role_bottom_nav_mobile_test.dart`
- Test: `test/admin_dashboard_and_routing_test.dart`

**Interfaces:**
- Consumes: completed customer, owner, rider, and admin layouts from Tasks 1–4.
- Produces: maintained design guidance describing the shared tokens, role-specific hierarchy, and motion/accessibility requirements.

- [ ] **Step 1: Update design guidance** to document role-specific layout priorities, the existing color/type/spacing tokens, appropriate motion, reduced-motion behavior, and the prohibition on gradients, purple, and glass effects.
- [ ] **Step 2: Run focused root tests** with `flutter test test/customer_discovery_layout_test.dart test/owner_dashboard_layout_test.dart test/rider_home_layout_test.dart test/design_tokens_contrast_test.dart test/role_bottom_nav_mobile_test.dart test/admin_dashboard_and_routing_test.dart test/order_status_colors_test.dart test/queued_delivery_rules_test.dart`; verify all assertions pass.
- [ ] **Step 3: Run focused admin tests** with `cd admin; flutter test test/admin_responsive_layout_test.dart test/widget_test.dart`; verify all assertions pass.
- [ ] **Step 4: Run root and admin analyzers** with `flutter analyze` and `cd admin; flutter analyze`; verify both report no issues.
- [ ] **Step 5: Run full root and admin test suites** with `flutter test` and `cd admin; flutter test`; verify zero failures and report any known non-fatal external service errors separately.
- [ ] **Step 6: Run `git diff --check`** and review the final diff for unrelated changes, unintended business-behavior changes, prohibited visual effects, and untested responsive states.
