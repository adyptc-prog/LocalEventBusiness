import 'package:flutter/material.dart';

import '../core/platform_support.dart';
import '../widgets/menu_card.dart';
import 'activity_config_screen.dart';
import 'event_connect_screen.dart';
import 'event_server_screen.dart';
import 'leaderboard_screen.dart';
import 'menu_editor_screen.dart';
import 'orders_dashboard_screen.dart';
import 'participants_screen.dart';
import 'room_monitor_screen.dart';
import 'tables_screen.dart';

/// Ecranul de start al aplicației. Butonul principal duce la conectarea la
/// serverul localului curent — meniul de-acolo (`EventMenuScreen`) e dictat
/// de organizator, nu static. Cardurile de organizator (Server local,
/// Activități, Produse meniu, Mese, Comenzi la bar) și clasamentul rămân
/// accesibile direct, fără conexiune — organizatorul trebuie să poată porni
/// serverul fără să depindă de conexiunea la el însuși.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.hub, size: 48, color: Colors.white),
                        SizedBox(height: 12),
                        Text('LocalEventBusiness',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('multiplayer local, fără internet — pe același Wi-Fi sau hotspot',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.leaderboard),
                    tooltip: 'Clasament',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    MenuCard(
                      icon: Icons.wifi,
                      title: 'Intră la eveniment',
                      subtitle: 'Conectează-te la serverul evenimentului curent și vezi ce activități sunt active.',
                      color: const Color(0xFF0B5E3B),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const EventConnectScreen()),
                      ),
                    ),
                    if (canHostEventServer) ...[
                      const SizedBox(height: 20),
                      MenuCard(
                        icon: Icons.dns,
                        title: 'Server local',
                        subtitle: 'Pornește acest telefon ca server central — clienții își creează singuri conexiunea.',
                        color: const Color(0xFF3A2E0E),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const EventServerScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      MenuCard(
                        icon: Icons.point_of_sale,
                        title: 'Comenzi la bar',
                        subtitle: 'Coada live de comenzi — avansează statusul fiecăreia.',
                        color: const Color(0xFF6B3F1D),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const OrdersDashboardScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.checklist),
                              label: const Text('Activități'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const ActivityConfigScreen()),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.restaurant_menu),
                              label: const Text('Produse meniu'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const MenuEditorScreen()),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Mese / cod QR'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const TablesScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.people),
                          label: const Text('Participanți'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const ParticipantsScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: const Text('Monitorizează camere'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const RoomMonitorScreen()),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
