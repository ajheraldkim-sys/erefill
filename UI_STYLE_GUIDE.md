# eRefill UI/UX Style Guide

## Overview
This document outlines the design system and best practices for the eRefill Flutter application. All screens and components should follow these guidelines for consistency and quality.

---

## Color Palette

### Primary Colors
- **Primary Blue**: `#0437F2` - Main brand color for CTAs, highlights
- **Primary Dark**: `#0329B8` - For hover/active states
- **Soft Blue**: `#E8EFFF` - Background tint, light elements

### Neutral Colors
- **White**: `#FFFFFF` - Card and surface backgrounds
- **Page Background**: `#F8FAFC` - Main app background
- **Text Primary**: `#14213D` - Primary text color
- **Text Secondary**: `#5C6784` - Secondary/muted text

### Semantic Colors
- **Success**: `#065F46` (text), `#ECFDF3` (background)
- **Warning**: `#9A3412` (text), `#FFF7ED` (background)
- **Error**: `#DC2626` (for errors, use Colors.red)
- **Border**: `#E2E8F0` - Default border color

---

## Typography

### Text Styles

#### Display Styles (Headings)
```dart
// Display Large (32px, bold)
Theme.of(context).textTheme.displayLarge

// Display Medium (28px, bold)
Theme.of(context).textTheme.displayMedium

// Display Small (24px, bold)
Theme.of(context).textTheme.displaySmall
```

#### Heading Styles
```dart
// Headline Medium (20px, semi-bold)
Theme.of(context).textTheme.headlineMedium

// Headline Small (18px, semi-bold)
Theme.of(context).textTheme.headlineSmall
```

#### Title Styles
```dart
// Title Large (16px, semi-bold)
Theme.of(context).textTheme.titleLarge

// Title Medium (14px, semi-bold)
Theme.of(context).textTheme.titleMedium

// Title Small (12px, semi-bold)
Theme.of(context).textTheme.titleSmall
```

#### Body Styles
```dart
// Body Large (16px, regular)
Theme.of(context).textTheme.bodyLarge

// Body Medium (14px, regular)
Theme.of(context).textTheme.bodyMedium

// Body Small (12px, regular)
Theme.of(context).textTheme.bodySmall
```

#### Label Styles
```dart
// Label Large (14px, semi-bold)
Theme.of(context).textTheme.labelLarge

// Label Medium (12px, semi-bold)
Theme.of(context).textTheme.labelMedium

// Label Small (11px, semi-bold)
Theme.of(context).textTheme.labelSmall
```

---

## Spacing System

Use `AppSpacing` constants for all spacing to maintain consistency:

```dart
import 'package:erefill/core/theme/app_spacing.dart';

// XS: 4px
// SM: 8px
// MD: 12px
// LG: 16px
// XL: 20px
// XXL: 24px
// XXXL: 32px
```

### Examples
```dart
// Padding
Padding(padding: AppSpacing.paddingMd, child: ...),

// Sized gaps
SizedBox(height: AppSpacing.md),
AppSpacing.gapVerticalLg,

// Container padding
Container(
  padding: AppSpacing.paddingLg,
  child: ...,
)
```

---

## Border Radius

Use consistent border radius throughout the app:

- **XS** (4px): Small buttons, chips
- **SM** (8px): Input fields, small containers
- **MD** (12px): Cards, dialogs, standard containers
- **LG** (14px): Default card radius - *Most Common*
- **XL** (16px): Large prominence elements
- **Circle** (32px): Circular avatars, FABs

```dart
BorderRadius.circular(AppUi.radius) // LG (14px) - default

// Or use AppSpacing for custom:
BorderRadius.circular(AppSpacing.radiusXl)
```

---

## Component Usage

### Buttons

#### Primary Button
For main actions (submit, continue, etc.)
```dart
PrimaryButton(
  label: 'Submit',
  onPressed: () { },
  icon: Icons.check,
  isLoading: false,
)
```

#### Secondary Button
For alternative actions
```dart
SecondaryButton(
  label: 'Cancel',
  onPressed: () { },
  icon: Icons.close,
)
```

#### Text Button
For low-priority actions
```dart
TextLinkButton(
  label: 'Forgot Password?',
  onPressed: () { },
)
```

### Cards

#### Custom Card (Elevated)
```dart
CustomCard(
  margin: AppSpacing.paddingMd,
  padding: AppSpacing.paddingLg,
  onTap: onTapAction,
  child: ...,
)
```

#### Custom Card (Flat - No Shadow)
```dart
CustomCard(
  elevated: false,
  child: ...,
)
```

### Sections & Headers

#### Section Header with Optional View All
```dart
SectionHeader(
  title: 'Nearby Stations',
  subtitle: 'Available for delivery',
  onViewAll: () { },
)
```

### Status & Info Cards

