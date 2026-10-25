import android.media.MediaPlayer
import android.os.Handler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.deanbowen.bibleappmac.RecordedBibleAudioBridge
import java.io.File
val fixtureRoot=File(System.getProperty("java.io.tmpdir"), "studybible-audio-fixtures").apply { mkdirs() }
fun call(n:String,vararg args:Pair<String,Any?>)=MethodChannel.call(n,mapOf(*args))
fun fresh():MediaPlayer { RecordedBibleAudioBridge(FlutterEngine());call("load","path" to File(fixtureRoot,"chapter.m4a").path);return MediaPlayer.all.last() }
fun events(){call("setAnnouncementEvents","events" to listOf(mapOf("seconds" to 10.0,"paths" to listOf(File(fixtureRoot,"cue.m4a").path))))}
fun baseline(){
 File(File(fixtureRoot,"chapter.m4a").path).writeText("stub");File(File(fixtureRoot,"cue.m4a").path).writeText("stub")
 var p=fresh();events();call("play");p.currentPosition=10380;Handler.tick();val cue=MediaPlayer.all.last()
 check(!p.isPlaying);check(p.requested==10000){"Late cue did not restore verse start: ${p.requested}"};check(p.mode==MediaPlayer.SEEK_CLOSEST)
 cue.finish();check(!p.isPlaying){"Chapter resumed before seek completed"};p.finishSeek();check(p.starts.last()==10000)
 println("PASS delayed verse cue resumes at first-word boundary and waits for seek")
 call("stop");p=fresh();events();call("seek","seconds" to 10.0);call("play","announceAtStart" to true)
 check(MediaPlayer.all.last()!==p){"Cue missed because seek position was stale"};p.finishSeek();check(!p.isPlaying);MediaPlayer.all.last().finish();check(p.starts.last()==10000)
 println("PASS seeking into verse announces before chapter, even with stale position")
 call("seek","seconds" to 20.0);call("seek","seconds" to 30.0);p.finishSeek();check(!p.isPlaying);check(p.requested==30000);p.finishSeek();check(p.starts.last()==30000)
 println("PASS rapid seeks serialize and latest target wins")
 call("seek","seconds" to 40.0);call("pause");p.finishSeek();check(!p.isPlaying)
 println("PASS pause during seek does not restart playback")
 call("play");call("setLoopRange","startSeconds" to 10.0,"endSeconds" to 20.0);p.currentPosition=20100;Handler.tick();check(p.requested==10000);p.finishSeek();check(!p.isPlaying);MediaPlayer.all.last().finish();check(p.starts.last()==10000)
 println("PASS verse loop returns to complete opening after announcement")
 call("stop");p=fresh();events();call("play");p.currentPosition=10380;Handler.tick();val old=p;call("stop");old.finishSeek();check(!old.isPlaying)
 println("PASS stop invalidates outstanding completion")
 call("stop");p=fresh()
 val book=File(fixtureRoot,"book_60.m4a").apply{writeText("stub")}.path
 val chapterCue=File(fixtureRoot,"chapter_001.m4a").apply{writeText("stub")}.path
 val verseCue=File(fixtureRoot,"cue.m4a").path
 call("setAnnouncementEvents","events" to listOf(mapOf("seconds" to 0.0,"paths" to listOf(book,chapterCue)),mapOf("seconds" to .24,"paths" to listOf(verseCue))))
 call("play","announceAtStart" to true);check(MediaPlayer.all.last().path==book)
 p.finishSeek();check(!p.isPlaying);MediaPlayer.all.last().finish();check(MediaPlayer.all.last().path==chapterCue);check(!p.isPlaying)
 MediaPlayer.all.last().finish();check(p.starts==listOf(0))
 p.currentPosition=450;Handler.tick();check(MediaPlayer.all.last().path==verseCue);MediaPlayer.all.last().finish();check(!p.isPlaying);p.finishSeek();check(p.starts.last()==240)
 println("PASS book and chapter cues finish before first verse and boundary resume")
}

