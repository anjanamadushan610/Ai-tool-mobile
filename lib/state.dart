import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Signed-in user, language and the shared API client.
class AppState extends ChangeNotifier {
  AppState() {
    api.onUnauthorized = () {
      if (me != null) {
        me = null;
        notifyListeners();
      }
    };
  }

  final api = Api();
  final _store = const FlutterSecureStorage();
  Map<String, dynamic>? me;
  bool loading = true;
  Locale locale = const Locale('en');

  Set<String> get perms => {...((me?['permissions'] as List?) ?? const []).cast<String>()};
  bool can(String p) => perms.contains(p);
  bool get isOwner => me?['role'] == 'owner';

  Future<void> boot() async {
    final lang = await _store.read(key: 'lang');
    if (lang == 'si') locale = const Locale('si');
    try {
      me = Map<String, dynamic>.from(await api.get('/auth/me'));
    } catch (_) {
      me = null;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final r = await api.post('/auth/login', {'username': username, 'password': password, 'remember': true});
    me = Map<String, dynamic>.from(r);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    await api.clear();
    me = null;
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    locale = Locale(code);
    await _store.write(key: 'lang', value: code);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