#### Info Card
```dart
InfoCard(
  icon: Icons.info,
  title: 'Station Status',
  description: 'Currently open and accepting orders',
  iconColor: AppUi.bluePrimary,
)
```

#### Badge (for status labels)
```dart
AppBadge(
  label: 'Open',
  backgroundColor: AppUi.successBg,
  textColor: AppUi.successFg,
  icon: Icons.check_circle,
)
```

### Empty & Loading States

#### Empty State
```dart
EmptyState(
  icon: Icons.shopping_bag_outlined,
  title: 'No Orders Yet',
  message: 'You haven\'t placed any orders',
  actionLabel: 'Browse Stations',
  onRetry: navigateToStations,
)
```

#### Loading State
```dart
LoadingState(
  message: 'Loading stations...',
)
```

---

## Layout Patterns

### Consistent Screen Padding
```dart
Scaffold(
  appBar: AppBar(...),
  body: SingleChildScrollView(
    padding: AppSpacing.paddingLg,
    child: ...,
  ),
)
```

### Safe Area
Always use SafeArea for screens with custom bottom bars:
```dart
bottomNavigationBar: SafeArea(
  top: false,
  child: ...,
)
```

### Responsive Grid
For water refill option grids:
```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    childAspectRatio: 0.72,
    crossAxisSpacing: AppSpacing.md,
    mainAxisSpacing: AppSpacing.md,
  ),
  itemBuilder: (context, index) => ...,
)
```

---

## Elevation & Shadows

### Card Elevation: 1.5
```dart
decoration: AppUi.cardDecoration
```

### Floating Elements
- AppBar: Elevation 1
- Bottom sheets: Elevation 4
- Floating Action Button: Elevation 4

---

## Input Fields

### Text Input Best Practice
```dart
TextFormField(
  decoration: AppUi.fieldDecoration(
    'Hint text here',
    prefixIcon: Icon(Icons.search),
  ),
  validator: (value) {
    if (value?.isEmpty ?? true) return 'Required';
    return null;
  },
)
```

---

## AppBar Styling

### Consistent AppBar
```dart
AppBar(
  title: Text('Screen Title'),
  elevation: 1,
  // Theme automatically applies styling from AppTheme
)
```

---

## Snackbars & Dialogs

### Success Snackbar
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Action successful'),
    duration: Duration(seconds: 2),
  ),
)
```

### Error Snackbar
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Error occurred'),
    backgroundColor: Colors.red,
  ),
)
```

---

## Best Practices

### 1. Always Use Theme Text Styles
❌ Avoid:
```dart
Text('Title', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
```

✅ Use:
```dart
Text('Title', style: Theme.of(context).textTheme.headlineSmall)
```

### 2. Use AppSpacing Constants
❌ Avoid:
```dart
SizedBox(height: 16)
```

✅ Use:
```dart
AppSpacing.gapVerticalLg
// or
SizedBox(height: AppSpacing.lg)
```

### 3. Use Reusable Widgets
Place common UI components in `lib/widgets/app_widgets.dart` and reuse across screens.

### 4. Consistent Navigation
- Use Material transitions
- Maintain consistent AppBar styling
- Always provide back buttons when appropriate

### 5. Forms & Validation
- Always include form validation
- Use consistent error messaging
- Provide helpful error descriptions

### 6. Loading & Error States
- Always show loading indicators for async operations
- Implement error states with actionable retry buttons
- Show empty states when no data is available

### 7. Mobile-First Design
- Test on small screens (iPhone SE), medium (iPhone 12), and large (iPhone 14 Pro)
- Ensure touch targets are at least 44x44 points
- Provide adequate spacing for thumb-friendly interaction

---

## Color Usage Quick Reference

| Usage | Color | Code |
|-------|-------|------|
| Primary CTA | Blue Primary | #0437F2 |
| Active/Hover | Blue Dark | #0329B8 |
| Backgrounds | Page BG | #F8FAFC |
| Cards | White | #FFFFFF |
| Primary Text | Text Primary | #14213D |
| Secondary Text | Text Secondary | #5C6784 |
| Dividers/Borders | Border | #E2E8F0 |
| Success badge | Success FG | #065F46 |
| Success background | Success BG | #ECFDF3 |

---

## Migration Checklist for Existing Screens

When updating existing screens:

- [ ] Update AppBar (remove backgroundColor: Colors.white)
- [ ] Replace hardcoded colors with AppUi constants
- [ ] Replace hardcoded text styles with Theme.of(context).textTheme.*
- [ ] Replace padding values with AppSpacing constants
- [ ] Update Card widgets to use CustomCard
- [ ] Update buttons to use PrimaryButton/SecondaryButton
- [ ] Convert empty states to use EmptyState widget
- [ ] Convert loading states to use LoadingState widget
- [ ] Add proper elevation and shadows
- [ ] Ensure consistent border radius usage

