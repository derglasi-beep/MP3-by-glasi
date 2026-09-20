import 'package:flutter/material.dart';
import 'services/audio_player_service.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';

class Mp3ByGlasiApp extends StatefulWidget { const Mp3ByGlasiApp({super.key}); @override State<Mp3ByGlasiApp> createState()=>_AppState(); }
class _AppState extends State<Mp3ByGlasiApp> {
  late final AudioPlayerService player;
  @override void initState(){super.initState();player=AudioPlayerService();}
  @override void dispose(){player.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>MaterialApp(
    title:'MP3 by Glasi',debugShowCheckedModeBanner:false,
    theme:ThemeData.dark(useMaterial3:true).copyWith(scaffoldBackgroundColor:const Color(0xFF101114),cardColor:const Color(0xFF181A1F)),
    home: _Shell(player:player),
  );
}

class _Shell extends StatefulWidget { final AudioPlayerService player; const _Shell({required this.player}); @override State<_Shell> createState()=>_ShellState(); }
class _ShellState extends State<_Shell> { int index=0;
  @override Widget build(BuildContext context){ final pages=[PlayerScreen(player:widget.player),SettingsScreen(player:widget.player)]; return Scaffold(body:pages[index],bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const[NavigationDestination(icon:Icon(Icons.library_music),label:'Player'),NavigationDestination(icon:Icon(Icons.tune),label:'Audio')]),); }
}
