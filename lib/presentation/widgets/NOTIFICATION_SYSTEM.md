# Notification System

A modern, flat notification system for displaying success, error, warning, and info messages throughout the app.

## Features

✨ **Two Display Modes:**
- **Dialog**: Full modal dialog for important messages
- **Toast**: Compact overlay notification that auto-dismisses

🎨 **Four Notification Types:**
- ✅ **Success** - Green with check icon
- ❌ **Error** - Red with error icon  
- ⚠️ **Warning** - Amber with warning icon
- ℹ️ **Info** - Primary color with info icon

📐 **Design:**
- Flat design with minimal border radius (8px)
- Color-coded for quick recognition
- Smooth animations
- Responsive and accessible

## Usage

### Quick Helpers

#### Success Notification (Toast)
```dart
NotificationToast.show(
  context,
  NotificationData(
    title: 'Success',
    message: 'Plan created successfully',
    type: NotificationType.success,
  ),
);
```

#### Error Dialog
```dart
await NotificationDialog.error(
  context,
  title: 'Failed to Save',
  message: 'Could not connect to server',
);
```

#### Warning Dialog
```dart
await NotificationDialog.warning(
  context,
  title: 'Warning',
  message: 'This action cannot be undone',
);
```

#### Info Dialog
```dart
await NotificationDialog.info(
  context,
  title: 'Information',
  message: 'Your session will expire in 5 minutes',
);
```

### Custom Notification

```dart
// Custom dialog
await NotificationDialog.show(
  context,
  NotificationData(
    title: 'Custom Title',
    message: 'Custom message here',
    type: NotificationType.success,
  ),
);

// Custom toast with duration
NotificationToast.show(
  context,
  NotificationData(
    title: 'Quick Message',
    message: 'This will disappear soon',
    type: NotificationType.info,
  ),
  duration: Duration(seconds: 2),
);
```

## Examples

### Form Validation Error
```dart
if (name.isEmpty) {
  await NotificationDialog.error(
    context,
    title: 'Validation Error',
    message: 'Plan name is required',
  );
  return;
}
```

### Successful Save
```dart
try {
  await savePlan(plan);
  NotificationToast.show(
    context,
    NotificationData(
      title: 'Saved',
      message: 'Plan saved successfully',
      type: NotificationType.success,
    ),
  );
} catch (e) {
  await NotificationDialog.error(
    context,
    title: 'Save Failed',
    message: e.toString(),
  );
}
```

### Warning Before Delete
```dart
await NotificationDialog.warning(
  context,
  title: 'Delete Plan?',
  message: 'This will permanently delete the plan and all associated vouchers.',
);
```

## Design Specifications

### Border Radius
- Dialog: 8px
- Toast: 8px
- Icon containers: 6px

### Colors
- Success: `#10B981` (Green 500)
- Error: `#EF4444` (Red 500)
- Warning: `#F59E0B` (Amber 500)
- Info: Primary theme color

### Animations
- Toast slide-in from top with fade
- Duration: 300ms
- Curve: `easeOutCubic`

### Auto-dismiss
- Default: 4 seconds
- Customizable via `duration` parameter

## Best Practices

1. **Use Toasts for non-critical feedback**
   - "Saved successfully"
   - "Copied to clipboard"
   - "Settings updated"

2. **Use Dialogs for important messages**
   - Errors that need attention
   - Warnings before destructive actions
   - Information that requires acknowledgment

3. **Keep messages concise**
   - Title: 2-5 words
   - Message: 1-2 sentences

4. **Choose the right type**
   - Success: Completed actions
   - Error: Failed operations
   - Warning: Potential issues
   - Info: General information
