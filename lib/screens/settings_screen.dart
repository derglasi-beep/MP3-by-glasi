import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../services/equalizer_service.dart';

class SettingsScreen extends StatefulWidget {
  final AudioPlayerService player;
  const SettingsScreen({super.key, required this.player});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = SettingsService();
  late final EqualizerService eq;
  List<double> bands = const [];
  List<String> bandLabels = const [];
  double eqMin = -12;
  double eqMax = 12;
  bool eqAvailable = false;
  double bass=0, treble=0, preamp=0, crossfade=0, speed=1, volume=.8;

  @override
  void initState() {
    super.initState();
    eq=EqualizerService(effect: widget.player.equalizer);
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      s.eqBands, s.bass, s.treble, s.preamp, s.crossfade, s.speed, s.volume,
    ]);
    final savedBands = values[0] as List<double>;
    final info = await eq.info;
    if (info != null && info.bands.isNotEmpty) {
      eqAvailable = true;
      eqMin = info.minDecibels;
      eqMax = info.maxDecibels;
      bands = List.generate(
        info.bands.length,
        (i) => i < savedBands.length ? savedBands[i].clamp(eqMin, eqMax).toDouble() : 0,
      );
      bandLabels = info.bands.map((band) {
        final hz = band.centerFrequency;
        return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k' : hz.round().toString();
      }).toList();
    }
    bass=values[1] as double;
    treble=values[2] as double;
    preamp=values[3] as double;
    crossfade=values[4] as double;
    speed=values[5] as double;
    volume=values[6] as double;
    if (!mounted) return;
    setState(() {});
  }

  Widget slider(String title,double value,double min,double max,ValueChanged<double> onChanged)=>
      Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title), Slider(value:value,min:min,max:max,onChanged:onChanged)
      ]);

  Future<void> _band(int i,double v) async {
    setState(()=>bands[i]=v);
    await widget.player.setEqBand(i,v);
    await s.setEqBand(i,v);
  }

  Future<void> _resetEq() async {
    for (var i=0;i<bands.length;i++) {
      bands[i]=0;
      await widget.player.setEqBand(i,0);
      await s.setEqBand(i,0);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Audio & Einstellungen')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text(eqAvailable ? '${bands.length}-Band EQ' : 'Equalizer',style:Theme.of(context).textTheme.headlineSmall),
        TextButton.icon(onPressed:_resetEq,icon:const Icon(Icons.restart_alt),label:const Text('Reset')),
      ]),
      const SizedBox(height:8),
      if (!eqAvailable)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('Auf diesem Gerät ist kein Android-Equalizer verfügbar.'),
        )
      else
        SizedBox(height:220,child:Row(
          crossAxisAlignment:CrossAxisAlignment.stretch,
          children:List.generate(bands.length,(i)=>Expanded(child:Column(children:[
            Expanded(child:RotatedBox(quarterTurns:3,child:Slider(
              min:eqMin,max:eqMax,value:bands[i],onChanged:(v)=>_band(i,v),
            ))),
            Text(bandLabels[i],style:Theme.of(context).textTheme.labelSmall),
            Text(bands[i].toStringAsFixed(0),style:Theme.of(context).textTheme.labelSmall),
          ]))),
        )),
      if (eqAvailable)
        Text('Gerätebereich: ${eqMin.toStringAsFixed(0)} bis ${eqMax.toStringAsFixed(0)} dB'),
      const Divider(height:32),
      Text('Player-Lautstärke',style:Theme.of(context).textTheme.headlineSmall),
      const Text('Unabhängig von der Android-Medienlautstärke.'),
      slider('${(volume*100).round()} %',volume,0,1,(v){
        setState(()=>volume=v); widget.player.setVolume(v); s.setVolume(v);
      }),
      const Divider(height:32),
      Text('Sound',style:Theme.of(context).textTheme.headlineSmall),
      slider('Preamp  ${preamp.toStringAsFixed(1)} dB',preamp,-12,12,(v){
        setState(()=>preamp=v); widget.player.setPreamp(v); s.setPreamp(v);
      }),
      slider('Bass  ${bass.toStringAsFixed(0)} dB',bass,-12,12,(v){
        setState(()=>bass=v); widget.player.setBass(v); s.setBass(v);
      }),
      slider('Treble  ${treble.toStringAsFixed(0)} dB',treble,-12,12,(v){
        setState(()=>treble=v); widget.player.setTreble(v); s.setTreble(v);
      }),
      const Divider(height:32),
      Text('Wiedergabe',style:Theme.of(context).textTheme.headlineSmall),
      slider('Geschwindigkeit  ${speed.toStringAsFixed(2)}×',speed,.5,2,(v){
        setState(()=>speed=v); widget.player.setSpeed(v); s.setSpeed(v);
      }),
      slider('Crossfade  ${crossfade.toStringAsFixed(0)} s',crossfade,0,12,(v){
        setState(()=>crossfade=v); s.setCrossfade(v);
      }),
      const SizedBox(height:8),
      const Text('Crossfade ist als Einstellung vorbereitet; die eigentliche Überblendung kommt mit dem nächsten Playback-Engine-Schritt.'),
    ]),
  );
}
