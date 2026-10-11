package android.os
object Build { object VERSION { var SDK_INT=36 }; object VERSION_CODES { const val O=26 } }
class Looper { companion object { fun getMainLooper()=Looper() } }
class Handler(v:Looper) { fun post(v:Runnable){tasks.add(v)}; fun postDelayed(v:Runnable,ms:Long){}; fun removeCallbacks(v:Runnable){tasks.remove(v)}; companion object { val tasks=mutableListOf<Runnable>(); fun tick(){val copy=tasks.toList();tasks.clear();copy.forEach{it.run()}} } }
