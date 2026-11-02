import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import '/Users/deanbowen/Development/StudyBible2/lib/features/reader/presentation/tag_playback/tag_pcm_clip_edges.dart';
Future<void> main() async {
  final results = <Map<String,Object>>[];
  for (final verse in [8,9,10,11]) {
    final path='/tmp/studybible-tag-click-20261024/verse$verse';
    final bytes=await File('$path-before.wav').readAsBytes();
    final original=Uint8List.fromList(bytes);
    softenTagPcmClipEdges(bytes);
    await File('$path-after.wav').writeAsBytes(bytes);
    final b=ByteData.sublistView(bytes), old=ByteData.sublistView(original);
    for (var i=12;i+8<=bytes.length;) {
      final n=b.getUint32(i+4,Endian.little), start=i+8;
      if (ascii.decode(bytes.sublist(i,i+4))=='data') {
        if(b.getInt16(start,Endian.little)!=0 || b.getInt16(start+n-2,Endian.little)!=0) throw StateError('Nonzero edge');
        for(var j=start+240;j<start+n-240;j++) { if(bytes[j]!=original[j]) throw StateError('Interior changed'); }
        results.add({'verse':verse,'frames':n~/2,'old_first':old.getInt16(start,Endian.little),'old_last':old.getInt16(start+n-2,Endian.little),'new_first':0,'new_last':0,'interior_identical':true,'file_length_unchanged':bytes.length==original.length});
      }
      i=start+n+(n.isOdd?1:0);
    }
  }
  final json=const JsonEncoder.withIndent('  ').convert(results);
  await File('/tmp/studybible-tag-click-20261024/real-audio-check.json').writeAsString(json);
  print(json);
}
