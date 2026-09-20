import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final AudioPlayerService player; const SettingsScreen({super.key,required this.player});
  @override State<SettingsScreen> createState()=>_SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s=SettingsService(); double bass=0,treble=0,preamp=0,crossfade=0,speed=1;
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { bass=await s.bass; treble=await s.treble; preamp=await s.preamp; crossfade=await s.crossfade; speed=await s.speed; if(mounted)setState((){});}
  Widget slider(String title,double value,double min,double max,ValueChanged<double> onChanged)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title),Slider(value:value,min:min,max:max,onChanged:onChanged)]);
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Audio & Einstellungen')),body:ListView(padding:const EdgeInsets.all(20),children:[
    Text('Sound',style:Theme.of(context).textTheme.headlineSmall),
    slider('Preamp  '+preamp.toStringAsFixed(1)+' dB',preamp,-12,12,(v){setState(()=>preamp=v);s.setPreamp(v);}),
    slider('Bass  '+bass.toStringAsFixed(0)+' dB',bass,-12,12,(v){setState(()=>bass=v);s.setBass(v);}),
    slider('Treble  '+treble.toStringAsFixed(0)+' dB',treble,-12,12,(v){setState(()=>treble=v);s.setTreble(v);}),
    const Divider(height:32), Text('Wiedergabe',style:Theme.of(context).textTheme.headlineSmall),
    slider('Geschwindigkeit  '+speed.toStringAsFixed(2)+'×',speed,.5,2,(v){setState(()=>speed=v);widget.player.setSpeed(v);s.setSpeed(v);}),
    slider('Crossfade  '+crossfade.toStringAsFixed(0)+' s',crossfade,0,12,(v){setState(()=>crossfade=v);s.setCrossfade(v);}),
    const SizedBox(height:12), const Text('Der EQ wird als nächstes an die Audio-Pipeline gekoppelt. Die Regler sind bereits persistent vorbereitet.'),
  ]));
}
