import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AudioPlayer audio=AudioPlayer();
  final List<Track> queue=[];
  int currentIndex=-1; bool shuffle=false; LoopMode loopMode=LoopMode.off;
  Stream<Duration> get positionStream=>audio.positionStream; Stream<Duration?> get durationStream=>audio.durationStream; Stream<PlayerState> get playerStateStream=>audio.playerStateStream;
  Track? get currentTrack=>currentIndex>=0&&currentIndex<queue.length?queue[currentIndex]:null;
  Future<void> setQueue(List<Track> tracks,{int startIndex=0}) async { queue..clear()..addAll(tracks); if(queue.isEmpty){currentIndex=-1;await audio.stop();return;} currentIndex=startIndex.clamp(0,queue.length-1); await _load(); }
  Future<void> _load() async { final t=currentTrack;if(t!=null) await audio.setFilePath(t.path); }
  Future<void> play() async {if(currentTrack!=null)await audio.play();} Future<void> pause()=>audio.pause(); Future<void> seek(Duration p)=>audio.seek(p);
  Future<void> setVolume(double v)=>audio.setVolume(v.clamp(0,1)); Future<void> setSpeed(double v)=>audio.setSpeed(v.clamp(.5,2));
  Future<void> next() async {if(queue.isEmpty)return;currentIndex=(currentIndex+1)%queue.length;await _load();await play();}
  Future<void> previous() async {if(queue.isEmpty)return;if(audio.position>const Duration(seconds:3)){await seek(Duration.zero);return;}currentIndex=(currentIndex-1+queue.length)%queue.length;await _load();await play();}
  Future<void> toggleShuffle() async {shuffle=!shuffle;await audio.setShuffleModeEnabled(shuffle);}
  Future<void> toggleRepeat() async {loopMode=switch(loopMode){LoopMode.off=>LoopMode.all,LoopMode.all=>LoopMode.one,LoopMode.one=>LoopMode.off};await audio.setLoopMode(loopMode);}
  Future<void> dispose()=>audio.dispose();
}
