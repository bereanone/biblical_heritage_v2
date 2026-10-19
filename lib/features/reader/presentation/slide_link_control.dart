import 'package:flutter/material.dart';
class SlideLinkControl extends StatelessWidget {
  const SlideLinkControl({super.key,required this.linked,required this.onChanged,this.nextTitle,this.disabledReason,this.saving=false});
  final bool linked,saving;
  final String? nextTitle,disabledReason;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context)=>GestureDetector(
    behavior:HitTestBehavior.opaque,excludeFromSemantics:true,
    onTap:saving || onChanged==null ? () {} : null,
    child:SwitchListTile.adaptive(
    contentPadding:EdgeInsets.zero,dense:true,
    value:linked,onChanged:saving?null:onChanged,
    title:Text('Link with next: ${linked?'ON':'OFF'}',style:const TextStyle(fontWeight:FontWeight.w700)),
    subtitle:Text(saving?'Saving link…':disabledReason??(linked?'Shares a slide with ${nextTitle??'the next entry'}.':'Starts a separate slide after this entry.')),
  ));
}
