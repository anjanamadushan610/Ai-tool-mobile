import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/report.dart';
import 'screens/task_view.dart';
import 'state.dart';

/// Push notifications: "Claude needs your OK" and "task finished".
/// The payload carries only a task id and a short title; the app fetches the rest over the API.
class Push {
  static bool _ready = false;
  static String? _token;
  static GlobalKey<NavigatorState>? _nav;
  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel('tasks', 'Claude tasks',
      description: 'Approvals and finished tasks', importance: Importance.high);

  static Future<void> init(AppState state, GlobalKey<NavigatorState> nav) async {
    _nav = nav;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return; // No google-services.json in this build: the app works, just without push.
    }
    _ready = true;
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _local.show(
        id: m.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(_channel.id, _channel.name, importance: Importance.high, priority: Priority.high),
        ),
        payload: _target(m.data),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(_target(m.data)));
    final first = await FirebaseMessaging.instance.getInitialMessage();
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(_target(first.data)));
    }
  }

  /// "report" for the morning report, otherwise the task id (alerts open nothing special).
  static String? _target(Map<String, dynamic> data) => data['kind'] == 'report' ? 'report' : data['task_id'] as String?;

  static void _open(String? target) {
    if (target == 'report') {
      _nav?.currentState?.push(MaterialPageRoute(builder: (_) => const ReportScreen()));
      return;
    }
    final id = int.tryParse(target ?? '');
    if (id == null) return;
    _nav?.currentState?.push(MaterialPageRoute(builder: (_) => TaskViewScreen(id: id)));
  }

  /// Called once signed in: ask permission (Android 13+) and register this phone with the server.
  static Future<void> register(AppState state) async {
    if (!_ready || state.me == null) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      // getToken/onTokenRefresh still work; the newer register() flow is not adopted until tested on a phone.
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await state.api.post('/devices', {'token': _token, 'platform': 'android'});
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        state.api.post('/devices', {'token': t, 'platform': 'android'});
      });
    } catch (_) {}
  }

  static Future<void> unregister(AppState state) async {
    if (!_ready || _token == null) return;
    try {
      await state.api.call('DELETE', '/devices', body: {'token': _token});
    } catch (_) {}
  }
}
