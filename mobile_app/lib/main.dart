import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'api_service.dart';
import 'auth_screens.dart'; // Added import for Auth Screens

void main() {
  runApp(const DarTnApp());
}

class DarTnApp extends StatelessWidget {
  const DarTnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dar-TN | Immobilier & Colocation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D9488)),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> _listings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() => _isLoading = true);
    final data = await ApiService.fetchMapListings();
    setState(() {
      _listings = data;
      _isLoading = false;
    });
  }

  void _showListingModal(String listingId) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // State variables for the interactive button
        bool isUnlocking = false;
        String? unlockedPhone;
        String? errorMessage;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FutureBuilder<Map<String, dynamic>>(
              future: ApiService.fetchListingDetails(listingId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: Text('Failed to load details.')),
                  );
                }

                final listing = snapshot.data!['listing'];
                final aiValuation = snapshot.data!['ai_valuation'];

                return Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            label: Text(
                              listing['property_type'] ?? 'PROPERTY',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: Colors.teal.shade50,
                          ),
                          Text(
                            '${listing['price_tnd']} TND / month',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        listing['title'] ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '📍 ${listing['city']}, ${listing['delegation']}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 16),

                      if (aiValuation != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: Color(0xFF0D9488)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  aiValuation['badge_label'] ?? 'Price Valuation Available',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Error Message Display
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        ),

                      // The Interactive Unlock Button / Phone Reveal
                      SizedBox(
                        width: double.infinity,
                        child: unlockedPhone != null
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF0D9488), width: 2),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.phone, color: Color(0xFF0D9488)),
                                    const SizedBox(width: 10),
                                    Text(
                                      unlockedPhone!,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0D9488),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: isUnlocking
                                    ? null
                                    : () async {
                                        setModalState(() {
                                          isUnlocking = true;
                                          errorMessage = null;
                                        });

                                        try {
                                          final result = await ApiService.unlockContact(listingId);
                                          setModalState(() {
                                            unlockedPhone = result['owner_phone'] ?? '+216 XX XXX XXX';
                                            isUnlocking = false;
                                          });
                                        } catch (e) {
                                          setModalState(() {
                                            // The backend will reject this until we add Auth!
                                            errorMessage = e.toString().replaceAll("Exception: ", "");
                                            isUnlocking = false;
                                          });
                                        }
                                      },
                                icon: isUnlocking
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.lock_open),
                                label: Text(isUnlocking ? 'Unlocking...' : 'Unlock Owner Contact (5 Points)'),
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dar-TN | Map View'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        actions: [
          // Added Person Icon to Navigate to Login Screen
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadListings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(36.8065, 10.1815),
                initialZoom: 9.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dartn.app',
                ),
                MarkerLayer(
                  markers: _listings.map((item) {
                    final lat = double.tryParse(item['latitude']?.toString() ?? '') ?? 36.8065;
                    final lng = double.tryParse(item['longitude']?.toString() ?? '') ?? 10.1815;

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 90,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _showListingModal(item['id']),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${item['price_tnd']} DT',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}