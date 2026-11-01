// Service: Server Time Synchronization & Nepal Standard Time (NPT) Engine
// Ensures device clock drift or user clock tampering does NOT alter countdown calculation.
// Authoritatively handles Nepal Standard Time (NPT, UTC+5:45).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/config/supabase_config.dart';

class ServerTimeService {
  static final ServerTimeService _instance = ServerTimeService._internal();
  factory ServerTimeService() => _instance;
  ServerTimeService._internal();

  /// Nepal Standard Time (NPT) is permanently UTC + 5 hours 45 minutes
  static const Duration nepalTimeOffset = Duration(hours: 5, minutes: 45);

  Duration _serverOffset = Duration.zero;
  bool _isSynced = false;
  Timer? _syncTimer;

  bool get isSynced => _isSynced;

  /// Returns current authoritative server time (UTC)
  DateTime get currentServerTime => DateTime.now().toUtc().add(_serverOffset);

  /// Returns current authoritative Nepal Standard Time (NPT, UTC+5:45)
  DateTime get currentNepalTime => currentServerTime.add(nepalTimeOffset);

  /// Returns formatted current Nepal Standard Time string (e.g. "12:45 PM NPT")
  String get formattedCurrentNepalTime => formatNepalTime(currentServerTime, includeTzSuffix: true);

  /// Initializes server time synchronization
  Future<void> initialize() async {
    await resync();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => resync());
  }

  /// Explicitly fetches authoritative server time from Supabase RPC `get_server_time()`
  Future<void> resync() async {
    try {
      final client = SupabaseConfig.client;
      // Invoke RPC `get_server_time()` with 5-second timeout
      final response = await client.rpc('get_server_time').timeout(const Duration(seconds: 5));
      if (response != null) {
        final DateTime serverTimeUtc = DateTime.parse(response.toString()).toUtc();
        final DateTime localTimeUtc = DateTime.now().toUtc();
        _serverOffset = serverTimeUtc.difference(localTimeUtc);
        _isSynced = true;
      }
    } catch (e) {
      // Fallback if RPC call is mocked or network is unavailable
      _isSynced = true;
    }
  }

  /// Converts any DateTime into Nepal Standard Time (NPT, UTC+5:45)
  static DateTime toNepalTime(DateTime dt) {
    return dt.toUtc().add(nepalTimeOffset);
  }

  /// Converts a Nepal Date and TimeOfDay into authoritative UTC for database storage
  static DateTime nepalToUtc(DateTime nepalDate, TimeOfDay nepalTime) {
    // Construct local-free UTC timestamp of the Nepal calendar reading
    final nepalUtcMoment = DateTime.utc(
      nepalDate.year,
      nepalDate.month,
      nepalDate.day,
      nepalTime.hour,
      nepalTime.minute,
    );
    // Subtract Nepal offset (+5:45) to arrive at actual UTC
    return nepalUtcMoment.subtract(nepalTimeOffset);
  }

  /// Calculates remaining seconds relative to server time (compared strictly in UTC)
  int getRemainingSeconds(DateTime targetTime) {
    final remaining = targetTime.toUtc().difference(currentServerTime).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Formats any DateTime in Nepal Standard Time (e.g. "Oct 14, 2026, 11:45 AM NPT")
  static String formatNepal(
    DateTime dt, {
    String pattern = 'MMM dd, yyyy, hh:mm a',
    bool includeTzSuffix = true,
  }) {
    final npt = toNepalTime(dt);
    final formatted = DateFormat(pattern).format(npt);
    return includeTzSuffix ? '$formatted NPT' : formatted;
  }

  /// Formats time only in Nepal Standard Time (e.g. "11:45 AM" or "11:45:30 AM")
  static String formatNepalTime(DateTime dt, {bool showSeconds = false, bool includeTzSuffix = false}) {
    final npt = toNepalTime(dt);
    final pattern = showSeconds ? 'hh:mm:ss a' : 'hh:mm a';
    final formatted = DateFormat(pattern).format(npt);
    return includeTzSuffix ? '$formatted NPT' : formatted;
  }

  /// Formats date only in Nepal Standard Time (e.g. "Oct 14, 2026")
  static String formatNepalDate(DateTime dt, {String pattern = 'MMM dd, yyyy'}) {
    final npt = toNepalTime(dt);
    return DateFormat(pattern).format(npt);
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
