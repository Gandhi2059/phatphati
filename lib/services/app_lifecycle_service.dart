// Service: App Lifecycle Observer (App Background / Resume Handler)
// Re-synchronizes server time and forces fresh state fetch whenever the app returns from background.

import 'package:flutter/widgets.dart';
import 'package:bid_app/services/server_time_service.dart';

typedef OnAppResumedCallback = Future<void> Function();

class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  final List<OnAppResumedCallback> _resumeListeners = [];
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
  }

  void registerResumeCallback(OnAppResumedCallback callback) {
    _resumeListeners.add(callback);
  }

  void removeResumeCallback(OnAppResumedCallback callback) {
    _resumeListeners.remove(callback);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 1. Immediately re-synchronize server time
      ServerTimeService().resync();

      // 2. Notify all active listeners to refresh auction state and deadlines
      for (final listener in List.of(_resumeListeners)) {
        listener();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeListeners.clear();
    _isInitialized = false;
  }
}
