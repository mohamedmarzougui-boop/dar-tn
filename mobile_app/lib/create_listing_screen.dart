import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'api_service.dart';
import 'tunisia_locations.dart';

const _propertyTypes = ['STUDIO', 'S_PLUS_1', 'S_PLUS_2', 'S_PLUS_3', 'S_PLUS_4', 'COLOCATION', 'HOUSE', 'VILLA'];
const _targetTenants = ['ANY', 'BOYS_ONLY', 'GIRLS_ONLY', 'STUDENT', 'FAMILY'];

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();
  final _bedroomsController = TextEditingController(text: '1');
  final _bathroomsController = TextEditingController(text: '1');
  final _surfaceController = TextEditingController();

  String _propertyType = _propertyTypes.first;
  String _targetTenant = _targetTenants.first;
  String? _selectedCity;
  String? _selectedDelegation;

  // Bumped whenever paste-and-parse programmatically changes a dropdown's
  // value, so the dropdowns below get a new key and rebuild fresh - their
  // FormFieldState otherwise only reads `initialValue` on first build and
  // ignores later external changes, which would silently desync the
  // displayed value from what's actually selected.
  int _formGeneration = 0;
  bool _hasClimatisation = false;
  bool _hasChauffageCentral = false;
  bool _hasWifi = false;
  bool _hasElevator = false;
  bool _isFurnished = false;

  LatLng? _selectedLocation;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      setState(() => _errorMessage = 'Tap the map to set the listing location.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ApiService.createListing({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'price_tnd': double.parse(_priceController.text),
        'deposit_tnd': _depositController.text.trim().isEmpty ? 0 : double.parse(_depositController.text),
        'property_type': _propertyType,
        'target_tenant': _targetTenant,
        'bedrooms': int.tryParse(_bedroomsController.text) ?? 1,
        'bathrooms': int.tryParse(_bathroomsController.text) ?? 1,
        'has_climatisation': _hasClimatisation,
        'has_chauffage_central': _hasChauffageCentral,
        'has_wifi': _hasWifi,
        'has_elevator': _hasElevator,
        'is_furnished': _isFurnished,
        'surface_m2': _surfaceController.text.trim().isEmpty ? null : int.tryParse(_surfaceController.text),
        'city': _selectedCity,
        'delegation': _selectedDelegation,
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
      });

      if (mounted) Navigator.pop(context, true);
    } on NotLoggedInException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openPasteDialog() async {
    final pasteController = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste listing text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a post from a Facebook group or elsewhere. We\'ll try to '
              'fill in the fields below - review everything before publishing.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pasteController,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Paste text here...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, pasteController.text),
            child: const Text('Parse'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty || !mounted) return;

    try {
      final fields = await ApiService.parseListingText(text);
      setState(() {
        if (fields['title'] != null) _titleController.text = fields['title'];
        if (fields['description'] != null) _descriptionController.text = fields['description'];
        if (fields['price_tnd'] != null) _priceController.text = fields['price_tnd'].toString();
        if (fields['property_type'] != null && _propertyTypes.contains(fields['property_type'])) {
          _propertyType = fields['property_type'];
        }
        if (fields['target_tenant'] != null && _targetTenants.contains(fields['target_tenant'])) {
          _targetTenant = fields['target_tenant'];
        }
        if (fields['city'] != null && tunisiaLocations.containsKey(fields['city'])) {
          _selectedCity = fields['city'];
          if (fields['delegation'] != null && tunisiaLocations[_selectedCity]!.contains(fields['delegation'])) {
            _selectedDelegation = fields['delegation'];
          }
        }
        _hasClimatisation = fields['has_climatisation'] ?? _hasClimatisation;
        _hasChauffageCentral = fields['has_chauffage_central'] ?? _hasChauffageCentral;
        _hasWifi = fields['has_wifi'] ?? _hasWifi;
        _hasElevator = fields['has_elevator'] ?? _hasElevator;
        _isFurnished = fields['is_furnished'] ?? _isFurnished;
        _formGeneration++;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fields prefilled - please review before publishing.')),
        );
      }
    } on NotLoggedInException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Listing'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste_go),
            tooltip: 'Paste from text',
            onPressed: _openPasteDialog,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(labelText: 'Price (TND/month)', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      return double.tryParse(v) == null ? 'Must be a number' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _depositController,
                    decoration: const InputDecoration(labelText: 'Deposit (optional)', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('propertyType-$_formGeneration'),
              initialValue: _propertyType,
              decoration: const InputDecoration(labelText: 'Property Type', border: OutlineInputBorder()),
              items: _propertyTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _propertyType = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('targetTenant-$_formGeneration'),
              initialValue: _targetTenant,
              decoration: const InputDecoration(labelText: 'Target Tenant', border: OutlineInputBorder()),
              items: _targetTenants.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _targetTenant = v!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _bedroomsController,
                    decoration: const InputDecoration(labelText: 'Bedrooms', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _bathroomsController,
                    decoration: const InputDecoration(labelText: 'Bathrooms', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _surfaceController,
                    decoration: const InputDecoration(labelText: 'm² (optional)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('city-$_formGeneration'),
                    initialValue: _selectedCity,
                    decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder()),
                    isExpanded: true,
                    items: tunisiaLocations.keys.map((city) => DropdownMenuItem(value: city, child: Text(city))).toList(),
                    onChanged: (city) => setState(() {
                      _selectedCity = city;
                      _selectedDelegation = null;
                    }),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // Keying on _selectedCity too resets this field whenever the
                    // city changes (whether from direct selection or paste-parse) -
                    // otherwise it could keep showing a delegation that belongs to
                    // whatever city was previously selected.
                    key: ValueKey('delegation-$_selectedCity-$_formGeneration'),
                    initialValue: _selectedDelegation,
                    decoration: const InputDecoration(labelText: 'Delegation', border: OutlineInputBorder()),
                    isExpanded: true,
                    items: (tunisiaLocations[_selectedCity] ?? [])
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: _selectedCity == null ? null : (delegation) => setState(() => _selectedDelegation = delegation),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(label: const Text('AC'), selected: _hasClimatisation, onSelected: (v) => setState(() => _hasClimatisation = v)),
                FilterChip(label: const Text('Central Heating'), selected: _hasChauffageCentral, onSelected: (v) => setState(() => _hasChauffageCentral = v)),
                FilterChip(label: const Text('WiFi'), selected: _hasWifi, onSelected: (v) => setState(() => _hasWifi = v)),
                FilterChip(label: const Text('Elevator'), selected: _hasElevator, onSelected: (v) => setState(() => _hasElevator = v)),
                FilterChip(label: const Text('Furnished'), selected: _isFurnished, onSelected: (v) => setState(() => _isFurnished = v)),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _selectedLocation == null ? 'Tap the map to set the listing location' : 'Location set - tap again to adjust',
              style: TextStyle(color: _selectedLocation == null ? Colors.grey.shade700 : const Color(0xFF0D9488), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: const LatLng(36.8065, 10.1815),
                    initialZoom: 11,
                    onTap: (tapPosition, point) => setState(() => _selectedLocation = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.dartn.app',
                    ),
                    if (_selectedLocation != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _selectedLocation!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin, color: Color(0xFF0D9488), size: 40),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Publish Listing'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
