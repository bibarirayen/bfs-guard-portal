// file: lib/config/app_globals.dart
import 'package:flutter/material.dart';

/// Shared navigator key — lets ApiService navigate without a BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// When true, LoginScreen will show a "session expired" banner on load.
bool pendingSessionExpiredMessage = false;

/// Registered in main() so ApiService can push back to LoginScreen
/// without creating a circular import (ApiService → LoginScreen).
WidgetBuilder? loginScreenBuilder;
