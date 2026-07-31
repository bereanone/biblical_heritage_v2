import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run tool/elibrary_profile_probe.dart <ws-uri> <chapter>',
    );
    exitCode = 64;
    return;
  }
  final service = await vmServiceConnectUri(arguments[0]);
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates!.firstWhere(
      (value) => value.isSystemIsolate != true,
    );
    final isolateId = isolate.id!;
    final memory = await service.getMemoryUsage(isolateId);
    final allocations = await service.getAllocationProfile(isolateId);
    final counts = <String, int>{
      'Element': 0,
      'RenderObject': 0,
      'Layer': 0,
      'Paragraph': 0,
      'GestureRecognizer': 0,
      'AnimationController': 0,
      'ScrollPosition': 0,
    };
    for (final member in allocations.members ?? const <ClassHeapStats>[]) {
      final name = member.classRef?.name ?? '';
      final instances = member.instancesCurrent ?? 0;
      for (final entry in counts.entries) {
        if (name.contains(entry.key)) {
          counts[entry.key] = counts[entry.key]! + instances;
        }
      }
    }
    final timeline = await service.getVMTimeline();
    final frames =
        timeline.traceEvents
            ?.where(
              (event) =>
                  event.json?['name'] == 'Frame' && event.json?['dur'] is num,
            )
            .toList(growable: false) ??
        const <TimelineEvent>[];
    final recentFrames = frames.length > 120
        ? frames.sublist(frames.length - 120)
        : frames;
    final frameMicros =
        recentFrames
            .map((event) => (event.json!['dur'] as num).toInt())
            .toList()
          ..sort();
    final p90 = frameMicros.isEmpty
        ? 0
        : frameMicros[(frameMicros.length * .9).floor().clamp(
            0,
            frameMicros.length - 1,
          )];
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'chapter': int.parse(arguments[1]),
        'heapBytes': memory.heapUsage,
        'externalBytes': memory.externalUsage,
        'frameSamples': frameMicros.length,
        'frameP90Micros': p90,
        ...counts,
      }),
    );
  } finally {
    await service.dispose();
  }
}
