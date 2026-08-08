import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:meal_of_record/services/nas_backup_service.dart';
import 'package:meal_of_record/services/background_backup_worker.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([NasBackupService, BackupConfigService])
import 'try_auto_backup_test.mocks.dart';

void main() {
  late MockNasBackupService mockNas;
  late MockBackupConfigService mockConfig;

  setUp(() {
    mockNas = MockNasBackupService();
    mockConfig = MockBackupConfigService();
  });

  group('tryAutoBackup (NAS)', () {
    test('skips when auto-backup is disabled', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => false);

      final result = await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
      );

      expect(result, isFalse);
      verifyNever(mockConfig.isNasConfigured());
    });

    test('skips when last backup was less than 24h ago', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.getLastBackupTime()).thenAnswer(
        (_) async => DateTime.now().subtract(const Duration(hours: 12)),
      );

      final result = await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
      );

      expect(result, isFalse);
      verifyNever(mockConfig.isNasConfigured());
    });

    test('skips when NAS is not configured', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.getLastBackupTime()).thenAnswer((_) async => null);
      when(mockConfig.isNasConfigured()).thenAnswer((_) async => false);

      final result = await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
      );

      expect(result, isFalse);
      verifyNever(
        mockNas.uploadBackup(any, retentionCount: anyNamed('retentionCount')),
      );
    });

    test('force=true skips cooldown check', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.isNasConfigured()).thenAnswer((_) async => false);

      await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
        force: true,
      );

      verifyNever(mockConfig.getLastBackupTime());
      // Still checks configuration
      verify(mockConfig.isNasConfigured()).called(1);
    });

    test('proceeds when last backup was more than 24h ago', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.getLastBackupTime()).thenAnswer(
        (_) async => DateTime.now().subtract(const Duration(hours: 25)),
      );
      // Will fail at NAS not configured, but we verify it gets past the cooldown
      when(mockConfig.isNasConfigured()).thenAnswer((_) async => false);

      await tryAutoBackup(configService: mockConfig, nasService: mockNas);

      verify(mockConfig.isNasConfigured()).called(1);
    });

    test('proceeds when no previous backup exists', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.getLastBackupTime()).thenAnswer((_) async => null);
      when(mockConfig.isNasConfigured()).thenAnswer((_) async => false);

      await tryAutoBackup(configService: mockConfig, nasService: mockNas);

      verify(mockConfig.isNasConfigured()).called(1);
    });

    test('returns false and does not throw on exceptions', () async {
      when(
        mockConfig.isAutoBackupEnabled(),
      ).thenThrow(Exception('prefs error'));

      final result = await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
      );

      expect(result, isFalse);
    });

    test('records failure on exception', () async {
      when(mockConfig.isAutoBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.getLastBackupTime()).thenAnswer((_) async => null);
      when(mockConfig.isNasConfigured()).thenThrow(Exception('test error'));
      when(mockConfig.recordBackupFailure()).thenAnswer((_) async {});

      final result = await tryAutoBackup(
        configService: mockConfig,
        nasService: mockNas,
      );

      expect(result, isFalse);
      verify(mockConfig.recordBackupFailure()).called(1);
    });
  });

  group('tryAutoLocalBackup', () {
    test('skips when local backup is disabled', () async {
      when(mockConfig.isLocalBackupEnabled()).thenAnswer((_) async => false);

      final result = await tryAutoLocalBackup(configService: mockConfig);

      expect(result, isFalse);
      verifyNever(mockConfig.isLocalBackupConfigured());
    });

    test('skips when no backup path is configured', () async {
      when(mockConfig.isLocalBackupEnabled()).thenAnswer((_) async => true);
      when(mockConfig.isLocalBackupConfigured()).thenAnswer((_) async => false);

      final result = await tryAutoLocalBackup(configService: mockConfig);

      expect(result, isFalse);
    });
  });
}
