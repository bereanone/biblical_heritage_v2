package io.flutter.plugin.common
class MethodCall(val method:String,val arguments:Any?)
class MethodChannel(m:Any,n:String) {
 interface Result { fun success(v:Any?); fun error(c:String,m:String?,d:Any?); fun notImplemented() }
 fun setMethodCallHandler(h:(MethodCall,Result)->Unit){ handler=h }
 fun invokeMethod(n:String,v:Any?){notifications.add(n to v)}
 companion object { val notifications=mutableListOf<Pair<String,Any?>>()
 lateinit var handler:(MethodCall,Result)->Unit; fun call(n:String,a:Map<String,Any?> = emptyMap()){handler(MethodCall(n,a),object:Result {override fun success(v:Any?){};override fun error(c:String,m:String?,d:Any?){error("$c $m")};override fun notImplemented(){error("missing")}})} }
}
