# 🏍️ PhatPhati — Two-Wheeler Auction & Bidding Platform

**PhatPhati** is a modern, real-time digital auction and bidding platform engineered specifically for Nepal's used two-wheeler (motorcycle & scooter) ecosystem. It transforms traditional unorganized recondition sales into transparent, server-enforced, and legally verified auctions.

A Flutter and Supabase-powered auction platform for Nepal’s used motorcycles and scooters, featuring real-time bidding, vehicle inspections, anti-sniping protection, and secure booking deposits.

---

## 🌟 Key Features

- **Authoritative Nepal Standard Time (NPT UTC+5:45):** Countdowns are synchronized directly with the server via PostgreSQL RPC to prevent device clock tampering.
- **Anti-Sniping Protection:** Any bid submitted in the final 2 minutes automatically extends the round by **+2 minutes** to ensure fair bidding.
- **16-Point Vehicle Inspection:** Captures CC, fuel type (Petrol/EV), BS/AD manufacturing year, lot number, provincial plate number, tax status, and engine repair history.
- **8-Photo Legal Verification:**
  - **3 Private Legal Documents:** Bluebook front, back, and tax/ownership pages (restricted to verified Admin view).
  - **5 Public Inspection Photos:** Front, rear, right, left profiles, and an odometer mileage reading.
- **Multi-Round Automated Re-Auction Engine:** If an auction winner fails to pay the 10% booking deposit within the deadline (20–30 mins), the system automatically expires the position and spawns **Round N+1** for the remaining bidders.
- **Dynamic Bank QR & Settlement:** Generates a real-time transaction QR code containing the booking reference and exact 10% deposit amount, alongside bank transfer details and showroom collection instructions.
- **Complete Audit Trail:** Every bid, state transition, and admin action is permanently logged in `public.audit_logs`.

---

## 🏗️ System Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Flutter Client App                   │
│  • Material 3 Design System (Automotive Navy & Orange)  │
│  • Google Fonts: Inter                                 │
│  • ServerTimeService (Authoritative NPT Engine)        │
│  • Reactive Streams for Live Bids, Rounds & Deposits   │
└───────────────────────────┬────────────────────────────┘
                            │ HTTPS & Realtime WebSockets
┌───────────────────────────▼────────────────────────────┐
│                  Supabase Cloud Backend                │
│  • PostgreSQL with Row Level Security (RLS)            │
│  • 46 Server-Side Migrations & Stored Procedures (RPC) │
│  • Realtime Replication Engine (Instant live bids)     │
│  • Public Storage (Vehicles) / Private (Bluebooks/PAN) │
│  • Secure Auth: OTP Verification & Bcrypt Hashing      │
└────────────────────────────────────────────────────────┘
```

---

## 👥 User Roles

The platform supports Admin, Buyer (Reconditioner), and Seller (Dealer) accounts. Create and manage accounts in your own Supabase project; this repository does not include shared test credentials.

---

## 📁 Project Structure

```
lib/
├── config/
│   └── supabase_config.dart          # Supabase client credentials & initialization
├── data/
│   └── vehicle_data.dart             # Nepal two-wheeler brand/model datasets & banks
├── models/
│   └── auction_models.dart           # Data models (Auction, Bid, Profile, Deposit, etc.)
├── screens/
│   ├── admin/                        # Admin dashboard, listing creation & verification
│   ├── auth/                         # Unified single-page login & registration
│   ├── buyer/                        # Discovery, live bidding, won auctions, deposit details
│   ├── notifications/                # Real-time in-app notification center
│   └── seller/                       # Seller hub, vehicle listings & profile
├── services/
│   ├── app_lifecycle_service.dart    # Foreground/resume timer re-synchronization
│   ├── auction_service.dart          # Reactive streams, data queries & storage uploads
│   └── server_time_service.dart      # Nepal Standard Time (UTC+5:45) synchronization
├── theme/
│   └── app_theme.dart                # Theme, color tokens (Navy/Orange) & typography
├── utils/
│   └── nepal_phone_helper.dart       # Nepali mobile number formatting & validation
└── widgets/
    ├── countdown_timer_widget.dart   # Server-synchronized real-time countdown widget
    └── status_badge_widget.dart      # Color-coded status badges (Live, Secured, etc.)
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK:** `>=3.0.0 <4.0.0`
- **Dart SDK:** `>=3.0.0`
- **Android Studio / Xcode** (for mobile builds)

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Configure Supabase

Provide your own Supabase project URL and publishable key at build/run time. Do not commit credentials or service-role keys.

### 3. Run Locally (Desktop / Device)
```bash
# Run on connected Android / Linux / Chrome
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
```

### 4. Build for Production

#### Lightweight Split APK (Recommended for Android device testing):
```bash
flutter build apk --split-per-abi \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
# Generates optimized ~18 MB APK in build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

#### Android App Bundle (.aab for Google Play Store):
```bash
flutter build appbundle \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
```

#### Web Build:
```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
```

---

## 📄 License
Proprietary & Confidential. Built for PhatPhati Vehicle Auction Platform, Kathmandu, Nepal.
