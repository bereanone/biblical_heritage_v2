import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/narration_lead.dart';

void main() {
  group('ClipLead', () {
    late DateTime clock;
    late double rate;
    late ClipLead lead;

    setUp(() {
      clock = DateTime.fromMillisecondsSinceEpoch(0);
      rate = 1;
      lead = ClipLead(playbackRate: () => rate, now: () => clock);
    });

    test('is empty before anything is synthesized', () {
      expect(lead.duration, Duration.zero);
      expect(lead.describe(), '0 clips 0.0s');
    });

    test('counts ready clips and the unplayed part of the current one', () {
      lead.ready('a', 8);
      lead.ready('b', 6);
      lead.ready('c', 7);
      lead.started('a');
      expect(lead.duration, const Duration(seconds: 21)); // 8 + 6 + 7
      clock = clock.add(const Duration(seconds: 3));
      expect(lead.duration, const Duration(seconds: 18)); // 5 + 6 + 7
      expect(lead.readyClips, 2);
    });

    test('a clip that has finished playing no longer counts', () {
      lead.ready('a', 4);
      lead.started('a');
      clock = clock.add(const Duration(seconds: 10));
      expect(lead.duration, Duration.zero);
      lead.stopped();
      expect(lead.duration, Duration.zero);
    });

    test('faster playback shortens the lead', () {
      rate = 1.25;
      lead.ready('a', 10);
      expect(lead.duration, const Duration(seconds: 8));
    });

    test('forgotten clips stop counting', () {
      lead.ready('a', 10);
      lead.forget('a');
      expect(lead.duration, Duration.zero);
    });
  });

  group('NarrationLeadRegistry', () {
    test('reports the smallest lead among playing narrators', () {
      final registry = NarrationLeadRegistry();
      registry.register(() => const Duration(seconds: 40));
      registry.register(() => const Duration(seconds: 12));
      registry.register(() => null);
      expect(registry.lead(), const Duration(seconds: 12));
    });

    test('is null when nobody is listening, and after unregistering', () {
      final registry = NarrationLeadRegistry();
      expect(registry.lead(), isNull);
      final remove = registry.register(() => const Duration(seconds: 5));
      expect(registry.lead(), const Duration(seconds: 5));
      remove();
      expect(registry.lead(), isNull);
    });
  });
}
