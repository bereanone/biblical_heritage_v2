import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NoteImageClipboard {
  static const _channel=MethodChannel('studybible/rich_clipboard');
  static Future<void> copy(Uint8List bytes,String mimeType) async {
    if(bytes.isEmpty) throw ArgumentError('Empty image');
    await _channel.invokeMethod<void>('writeImage',{'bytes':bytes,'mimeType':mimeType});
  }
  static Future<Uint8List?> read() async {
    try { return await _channel.invokeMethod<Uint8List>('readImage'); }
    on MissingPluginException { return null; }
    on PlatformException { return null; }
  }
}

class NoteImageThumbnail extends StatelessWidget {
  const NoteImageThumbnail({super.key,required this.bytes,required this.onCopy,required this.onRemove,this.enabled=true});
  final Uint8List bytes;
  final VoidCallback onCopy,onRemove;
  final bool enabled;
  Future<void> _menu(BuildContext context,Offset position) async {
    if(!enabled)return;
    final overlay=Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected=await showMenu<String>(context:context,position:RelativeRect.fromRect(position & Size.zero,Offset.zero & overlay.size),items:const[
      PopupMenuItem(value:'copy',child:Text('Copy Image')),
      PopupMenuItem(value:'remove',child:Text('Remove image'))]);
    if(selected=='copy')onCopy();else if(selected=='remove')onRemove();
  }
  @override
  Widget build(BuildContext context)=>GestureDetector(
    onLongPressStart:(d)=>_menu(context,d.globalPosition),
    onSecondaryTapDown:(d)=>_menu(context,d.globalPosition),
    child:SizedBox(width:112,height:84,child:Stack(children:[
      Positioned.fill(child:ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.memory(bytes,fit:BoxFit.cover))),
      Positioned(top:2,right:2,child:Material(color:Theme.of(context).colorScheme.surface,shape:const CircleBorder(),child:IconButton(tooltip:'Remove image',onPressed:enabled?onRemove:null,icon:const Icon(Icons.close,size:16),constraints:const BoxConstraints.tightFor(width:28,height:28),padding:EdgeInsets.zero))),
      Positioned(bottom:2,left:2,child:Material(color:Theme.of(context).colorScheme.surface,shape:const CircleBorder(),child:IconButton(tooltip:'Copy Image',onPressed:enabled?onCopy:null,icon:const Icon(Icons.copy,size:16),constraints:const BoxConstraints.tightFor(width:28,height:28),padding:EdgeInsets.zero))),
    ])));
}
