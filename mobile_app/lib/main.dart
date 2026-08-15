import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'api_service.dart';
import 'auth_screens.dart';
import 'create_listing_screen.dart';

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
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadCurrentUser();
  }

  Future<void> _loadListings() async {
    setState(() => _isLoading = true);
    final data = await ApiService.fetchMapListings();
    setState(() {
      _listings = data;
      _isLoading = false;
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await ApiService.fetchCurrentUser();
    setState(() => _currentUser = user);
  }

  Future<void> _openAuth() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (loggedIn == true) _loadCurrentUser();
  }

  Future<void> _logout() async {
    await ApiService.logout();
    setState(() => _currentUser = null);
  }

  Future<void> _openCreateListing() async {
    if (_currentUser == null) {
      await _openAuth();
      if (!mounted || _currentUser == null) return; // user closed the login screen without logging in
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
    if (created == true) _loadListings();
  }

  void _showListingModal(String listingId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool isUnlocking = false;
        Map<String, dynamic>? unlockedContact;
        String? errorMessage;
        bool showLoginPrompt = false;
        final imageScrollController = ScrollController();

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
                final images = (listing['images'] as List?)?.cast<String>() ?? [];

                return Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (images.isNotEmpty) ...[
                        SizedBox(
                          height: 180,
                          // Two separate desktop-web gotchas here: a plain
                          // ListView doesn't scroll on mouse-wheel unless the
                          // axis is horizontal AND the wheel's vertical delta
                          // is manually applied (Listener below), and mouse
                          // click-drag needs to be explicitly allowed via
                          // ScrollConfiguration - Flutter's default only
                          // enables drag-to-scroll for touch/stylus.
                          child: Listener(
                            onPointerSignal: (event) {
                              if (event is PointerScrollEvent && imageScrollController.hasClients) {
                                imageScrollController.jumpTo(
                                  (imageScrollController.offset + event.scrollDelta.dy)
                                      .clamp(0.0, imageScrollController.position.maxScrollExtent),
                                );
                              }
                            },
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: ListView.separated(
                                controller: imageScrollController,
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 8),
                                itemBuilder: (context, i) => ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    images[i],
                                    width: 240,
                                    height: 180,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) => progress == null
                                        ? child
                                        : Container(
                                            width: 240,
                                            color: Colors.grey.shade200,
                                            child: const Center(child: CircularProgressIndicator()),
                                          ),
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 240,
                                      color: Colors.grey.shade200,
                                      child: const Center(child: Icon(Icons.image_not_supported, color: Colors.grey)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            label: Text(
                              listing['property_type'] ?? 'PROPERTY',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                      if (listing['owner_name'] != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Listed by ${listing['owner_name']}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                              const Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF0D9488),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  aiValuation['badge_label'] ??
                                      'Price Valuation Available',
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
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (showLoginPrompt)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _openAuth();
                            },
                            child: const Text('Login to unlock contact'),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: unlockedContact != null
                              ? Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF0D9488),
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.phone,
                                        color: Color(0xFF0D9488),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        unlockedContact!['phone_number'] ?? '',
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: isUnlocking
                                      ? null
                                      : () async {
                                          setModalState(() {
                                            isUnlocking = true;
                                            errorMessage = null;
                                          });
                                          try {
                                            final result =
                                                await ApiService.unlockContact(
                                                  listingId,
                                                );
                                            setModalState(() {
                                              unlockedContact =
                                                  result['contact'];
                                              isUnlocking = false;
                                            });
                                            _loadCurrentUser();
                                          } on NotLoggedInException {
                                            setModalState(() {
                                              showLoginPrompt = true;
                                              isUnlocking = false;
                                            });
                                          } catch (e) {
                                            setModalState(() {
                                              errorMessage = e
                                                  .toString()
                                                  .replaceAll(
                                                    'Exception: ',
                                                    '',
                                                  );
                                              isUnlocking = false;
                                            });
                                          }
                                        },
                                  icon: isUnlocking
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.lock_open),
                                  label: Text(
                                    isUnlocking
                                        ? 'Unlocking...'
                                        : 'Unlock Owner Contact (5 Points)',
                                  ),
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
          if (_currentUser != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle),
              onSelected: (value) {
                if (value == 'logout') _logout();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    '${_currentUser!['full_name']} · ${_currentUser!['points_balance']} pts',
                  ),
                ),
                const PopupMenuItem(value: 'logout', child: Text('Logout')),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Login',
              onPressed: _openAuth,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadListings),
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
                    final lat =
                        double.tryParse(item['latitude']?.toString() ?? '') ??
                        36.8065;
                    final lng =
                        double.tryParse(item['longitude']?.toString() ?? '') ??
                        10.1815;

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateListing,
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_home),
        label: const Text('List a place'),
      ),
    );
  }
}
