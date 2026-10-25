package android.os
object Build { object VERSION { var SDK_INT=36 }; object VERSION_CODES { const val O=26 } }
class Looper { companion object { fun getMainLooper()=Looper() } }
class Handler(v:Looper) {
 fun post(v:Runnable) { postDelayed(v, 0) }
 fun postDelayed(v:Runnable,ms:Long) { tasks.add(Task(now+ms,v)) }
 fun removeCallbacks(v:Runnable) { tasks.removeAll { it.runnable === v } }
 companion object {
  data class Task(val at:Long,val runnable:Runnable)
  private val tasks=mutableListOf<Task>()
  private var now=0L
  fun tick() { advanceBy(0) }
  fun advanceBy(ms:Long) {
   val target=now+ms
   while(true) {
    val next=tasks.filter { it.at<=target }.minByOrNull { it.at } ?: break
    tasks.remove(next); now=next.at; next.runnable.run()
   }
   now=target
  }
 }
}
