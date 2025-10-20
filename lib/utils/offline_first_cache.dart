import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A widget that caches and displays data from a future.
///
/// It always shows the cached data first, and then updates with the fresh data
/// from the future.
class OfflineFirstCache<T> extends StatefulWidget {
  /// Creates a widget that caches and displays data from a future.
  const OfflineFirstCache({
    Key? key,
    required this.cacheKey,
    required this.future,
    required this.builder,
    this.deserializer,
    this.serializer,
  }) : super(key: key);

  /// The key to use for caching the data.
  final String cacheKey;

  /// The future to fetch the data from.
  final Future<T> future;

  /// The widget to build when the data is available.
  final Widget Function(BuildContext context, T data) builder;

  /// A function that deserializes the cached data.
  ///
  /// If the data is a primitive type, this is not needed.
  final T Function(String)? deserializer;

  /// A function that serializes the data to be cached.
  ///
  /// If the data is a primitive type, this is not needed.
  final String Function(T)? serializer;

  @override
  _OfflineFirstCacheState<T> createState() => _OfflineFirstCacheState<T>();
}

class _OfflineFirstCacheState<T> extends State<OfflineFirstCache<T>> {
  T? _data;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetchData();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(widget.cacheKey);
    if (cachedData != null) {
      setState(() {
        if (widget.deserializer != null) {
          _data = widget.deserializer!(cachedData);
        } else {
          _data = jsonDecode(cachedData) as T;
        }
      });
    }
  }

  Future<void> _fetchData() async {
    try {
      final data = await widget.future;
      setState(() {
        _data = data;
      });
      _saveCache(data);
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _saveCache(T data) async {
    final prefs = await SharedPreferences.getInstance();
    if (widget.serializer != null) {
      await prefs.setString(widget.cacheKey, widget.serializer!(data));
    } else {
      await prefs.setString(widget.cacheKey, jsonEncode(data));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, _data as T);
  }
}
