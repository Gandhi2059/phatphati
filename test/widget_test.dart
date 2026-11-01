// Basic Widget Test for AuctionApp

import 'package:flutter_test/flutter_test.dart';
import 'package:bid_app/main.dart';

void main() {
  testWidgets('AuctionApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AuctionApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('PHATPHATI AUCTIONS'), findsOneWidget);
  });
}
