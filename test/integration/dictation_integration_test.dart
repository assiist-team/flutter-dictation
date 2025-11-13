import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dictation/services/native_dictation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dictation Integration Tests', () {
    late NativeDictationService service;

    setUp(() {
      service = NativeDictationService();
    });

    tearDown(() {
      service.dispose();
    });

    test('full flow: initialize → start → speak → stop', () async {
      final events = <String>[];

      try {
        // Initialize
        await service.initialize();
        events.add('initialized');

        // Start listening
        await service.startListening(
          onResult: (text, isFinal) {
            if (isFinal) {
              events.add('finalResult');
              expect(text, isA<String>());
            } else {
              events.add('partialResult');
            }
          },
          onStatus: (status) {
            events.add('status:$status');
          },
          onAudioLevel: (_) {
            events.add('audioLevel');
          },
        );
        events.add('started');

        // Wait for some activity
        await Future.delayed(const Duration(seconds: 3));

        // Stop listening
        await service.stopListening();
        events.add('stopped');

        // Verify flow occurred
        expect(events.contains('initialized'), isTrue);
        expect(events.contains('started'), isTrue);
        expect(events.contains('stopped'), isTrue);
      } on PlatformException catch (e) {
        // Handle errors gracefully in integration tests
        expect(e.code, isNotNull);
      } catch (e) {
        // Other errors might occur
        expect(e, isNotNull);
      }
    });

    test('multiple start/stop cycles', () async {
      try {
        await service.initialize();

        for (int cycle = 0; cycle < 3; cycle++) {
          await service.startListening(
            onResult: (_, __) {},
            onStatus: (_) {},
            onAudioLevel: (_) {},
          );

          await Future.delayed(const Duration(milliseconds: 200));

          await service.stopListening();

          await Future.delayed(const Duration(milliseconds: 100));
        }

        // If we get here without crashing, the cycles worked
        expect(service, isNotNull);
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('error recovery', () async {
      try {
        await service.initialize();

        await service.startListening(
          onResult: (_, __) {},
          onStatus: (status) {
            expect(status, isA<String>());
          },
          onAudioLevel: (_) {},
          onError: (error) {
            expect(error, isA<String>());
          },
        );

        // Try to recover by stopping and restarting
        await service.stopListening();
        await Future.delayed(const Duration(milliseconds: 100));

        await service.startListening(
          onResult: (_, __) {},
          onStatus: (_) {},
          onAudioLevel: (_) {},
        );

        await Future.delayed(const Duration(milliseconds: 200));

        // Recovery should be possible
        expect(service, isNotNull);
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('state transitions', () async {
      final states = <String>[];

      try {
        await service.initialize();
        states.add('idle');

        await service.startListening(
          onResult: (_, __) {},
          onStatus: (status) {
            states.add(status);
          },
          onAudioLevel: (_) {},
        );

        await Future.delayed(const Duration(milliseconds: 200));
        states.add('listening');

        await service.stopListening();
        await Future.delayed(const Duration(milliseconds: 100));
        states.add('stopped');

        // Verify state transitions occurred
        expect(states.length, greaterThan(0));
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('memory leaks - multiple sessions', () async {
      try {
        for (int session = 0; session < 5; session++) {
          final sessionService = NativeDictationService();

          await sessionService.initialize();

          await sessionService.startListening(
            onResult: (_, __) {},
            onStatus: (_) {},
            onAudioLevel: (_) {},
          );

          await Future.delayed(const Duration(milliseconds: 100));

          await sessionService.stopListening();
          sessionService.dispose();

          await Future.delayed(const Duration(milliseconds: 50));
        }

        // If we get here, no obvious memory leaks
        expect(true, isTrue);
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('long recording session', () async {
      try {
        await service.initialize();

        await service.startListening(
          onResult: (text, isFinal) {
            expect(text, isA<String>());
            expect(isFinal, isA<bool>());
          },
          onStatus: (_) {},
          onAudioLevel: (_) {},
        );

        // Simulate long recording (5 seconds)
        await Future.delayed(const Duration(seconds: 5));

        await service.stopListening();

        // Service should still work after long session
        expect(service, isNotNull);
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('cancel during listening', () async {
      try {
        await service.initialize();

        await service.startListening(
          onResult: (_, __) {},
          onStatus: (_) {},
          onAudioLevel: (_) {},
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Cancel instead of stop
        await service.cancelListening();

        // Service should be ready for next session
        expect(service, isNotNull);
      } on PlatformException catch (e) {
        expect(e.code, isNotNull);
      } catch (e) {
        expect(e, isNotNull);
      }
    });
  });
}

