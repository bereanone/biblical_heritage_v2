package android.media
class AudioAttributes { class Builder { fun setUsage(v:Int)=this; fun setContentType(v:Int)=this; fun build()=AudioAttributes() }; companion object { const val USAGE_MEDIA=1; const val CONTENT_TYPE_SPEECH=1 } }
class PlaybackParams {
 var selectedSpeed=1.0f; var selectedPitch=1.0f; var fallbackMode=0
 fun allowDefaults()=this
 fun setAudioFallbackMode(v:Int)=apply { fallbackMode=v }
 fun setSpeed(v:Float)=apply { selectedSpeed=v }
 fun setPitch(v:Float)=apply { selectedPitch=v }
 companion object { const val AUDIO_FALLBACK_MODE_FAIL=2 }
}
class AudioDeviceInfo(val type:Int=2)
class MediaPlayer {
 var routedDevice:AudioDeviceInfo?=AudioDeviceInfo(); val audioSessionId=1
 var currentPosition=0; val duration=100000; var failIsPlaying=false; private var playing=false
 var isPlaying:Boolean
  get(){check(!failIsPlaying){"Simulated invalid native state"};return playing}
  set(value){playing=value}
  private var parameters=PlaybackParams()
 var parameterWrites=0; var failParameters=false
 var playbackParams:PlaybackParams
  get()=parameters
  set(value){check(!released);if(failParameters)throw IllegalArgumentException("Unsupported hardware adjustment");parameters=value;parameterWrites++}
 var failStart=false; var released=false
 var path=""; var requested:Int?=null; var mode:Int?=null; var starts=mutableListOf<Int>()
 private var infoListener:((MediaPlayer,Int,Int)->Boolean)?=null
 private var errorListener:((MediaPlayer,Int,Int)->Boolean)?=null
 private var completion:((MediaPlayer)->Unit)?=null; private var seekComplete:((MediaPlayer)->Unit)?=null
 init { all.add(this) }
 fun setAudioAttributes(v:AudioAttributes){}; fun setDataSource(v:String){path=v}; fun prepare(){}
 fun setOnCompletionListener(v:(MediaPlayer)->Unit){completion=v}
 fun setOnInfoListener(v:(MediaPlayer,Int,Int)->Boolean){infoListener=v}
 fun info(what:Int,extra:Int){infoListener?.invoke(this,what,extra)}
 fun setOnErrorListener(v:(MediaPlayer,Int,Int)->Boolean){errorListener=v}
 fun fail(){errorListener?.invoke(this,1,2)}
 fun setOnSeekCompleteListener(v:(MediaPlayer)->Unit){seekComplete=v}
 fun seekTo(v:Int){requested=v}; fun seekTo(v:Long,m:Int){requested=v.toInt();mode=m}
 fun finishSeek(){currentPosition=requested!!;requested=null;seekComplete?.invoke(this)}
 fun finish(){isPlaying=false;completion?.invoke(this)}
 fun start(){check(!failStart){"Simulated decoder start failure"};isPlaying=true;starts.add(currentPosition)}; fun pause(){isPlaying=false}; fun release(){isPlaying=false;released=true}
 companion object { const val SEEK_CLOSEST=3; val all=mutableListOf<MediaPlayer>() }
}
