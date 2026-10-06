import 'package:flutter/material.dart';

import '../models/saved_itinerary.dart';
import '../services/itinerary_store.dart';
import 'itinerary_screen.dart';

class SavedItinerariesScreen extends StatefulWidget {
  const SavedItinerariesScreen({super.key});

  @override
  State<SavedItinerariesScreen> createState() => _SavedItinerariesScreenState();
}

class _SavedItinerariesScreenState extends State<SavedItinerariesScreen> {
  final ItineraryStore _store = ItineraryStore();
  List<SavedItinerary> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _delete(SavedItinerary it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除行程'),
        content: Text('確定要刪除「${it.name}」嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(it.id);
    await _load();
  }

  void _open(SavedItinerary it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ItineraryScreen(initialPlan: it.plan, initialSettings: it.settings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的行程')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '尚無儲存的行程。\n到「智慧行程規劃」產生行程後，按「儲存行程」即可保存。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.map_outlined)),
                        title: Text(it.name),
                        subtitle: Text(
                          '${it.dateText}　·　${it.plan.stops.length} 站　·　${it.plan.distanceText}',
                        ),
                        onTap: () => _open(it),
                        trailing: IconButton(
                          tooltip: '刪除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(it),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
