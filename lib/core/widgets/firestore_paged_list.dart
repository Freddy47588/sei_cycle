import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/firestore_page.dart';
import 'async_state_widgets.dart';
import '../utils/operation_error.dart';

/// A cursor and loaded rows belong to one query generation, never to a build.
class FirestorePagedList<T> extends StatefulWidget {
  const FirestorePagedList({
    required this.queryKey,
    required this.load,
    required this.itemBuilder,
    this.header,
    this.transform,
    this.onLoaded,
    this.idOf,
    this.watchPage,
    super.key,
  });
  final Widget? header;
  final String Function(T)? idOf;
  final Stream<List<T>> Function(List<T> items)? watchPage;
  final Object queryKey;
  final Future<FirestorePage<T>> Function(
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  )
  load;
  final Widget Function(T item) itemBuilder;
  final List<T> Function(List<T> items)? transform;
  final Future<void> Function(List<T> items)? onLoaded;
  @override
  State<FirestorePagedList<T>> createState() => _FirestorePagedListState<T>();
}

class _FirestorePagedListState<T> extends State<FirestorePagedList<T>> {
  final _subscriptions = <StreamSubscription<List<T>>>[];
  final _items = <T>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _busy = false, _more = true;
  Object? _error;
  Object? _liveError;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant FirestorePagedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryKey != widget.queryKey) _reset();
  }

  Future<void> _reset() async {
    final generation = ++_generation;
    final previous = List.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in previous) {
      await subscription.cancel();
    }
    if (!mounted || generation != _generation) return;
    _items.clear();
    _cursor = null;
    _more = true;
    _busy = false;
    _error = null;
    _liveError = null;
    await _fetch();
  }

  Future<void> _fetch() async {
    if (_busy || !_more) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.load(_cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        final idOf = widget.idOf;
        final ids = idOf == null ? <String>{} : _items.map(idOf).toSet();
        _items.addAll(
          page.items.where((row) => idOf == null || ids.add(idOf(row))),
        );
        _cursor = page.cursor;
        _more = page.hasMore;
      });
      final watch = widget.watchPage;
      final idOf = widget.idOf;
      if (watch != null && idOf != null && page.items.isNotEmpty) {
        _subscriptions.add(
          watch(page.items).listen(
            (rows) {
              if (!mounted || generation != _generation) return;
              final updates = {for (final row in rows) idOf(row): row};
              setState(() {
                for (var i = 0; i < _items.length; i++) {
                  final updated = updates[idOf(_items[i])];
                  if (updated != null) {
                    _items[i] = updated;
                  }
                }
                _liveError = null;
              });
            },
            onError: (Object error) {
              if (mounted && generation == _generation) {
                setState(() => _liveError = error);
              }
            },
          ),
        );
      }
      // Side effects belong to data arrival, never widget rebuilds.
      try {
        await widget.onLoaded?.call(page.items);
      } catch (_) {
        /* Retry on refresh. */
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _items.isEmpty && widget.header == null) {
      return const LoadingState();
    }
    if (_error != null && _items.isEmpty && widget.header == null) {
      return ErrorState(message: operationError(_error!), onRetry: _fetch);
    }
    final visible = widget.transform?.call(List.of(_items)) ?? _items;
    return RefreshIndicator(
      onRefresh: _reset,
      child: ListView(
        children: [
          if (widget.header != null) _PagedHeader(child: widget.header!),
          if (_busy && _items.isEmpty) const LoadingState(),
          if (_liveError != null)
            const Text(
              'Pembaruan stok terhenti. Muat ulang untuk mencoba lagi.',
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${visible.length} ditampilkan dari ${_items.length} data dimuat. Bukan jumlah global.',
            ),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Belum ada data yang sesuai. Ubah filter atau muat halaman berikutnya.',
              ),
            ),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: widget.itemBuilder(item),
            ),
          if (_error != null) Text(operationError(_error!)),
          if (_more || _error != null)
            OutlinedButton(
              onPressed: _busy ? null : _fetch,
              child: Text(
                _busy
                    ? 'Memuat...'
                    : _error != null
                    ? 'Coba lagi'
                    : 'Muat berikutnya',
              ),
            ),
          if (!_more) const Center(child: Text('Akhir data')),
        ],
      ),
    );
  }
}

/// Keep filter text, selections and expansion state when a long list scrolls
/// its header out of view. State still belongs to this page/account instance.
class _PagedHeader extends StatefulWidget {
  const _PagedHeader({required this.child});
  final Widget child;
  @override
  State<_PagedHeader> createState() => _PagedHeaderState();
}

class _PagedHeaderState extends State<_PagedHeader>
    with AutomaticKeepAliveClientMixin<_PagedHeader> {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