fun errors() = MethodChannel.notifications.filter { it.first == "error" }
fun readyWithAnnouncement(): MediaPlayer {
 call("stop")
 val p=fresh()
 MethodChannel.notifications.clear()
 call("setAnnouncementEvents", "events" to listOf(mapOf("seconds" to 10.0,
  "paths" to listOf(File(fixtureRoot,"cue.m4a").path))))
 call("seek","seconds" to 10.0)
 call("play","announceAtStart" to true)
 return p
}
fun main() {
 baseline()
 for (sdk in listOf(24,26,36)) {
  android.os.Build.VERSION.SDK_INT=sdk
  var p=readyWithAnnouncement()
  MediaPlayer.all.last().finish()
  Handler.advanceBy(9999)
  check(errors().isEmpty() && p.starts.isEmpty())
  Handler.advanceBy(1)
  check(errors().size==1 && p.starts.isEmpty()) {"Missing seek must report once, never guess position"}
  Handler.advanceBy(20000);check(errors().size==1)
  p.finishSeek();check(p.starts.isEmpty()) {"Late seek must not restart after error"}
  call("play");check(p.starts==listOf(10000))
  println("PASS API branch $sdk: missing callback reports bounded error; late callback cannot autoplay")
  call("stop")
 }
 var p=readyWithAnnouncement()
 val cue=MediaPlayer.all.last()
 Handler.advanceBy(10000)
 check(errors().size==1 && cue.released && p.starts.isEmpty())
 cue.finish();check(p.starts.isEmpty())
 println("PASS timeout also stops remaining announcements")
 p=readyWithAnnouncement()
 MediaPlayer.all.last().finish()
 call("pause");Handler.advanceBy(20000)
 check(errors().isEmpty())
 call("play");Handler.advanceBy(10000)
 check(errors().size==1 && p.starts.isEmpty())
 println("PASS pause cancels timeout; resume re-arms stalled seek timeout")
 p=readyWithAnnouncement()
 MediaPlayer.all.last().finish();p.finishSeek()
 Handler.advanceBy(20000)
 check(errors().isEmpty() && p.starts==listOf(10000))
 println("PASS completed seek cancels timeout")
 p=readyWithAnnouncement()
 val old=p
 call("stop");p=fresh();call("play")
 old.finishSeek();old.fail();Handler.advanceBy(20000)
 check(errors().isEmpty() && p.isPlaying)
 println("PASS stop and replacement ignore stale seek, error, and timeout")
 p=readyWithAnnouncement()
 val oldCue=MediaPlayer.all.last()
 call("pause");oldCue.fail()
 check(errors().isEmpty())
 println("PASS stale announcement errors ignored after pause")
 p=readyWithAnnouncement()
 MediaPlayer.all.last().finish();p.failStart=true
 p.finishSeek()
 check(errors().size==1 && p.starts.isEmpty())
 println("PASS asynchronous seek callback start failure reports error instead of escaping")
 p=readyWithAnnouncement()
 p.finishSeek();p.failStart=true
 MediaPlayer.all.last().finish()
 check(errors().size==1 && p.starts.isEmpty())
 println("PASS asynchronous cue completion start failure reports error instead of escaping")
 p=readyWithAnnouncement()
 MediaPlayer.all.last().finish();Handler.advanceBy(9000)
 call("seek","seconds" to 20.0);p.finishSeek()
 Handler.advanceBy(1000);check(errors().isEmpty())
 p.finishSeek();check(p.starts==listOf(20000));Handler.advanceBy(10000)
 check(errors().isEmpty())
 println("PASS coalesced seek gets its own deadline and latest position wins")
 p=readyWithAnnouncement()
 MediaPlayer.all.last().finish();p.failIsPlaying=true
 Handler.advanceBy(10000)
 check(errors().size==1 && errors().single().second.toString().contains("could not reach the selected verse"))
 check(p.starts.isEmpty())
 p.finishSeek();check(p.starts.isEmpty())
 p.failIsPlaying=false
 println("PASS invalid native state during timeout cleanup still reports original error without autoplay")
 call("stop")
}
