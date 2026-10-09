import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Opens and exposes the on-device boxes. Records are stored as JSON strings,
/// which keeps the schema explicit and works the same on mobile and web.
class LocalStore {
  LocalStore._(this.settings, this.receipts, this.attachments, this.reminders, this.outbox, this.meta);

  final Box<String> settings;
  final Box<String> receipts;
  final LazyBox<Uint8List> attachments;
  final Box<String> reminders;
  final Box<String> outbox;
  final Box<String> meta;

  static Future<LocalStore> open({String? path}) async {
    if (path == null) {
      await Hive.initFlutter('keepr');
    } else {
      Hive.init(path);
    }
    return LocalStore._(
      await Hive.openBox<String>('settings'),
      await Hive.openBox<String>('receipts'),
      await Hive.openLazyBox<Uint8List>('attachments'),
      await Hive.openBox<String>('reminders'),
      await Hive.openBox<String>('outbox'),
      await Hive.openBox<String>('meta'),
    );
  }

  /// Wipes everything (sign out / delete account).
  Future<void> clearAll({bool keepSettings = true}) async {
    await receipts.clear();
    await attachments.clear();
    await reminders.clear();
    await outbox.clear();
    await meta.clear();
    if (!keepSettings) await settings.clear();
  }

  static Map<String, dynamic> decode(String raw) => (jsonDecode(raw) as Map).cast<String, dynamic>();

  static String encode(Map<String, dynamic> json) => jsonEncode(json);
}

/// Emits [read] immediately and again after every change to [box].
Stream<T> watchBox<T>(Box<dynamic> box, T Function() read) async* {
  yield read();
  await for (final _ in box.watch()) {
    yield read();
  }
}
