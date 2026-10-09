import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/entities/reminder.dart';
import '../domain/repositories/reminder_repository.dart';

/// Schedules reminders as OS notifications on Android and iOS. Notification
/// taps emit the deep link stored in the payload on [taps].
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();

  /// Deep links (e.g. `/receipt/<id>`) from tapped notifications.
  Stream<String> get taps => _taps.stream;

  /// Link that launched the app from a terminated state, if any.
  String? launchLink;

  static const _channel = AndroidNotificationDetails(
    'keepr_reminders',
    'Deadlines and warranties',
    channelDescription: 'Return window and warranty reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<LocalNotificationScheduler> create() async {
    final scheduler = LocalNotificationScheduler._(FlutterLocalNotificationsPlugin());
    if (!scheduler.isSupported) return scheduler;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await scheduler._plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final link = response.payload;
        if (link != null) scheduler._taps.add(link);
      },
    );
    final launch = await scheduler._plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      scheduler.launchLink = launch!.notificationResponse?.payload;
    }
    return scheduler;
  }

  @override
  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  @override
  Future<void> schedule(Reminder reminder) async {
    if (!isSupported) return;
    try {
      await _plugin.zonedSchedule(
        id: notificationId(reminder.id),
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.fireAt, tz.local),
        notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '/receipt/${reminder.receiptId}',
      );
    } catch (_) {
      // A missing permission must never break saving a receipt.
    }
  }

  @override
  Future<void> cancel(String reminderId) async {
    if (!isSupported) return;
    try {
      await _plugin.cancel(id: notificationId(reminderId));
    } catch (_) {}
  }

  /// Stable 31-bit FNV-1a hash (String.hashCode is not stable across runs).
  static int notificationId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}
