package android.media
class AudioAttributes { class Builder { fun setUsage(v:Int)=this; fun setContentType(v:Int)=this; fun build()=AudioAttributes() }; companion object { const val USAGE_MEDIA=1; const val CONTENT_TYPE_SPEECH=1 } }
class PlaybackParams { fun setSpeed(v:Float)=this; fun setPitch(v:Float)=this }
class MediaPlayer {
 var currentPosition=0; val duration=100000; var isPlaying=false; var playbackParams=PlaybackParams()
 var path=""; var requested:Int?=null; var mode:Int?=null; var starts=mutableListOf<Int>()
 private var completion:((MediaPlayer)->Unit)?=null; private var seekComplete:((MediaPlayer)->Unit)?=null
 init { all.add(this) }
 fun setAudioAttributes(v:AudioAttributes){}; fun setDataSource(v:String){path=v}; fun prepare(){}
 fun setOnCompletionListener(v:(MediaPlayer)->Unit){completion=v}
 fun setOnErrorListener(v:(MediaPlayer,Int,Int)->Boolean){}
 fun setOnSeekCompleteListener(v:(MediaPlayer)->Unit){seekComplete=v}
 fun seekTo(v:Int){requested=v}; fun seekTo(v:Long,m:Int){requested=v.toInt();mode=m}
 fun finishSeek(){currentPosition=requested!!;requested=null;seekComplete?.invoke(this)}
 fun finish(){isPlaying=false;completion?.invoke(this)}
 fun start(){isPlaying=true;starts.add(currentPosition)}; fun pause(){isPlaying=false}; fun release(){isPlaying=false}
 companion object { const val SEEK_CLOSEST=3; val all=mutableListOf<MediaPlayer>() }
}
