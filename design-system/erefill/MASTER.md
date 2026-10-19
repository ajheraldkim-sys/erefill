# eRefill Design System — Master

> Source of truth for every eRefill surface: the customer, station owner and
> rider apps (`lib/`) and the admin console (`admin/`). When a page file exists
> in `design-system/erefill/pages/<page>.md`, its rules override this file.
>
> Code is canonical. Every value below lives in
> [`lib/core/constants.dart`](../../lib/core/constants.dart) (`AppUi`),
> [`lib/core/theme/app_colors.dart`](../../lib/core/theme/app_colors.dart) and
> [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart).
> Never hard-code a color, radius or font size in a screen.

## Direction

**Minimal, operational, water-calm.** Neutral slate surfaces, one brand blue
accent, borders instead of shadows, and color reserved for meaning (status).
Generated with the UI UX Pro Max skill
(`search.py "water delivery ordering SaaS …" --design-system`), then adapted:

| Skill recommendation | Decision | Why |
|---|---|---|
| Style "Vibrant & Block-based" | **Rejected** → Minimalism / Swiss + Flat | The brief asks for minimal and operational; the skill's own style search ranks Minimalism & Swiss (WCAG AAA) for SaaS dashboards. |
| Primary cyan `#0891B2` | **Kept existing brand blue `#0F71C3`** | Same water hue family, already in launcher icon and splash, 5.0:1 on white. Cyan `#42C2C8` stays as the dark-mode primary. |
| CTA green `#22C55E` | **Rejected** | 2.3:1 on white; a second accent competes with status green. Primary actions use brand blue. |
| Inter | **Kept Plus Jakarta Sans** | Same "clean, functional" role; already bundled; switching changes text metrics on 200+ screens. |
| Data-dense dashboard for admin | **Adopted** for admin tables and owner queues | Space-efficient, WCAG AA. |
| 150–300 ms transitions, reduced motion, 44–48 dp targets, visible focus | **Adopted** | See Motion and Interaction. |

## Color

### Brand & neutrals (light / dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `bluePrimary` / `accentCyan` | `#0F71C3` | `#42C2C8` | Primary actions, active nav, links, focus |
| `blueSoft` | `#EEF6FD` | cyan 16 % | Selected chips, nav indicator, info tint |
| `pageBg` / `darkPageBg` | `#F8FAFC` | `#0B1220` | Scaffold |
| `surface` / `darkSurface` | `#FFFFFF` | `#111A2B` | Cards, sheets, dialogs, inputs |
| `lightSurfaceRaised` / `darkSurfaceRaised` | `#F1F5F9` | `#1A2538` | Wells, disabled fills, table headers |
| `textPrimary` | `#0F172A` | `#F1F5F9` | Titles, values |
| `textSecondary` | `#475569` | `#A8B4C6` | Body, labels |
| `textMuted` | `#5B6B80` | `#8E9BB0` | Captions, meta, unselected nav |
| `borderLight` / `borderDark` | `#E2E8F0` | `#26334A` | Card and input outlines, dividers |
| `borderStrongLight` | `#CBD5E1` | `#34435C` | Outlined buttons, checkboxes |

In widgets, prefer the theme-aware helpers `AppUi.brandOf(context)` (brand
text/icons), `AppUi.brandSoftOf(context)` (tinted tiles, tonal buttons) and
`AppUi.onBrandSoftOf(context)` (content on that tint). The raw light values
(`bluePrimary` 3.5:1, `blueSoft` glare) are wrong on dark surfaces.

All text tokens are ≥ 4.5:1 on every surface of their mode — enforced by
`test/design_tokens_contrast_test.dart`.

### Semantic feedback

| Role | Solid (text/icon on white) | Tint bg | Text on tint |
|---|---|---|---|
| Success | `AppColors.uiSuccess #15803D` | `AppUi.successBg #DCFCE7` | `AppUi.successFg #166534` |
| Warning | `AppColors.uiWarning #B45309` | `AppUi.warningBg #FEF3C7` | `AppUi.warningFg #92400E` |
| Error | `AppUi.error #DC2626` | `AppUi.errorBg #FEE2E2` | `AppUi.errorFg #B91C1C` |
| Info | `AppUi.info` (brand) | `AppUi.infoBg` | `bluePrimary` |

Tint borders: `successBorder`, `warningBorder`, `errorBorder`. Readable
foregrounds on dark surfaces: `successFgDark`, `warningFgDark`, `errorFgDark`,
`infoFgDark`. `StatusToneStyle` is built from these same tokens.

### Order status (shared by every role)

Resolve with `OrderStatusStyle.resolve(status, isDark:)` or render with
`OrderStatusBadge`. Statuses are mapped, never renamed — the database values are
untouched.

| Canonical status | Accepted aliases | Color | Label |
|---|---|---|---|
| `pending` | `pending_sync` (offline) | Amber `#B45309` | Pending / Queued Offline |
| `accepted` | `confirmed` | Blue `#2563EB` | Accepted |
| `preparing` | `in_prep` | Violet `#7C3AED` | Preparing |
| `ready_for_pickup` | `ready`, `ready_for_delivery` | Teal `#0F766E` | Ready for Pickup |
| `out_for_delivery` | `assigned_to_rider`, `rider_assigned`, `delivering`, `dispatched` | Indigo `#4338CA` | Out for Delivery / Assigned to Rider |
| `delivered` | `completed` | Green `#16803D` | Delivered |
| `cancelled` | `canceled` | Red `#DC2626` | Cancelled |
| `rejected` | — | Crimson `#991B1B` | Rejected |
| anything else | — | Slate `#64748B` | Processing |

