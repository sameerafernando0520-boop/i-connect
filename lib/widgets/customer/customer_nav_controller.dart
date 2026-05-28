// lib/widgets/customer/customer_nav_controller.dart
//
// Shared static controller for the customer shell.
// Kept in a separate file so tab pages can import it without
// creating circular dependencies on each other or on the shell.

import 'package:flutter/foundation.dart';

class CustomerNavController {
  CustomerNavController._();

  /// The currently selected tab index (0–4).
  static final tabIndex = ValueNotifier<int>(0);

  /// Number of open tickets — drives the Support FAB badge.
  static final openTickets = ValueNotifier<int>(0);

  /// Switch to a tab by index.
  static void switchTab(int index) => tabIndex.value = index;

  /// Update the open-tickets badge count.
  static void setOpenTickets(int count) => openTickets.value = count;
}
