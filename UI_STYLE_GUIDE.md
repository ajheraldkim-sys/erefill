# eRefill UI Style Guide (developer quick reference)

The full design system — palette, type scale, status mapping, and the
reasoning behind each choice — lives in
[`design-system/erefill/MASTER.md`](design-system/erefill/MASTER.md).
This page is the "how do I use it in code" companion.

## Golden rules

1. **No raw values in screens.** Use `AppUi.*` / `AppColors.*` tokens and
   `Theme.of(context).textTheme`. No `Color(0x…)`, no `BorderRadius.circular(10)`,
   no `fontSize: 9`.
2. **Theme-aware colors.** Prefer `AppUi.textPrimaryOf(context)`,
   `AppUi.surfaceOf(context)`, `AppUi.borderOf(context)` over static light values.
3. **Status = shared widget.** Orders: `OrderStatusBadge(status: …)`.
   Payments / accounts / stations: `AppStatusPill.payment(…)` /
   `AppStatusPill.account(…)`. Never invent a local color map.
4. **Money = `formatPeso(amount)`** — always `₱1,234.50`.
5. **Show only real data.** No placeholder ETAs, ratings, or fees. If the
   backend hasn't answered, say so ("Calculated at checkout").

## Tokens at a glance

```dart
import 'package:erefill/core/constants.dart';      // AppUi
import 'package:erefill/core/theme/app_colors.dart'; // AppColors, StatusTone

AppUi.bluePrimary          // brand / primary action
AppUi.textPrimary / textSecondary / textMuted
AppUi.pageBg / surface / lightSurfaceRaised / borderLight
AppColors.uiSuccess / uiWarning / uiError       // text & icons on white
AppUi.successBg / warningBg / errorBg           // tinted surfaces

AppUi.spacingXs 4 · Sm 8 · Md 12 · Lg 16 · Xl 24 · 2xl 32
AppUi.radiusControl 8 · radiusCard 12 · radiusSheet 16 · radiusFull 999
AppUi.buttonHeight 48 · kMinTouchTarget 48 · kRiderTouchTarget 56
AppUi.motion(context)      // 200 ms, or zero when reduce-motion is on
```

## Components (`lib/core/widgets/app_ui_kit.dart`)

| Need | Use |
|---|---|
| Bordered card | `AppCard(child: …, onTap: …)` |
| Quantity stepper (48 dp) | `QuantitySelector(value:, onChanged:, onRemove:)` |
| Price summary | `PriceBreakdown(lines: [PriceLine(…)], total:)` |
| Non-order status | `AppStatusPill(label:, tone: StatusTone.success)` |
| Failure with retry | `AppErrorState(message:, onRetry:)` |
| Confirm / destructive confirm | `await showAppConfirmDialog(context, title:, message:, destructive: true)` |
| Cap content width on tablets | `ResponsiveCenter(maxWidth: AppBreakpoints.formMaxWidth, child: …)` |
| Breakpoints | `AppBreakpoints.compact` (600) · `expanded` (1024) |

Other shared widgets: `OrderStatusBadge`, `AvailabilityBadge`,
`RefillOrderStatusTimeline` (`refill_status_widgets.dart`), `EmptyStateCard` /
`LoadingStateCard` (`brand/axo_states.dart`), `AppLoadingSkeleton`
(`skeleton.dart`), `RoleBottomNavBar`, `AppFormField`
(`app_form_fields.dart`). Admin console primitives live in
`admin/lib/widgets/admin_ui.dart` and read the same tokens.

## Buttons

Use the Material buttons — the theme already sets height 48, radius 8, and
the label style.

```dart
FilledButton(onPressed: …, child: const Text('Place order'))   // primary
OutlinedButton(onPressed: …, child: const Text('Cancel'))      // secondary
TextButton(onPressed: …, child: const Text('View all'))        // tertiary
```

While a request runs: disable the button and show a spinner inside it; show
success only after the backend confirms.

## Copy

Sentence case for buttons, titles and labels ("Clear cart", "Order summary").
Status labels come from `OrderStatusColors.getLabel` so every role reads the
same words.

## Verifying changes

```bash
flutter analyze && flutter test            # app
cd admin && flutter analyze && flutter test # admin console
```

`test/design_tokens_contrast_test.dart` fails if a token edit drops any text
pair below WCAG AA; `test/ui_kit_responsive_test.dart` renders the cart and
shared components at 320–1280 px with 130 % text.