### Other statuses — `StatusTone`

Payments, accounts, stations, riders and payouts use
`StatusToneStyle.paymentTone(raw)` / `accountTone(raw)` → one of
`neutral · info · success · warning · danger · progress`, rendered with
`AppStatusPill`. Example: `paid` → success, `pending` → warning, `failed` →
danger, `refunded` → info, `suspended` → danger.

## Typography — Plus Jakarta Sans

Use `Theme.of(context).textTheme`. Weights stop at **700**; hierarchy comes
from size. Minimum on-screen size is **11 dp** (badges only); body text is
14 dp, line-height 1.5.

| Style | Size | Weight | Use |
|---|---|---|---|
| `displaySmall` | 24 | 700 | Totals, hero numbers |
| `headlineMedium` | 20 | 700 | Screen titles (large) |
| `headlineSmall` | 18 | 700 | Dialog titles |
| `titleLarge` | 16 | 700 | App bar, card titles |
| `titleMedium` | 14 | 700 | Section titles, list titles |
| `bodyLarge` | 16 | 500 | Inputs, prominent body |
| `bodyMedium` | 14 | 500 | Body (secondary color) |
| `bodySmall` | 12 | 500 | Meta, helper text |
| `labelLarge` | 15 | 700 | Buttons |
| `labelSmall` | 11 | 700 | Badges, overlines |

## Spacing — 4 pt grid

`AppUi.spacingXs 4 · Sm 8 · Md 12 · Lg 16 · Xl 24 · 2xl 32`.
Screen gutter `screenPadding 16` (phones) / `screenPaddingWide 20`.
Card padding 16. Gap between cards 12. Gap between sections 24.

## Radius

`radiusXs 4` (checkbox) · `radiusSm 6` (tooltip, small tag) ·
`radiusControl 8` (buttons, inputs, menus, snackbars) · `radiusCard 12` (cards,
tiles) · `radiusSheet 16` (bottom sheets, dialogs, large panels) ·
`radiusPill 24` (segmented pills on short controls) · `radiusFull 999` (chips,
status pills, avatars).

## Elevation

Borders separate; shadows are for overlays only.
Cards: `elevation 0` + 1 px `borderLight`. Floating overlays: `AppUi.shadowMd`.
No gradients on functional surfaces.

## Controls

| Control | Spec |
|---|---|
| Buttons (Elevated/Filled/Outlined) | 48 dp min height, radius 8, 15/600 label. Filled = brand. Outlined = neutral text + `borderStrong`. Text = brand. |
| Icon buttons | 48 × 48 dp target |
| Rider primary actions | 56 dp (`kRiderTouchTarget`) |
| Inputs | Filled `surface`, 1 px border, 2 px brand on focus, radius 8, 16/14 padding, label always present (no placeholder-only fields) |
| Chips | Pill, 1 px border, selected = `blueSoft` + dark brand text |
| Status pill | `OrderStatusBadge` / `AppStatusPill`, radius full, 12/600, icon + label (color is never the only signal) |

## Navigation

* **Phones:** `RoleBottomNavBar` — docked, full-width, hairline top border,
  12 dp labels always visible, brand indicator pill, badge for unread counts.
* **Admin desktop:** sidebar shell (`admin/lib/shell/admin_shell.dart`) with
  grouped sections and an active indicator; collapses to a drawer < 1024 dp.
* App bars: centered title, 56 dp, no elevation, same color as page.

## Breakpoints

`AppBreakpoints.compact < 600 ≤ medium < 1024 ≤ expanded`. Constrain reading
content to `AppBreakpoints.contentMaxWidth` (1200) and forms to 640.

## Motion

`motionFast 150 ms` (press, hover) · `motionBase 200 ms` (state change) ·
`motionSlow 300 ms` (sheet, page) · `motionCurve easeOutCubic`.
Use `AppUi.motion(context)` — returns `Duration.zero` when the OS asks for
reduced motion. No elastic/bounce curves on navigation.

## States

Every async surface has four states, using the shared widgets:
loading (`AppLoadingSkeleton` / `LoadingStateCard`), empty (`EmptyStateCard`),
error with a retry action (`AppErrorState`), and content. Submit buttons show a
spinner and are disabled while the request runs; success is only shown after
the backend confirms.

## Anti-patterns

* Hard-coded `Color(0x…)`, `fontSize`, `BorderRadius.circular(n)` in screens.
* Emoji as icons; mixed icon sets (use Material Symbols rounded/outlined).
* Text below 11 dp, weights above 700, Tailwind 400/500 tones as text.
* Invented data in the UI (fake ETAs, default container sizes, placeholder
  prices). Show only what the backend returns.
* Success toasts before the backend confirms.
* Hard-coded KPI deltas or "insights". Deltas come from real data
  (today vs. yesterday) or are omitted.
* Raw exception text in UI. Wrap with `FriendlyErrors.message(e)`.
* Hand-built currency strings. Use `formatPeso()`.
* Auto-advancing carousels faster than 6 s, or any that ignore reduce-motion.
