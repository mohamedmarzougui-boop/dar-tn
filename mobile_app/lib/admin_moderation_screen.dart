import 'package:flutter/material.dart';
import 'api_service.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  List<dynamic> _listings = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final listings = await ApiService.fetchModerationQueue();
      setState(() {
        _listings = listings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _moderate(String listingId, String status) async {
    setState(() => _processingIds.add(listingId));
    try {
      await ApiService.moderateListing(listingId, status);
      setState(() {
        _listings.removeWhere((l) => l['id'] == listingId);
        _processingIds.remove(listingId);
      });
    } catch (e) {
      setState(() => _processingIds.remove(listingId));
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
        title: const Text('Moderation Queue'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : _listings.isEmpty
                  ? const Center(child: Text('Nothing awaiting moderation.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _listings.length,
                      itemBuilder: (context, i) {
                        final listing = _listings[i];
                        final images = (listing['images'] as List?)?.cast<String>() ?? [];
                        final isProcessing = _processingIds.contains(listing['id']);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (images.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          images.first,
                                          width: 70,
                                          height: 70,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 70,
                                            height: 70,
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(listing['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text('${listing['price_tnd']} TND · ${listing['city']}, ${listing['delegation']}'),
                                          Text(
                                            listing['status'],
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: isProcessing ? null : () => _moderate(listing['id'], 'ARCHIVED'),
                                      child: const Text('Reject', style: TextStyle(color: Colors.red)),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488), foregroundColor: Colors.white),
                                      onPressed: isProcessing ? null : () => _moderate(listing['id'], 'ACTIVE'),
                                      child: isProcessing
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                          : const Text('Approve'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
