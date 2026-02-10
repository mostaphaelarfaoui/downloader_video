
import 'package:flutter_test/flutter_test.dart';

import 'package:video_downloader_app/main.dart';

void main() {
  testWidgets('App renders MainScreen with bottom navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify the bottom navigation items exist.
    expect(find.text('Downloader'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });
}