---

## Definition of Terms

**Agile Model.** Refers to an iterative development approach where the system is designed, developed, tested, and improved in short cycles based on feedback.

**Application.** Refers to the eRefill mobile system used for managing water refilling orders, deliveries, inventory, and transactions.

**Application Programming Interface (API).** Refers to a set of rules that allows the eRefill application to communicate with other services, such as the database, payment provider, or map service.

**Authentication.** Refers to the process of verifying a user's identity before allowing access to the eRefill system.

**Authorization.** Refers to the process of checking what a verified user is allowed to access or do in the system based on their role.

**Backend.** Refers to the part of the system that works behind the scenes to store data, process orders, manage accounts, and handle system rules.

**Cache.** Refers to temporary storage that helps the application load information faster or continue showing recent data when the connection is slow.

**Checkout.** Refers to the process where a customer reviews an order, confirms delivery details, selects a payment method, and submits the order.

**Cloud Database.** Refers to an online database that stores system data on internet-based servers instead of only on one local computer.

**Customer.** Refers to a user who places water refill orders, selects a station, provides delivery details, and monitors order status.

**Customer Balance.** Refers to the recorded amount that a customer still needs to pay for water refill transactions.

**Dashboard.** Refers to the interface used by station owners to view summaries of orders, inventory, deliveries, payments, and sales.

**Database.** Refers to the organized storage of eRefill data, including accounts, orders, payments, inventory records, and delivery details.

**Delivery Management.** Refers to the process of assigning, monitoring, and updating delivery tasks through the eRefill system.

**Delivery Rider.** Refers to a user responsible for receiving assigned deliveries, viewing customer delivery details, and updating delivery status.

**eRefill.** Refers to the proposed smart order and inventory management system for water refilling stations.

**Empty Gallon Tracking.** Refers to the process of monitoring returned and unreturned water containers to prevent losses and maintain accurate records.

**Frontend.** Refers to the visible part of the application that users interact with, such as screens, buttons, forms, menus, and status displays.

**Global Positioning System (GPS).** Refers to a location technology used to help identify delivery locations and support rider tracking.

**Inventory Management.** Refers to the process of monitoring and recording available water products, gallons, containers, and related supplies.

**ISO/IEC 25010.** Refers to the software quality model used to evaluate the system in terms of functionality, reliability, usability, performance, security, maintainability, and portability.

**Local Storage.** Refers to data saved on a user's device so the application can keep selected information available even when the internet connection is limited.

**Mobile Application.** Refers to software designed to run on mobile devices such as smartphones and tablets.

**Notification.** Refers to an alert or message sent by the system to inform users about order updates, delivery changes, payment status, or other important activities.

**Offline Queue.** Refers to a temporary list of actions saved by the application when the internet connection is unavailable, which are sent once the connection is restored.

**Order Management.** Refers to the process of creating, receiving, updating, tracking, and completing customer water refill orders.

**Order Status.** Refers to the current progress of a customer's order, such as pending, preparing, out for delivery, delivered, or completed.

**Payment Gateway.** Refers to an online service that helps process digital payments securely between the customer, the system, and the payment provider.

**Payment Record.** Refers to the stored details of customer payments, including amount, payment method, date, and related order information.

**Profile.** Refers to the stored information about a user, such as name, contact details, address, role, and account settings.

**Real-Time Tracking.** Refers to the feature that allows users to monitor order or delivery updates as they occur.

**Role-Based Access.** Refers to a security method where the system shows different features depending on whether the user is a customer, rider, station owner, or administrator.

**Security Policy.** Refers to system rules that protect data by controlling who can view, add, change, or delete specific records.

**Server.** Refers to a computer or online service that receives requests from the application, processes them, and sends back the needed information.

**Station Owner.** Refers to a user who manages a water refilling station, including orders, inventory, riders, empty gallons, payments, and reports.

**Supabase.** Refers to the cloud platform used by the system to provide database, authentication, real-time updates, and backend services.

**Sync.** Refers to the process of making sure data in the mobile application and the online database are updated and consistent with each other.

**Transaction.** Refers to a recorded system activity involving an order, payment, delivery, inventory change, or customer balance update.

**User Interface (UI).** Refers to the visual layout of the application, including screens, buttons, text fields, icons, and menus.

**User Experience (UX).** Refers to how easy, clear, and convenient the application feels for users while completing tasks.

**User Role.** Refers to the assigned classification of a system user, such as customer, rider, or station owner, which determines access and responsibilities.

**Water Refilling Station.** Refers to a business establishment that provides purified, mineral, or alkaline water services and manages orders through the eRefill system.

**Webhook.** Refers to an automatic message sent by an external service, such as a payment provider, to notify the eRefill system when an event has occurred.
