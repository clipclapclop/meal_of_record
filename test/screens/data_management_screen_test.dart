import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/screens/data_management_screen.dart';
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:meal_of_record/services/nas_backup_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([NasBackupService, BackupConfigService])
import 'data_management_screen_test.mocks.dart';

void main() {
  late MockNasBackupService mockNasService;
  late MockBackupConfigService mockConfigService;

  setUp(() {
    mockNasService = MockNasBackupService();
    mockConfigService = MockBackupConfigService();

    // Default stubs
    when(
      mockConfigService.isAutoBackupEnabled(),
    ).thenAnswer((_) async => false);
    when(mockConfigService.getRetentionCount()).thenAnswer((_) async => 7);
    when(mockConfigService.getLastBackupTime()).thenAnswer((_) async => null);
    when(mockConfigService.isNasConfigured()).thenAnswer((_) async => false);
    when(
      mockConfigService.isLocalBackupEnabled(),
    ).thenAnswer((_) async => false);
    when(mockConfigService.getLocalBackupPath()).thenAnswer((_) async => null);
    when(
      mockConfigService.getLocalBackupLastTime(),
    ).thenAnswer((_) async => null);
    when(
      mockConfigService.getLocalBackupScheduledTime(),
    ).thenAnswer((_) async => null);
  });

  Widget createSubject() {
    return MaterialApp(
      home: DataManagementScreen(
        nasBackupService: mockNasService,
        backupConfigService: mockConfigService,
      ),
    );
  }

  group('DataManagementScreen NAS Backup', () {
    testWidgets('shows Configure NAS button when not configured', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('NAS Backup'), findsOneWidget);
      expect(find.text('Configure NAS'), findsOneWidget);
    });

    testWidgets('uses the configured active switch thumb colors', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final activeThumbColors = tester
          .widgetList<Switch>(find.byType(Switch))
          .map((widget) => widget.activeThumbColor);
      expect(activeThumbColors, containsAll([Colors.teal, Colors.orange]));
    });

    testWidgets('shows NAS address when configured', (tester) async {
      when(mockConfigService.isNasConfigured()).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasHost(),
      ).thenAnswer((_) async => '192.168.1.100');
      when(mockConfigService.getNasPort()).thenAnswer((_) async => 5006);
      when(
        mockConfigService.getNasPath(),
      ).thenAnswer((_) async => '/backups/meal_of_record');
      when(mockConfigService.getNasUseHttps()).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasAllowSelfSigned(),
      ).thenAnswer((_) async => false);
      when(
        mockConfigService.getNasCredentials(),
      ).thenAnswer((_) async => ('user', 'pass'));

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(
        find.text('192.168.1.100:5006/backups/meal_of_record'),
        findsOneWidget,
      );
      expect(find.text('HTTPS'), findsOneWidget);
      expect(find.text('Edit Settings'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('hides Backup to NAS card when not configured', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Backup to NAS'), findsNothing);
      expect(find.text('Restore from NAS'), findsNothing);
    });

    testWidgets('shows Backup to NAS cards when configured', (tester) async {
      when(mockConfigService.isNasConfigured()).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasHost(),
      ).thenAnswer((_) async => '192.168.1.100');
      when(mockConfigService.getNasPort()).thenAnswer((_) async => null);
      when(
        mockConfigService.getNasPath(),
      ).thenAnswer((_) async => '/backups/meal_of_record');
      when(mockConfigService.getNasUseHttps()).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasAllowSelfSigned(),
      ).thenAnswer((_) async => false);
      when(
        mockConfigService.getNasCredentials(),
      ).thenAnswer((_) async => ('user', 'pass'));

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Scroll down so the NAS action cards are visible in the viewport
      await tester.scrollUntilVisible(find.text('Backup to NAS'), 200);
      await tester.pumpAndSettle();

      expect(find.text('Backup to NAS'), findsOneWidget);
      expect(find.text('Restore from NAS'), findsOneWidget);
    });

    testWidgets('shows self-signed certificate note', (tester) async {
      when(mockConfigService.isNasConfigured()).thenAnswer((_) async => true);
      when(mockConfigService.getNasHost()).thenAnswer((_) async => 'nas.local');
      when(mockConfigService.getNasPort()).thenAnswer((_) async => null);
      when(mockConfigService.getNasPath()).thenAnswer((_) async => '/backups');
      when(mockConfigService.getNasUseHttps()).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasAllowSelfSigned(),
      ).thenAnswer((_) async => true);
      when(
        mockConfigService.getNasCredentials(),
      ).thenAnswer((_) async => ('user', 'pass'));

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('HTTPS (self-signed certificate)'), findsOneWidget);
    });
  });
}
