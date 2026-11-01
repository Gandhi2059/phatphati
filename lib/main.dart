// Main Entrypoint: Auction & Bidding Application
// Authoritative server-synced timers, multi-round auction state engine, and realtime notifications.

import 'package:flutter/material.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/services/app_lifecycle_service.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/screens/auth/login_screen.dart';
import 'package:bid_app/screens/admin/admin_dashboard_screen.dart';
import 'package:bid_app/screens/buyer/buyer_home_screen.dart';
import 'package:bid_app/screens/seller/seller_dashboard_screen.dart';

import 'package:bid_app/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Client Config
  await SupabaseConfig.initialize();

  // Initialize Server Time Synchronization Service
  await ServerTimeService().initialize();

  // Initialize Global App Lifecycle Observer for Foreground/Resume Re-sync
  AppLifecycleService().initialize();

  runApp(const AuctionApp());
}

class AuctionApp extends StatelessWidget {
  const AuctionApp({super.key});

  Future<Widget> _getInitialScreen() async {
    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null) {
        return const LoginScreen();
      }

      final profile = await AuctionService().fetchUserProfile(session.user.id);
      if (profile == null) {
        await SupabaseConfig.client.auth.signOut();
        return const LoginScreen();
      }

      AuctionService().setCurrentProfile(profile);

      if (profile.isAdmin) {
        return const AdminDashboardScreen();
      } else if (profile.isSeller || profile.isDealer) {
        return const SellerDashboardScreen();
      } else if (profile.isBuyer || profile.isReconditioner) {
        return const BuyerHomeScreen();
      }
      return const LoginScreen();
    } catch (_) {
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhatPhati - Bike & Scooter Bidding',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }
}
