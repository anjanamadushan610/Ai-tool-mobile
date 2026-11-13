import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const baseUrl = 'https://ai.sribees.com/api';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Same API and cookies as the web app. The session and CSRF cookies live in secure storage.
class Api {
  Api() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      _cookies ??= await _load();
      if (_cookies!.isNotEmpty) {
        o.headers['Cookie'] = _cookies!.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
      final csrf = _cookies!['sbai_csrf'];
      if (o.method != 'GET' && csrf != null) o.headers['X-CSRF-Token'] = csrf;
      h.next(o);
    }, onResponse: (r, h) async {
      await _keep(r.headers['set-cookie']);
      h.next(r);
    }, onError: (e, h) async {
      await _keep(e.response?.headers['set-cookie']);
      h.next(e);
    }));
  }

  final _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': 'SriBeesAI-Android'},
  ));
  final _store = const FlutterSecureStorage();
  Map<String, String>? _cookies;
  void Function()? onUnauthorized;

  Future<Map<String, String>> _load() async {
    final out = <String, String>{};
    for (final k in ['sbai_session', 'sbai_csrf']) {
      final v = await _store.read(key: k);
      if (v != null) out[k] = v;
    }
    return out;
  }

  Future<void> _keep(List<String>? setCookies) async {
    if (setCookies == null) return;
    _cookies ??= await _load();
    for (final sc in setCookies) {
      final pair = sc.split(';').first;
      final i = pair.indexOf('=');
      if (i < 1) continue;
      final k = pair.substring(0, i).trim();
      final v = pair.substring(i + 1).trim();
      if (k != 'sbai_session' && k != 'sbai_csrf') continue;
      final expired = sc.toLowerCase().contains('max-age=0') || v.isEmpty || v == '""';
      if (expired) {
        _cookies!.remove(k);
        await _store.delete(key: k);
      } else {
        _cookies![k] = v;
        await _store.write(key: k, value: v);
      }
    }
  }

  Future<void> clear() async {
    _cookies = {};
    await _store.delete(key: 'sbai_session');
    await _store.delete(key: 'sbai_csrf');
  }

  Future<dynamic> call(String method, String path, {Object? body}) async {
    try {
      final r = await _dio.request(path, data: body, options: Options(method: method));
      return r.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final detail = data is Map && data['detail'] is String
          ? data['detail'] as String
          : status == 0
              ? 'No connection to ai.sribees.com'
              : 'Request failed ($status)';
      if (status == 401 && path != '/auth/login') onUnauthorized?.call();
      throw ApiException(status, detail);
    }
  }

  Future<dynamic> get(String path) => call('GET', path);
  Future<dynamic> post(String path, [Object? body]) => call('POST', path, body: body ?? {});
  Future<dynamic> patch(String path, Object body) => call('PATCH', path, body: body);
  Future<dynamic> delete(String path) => call('DELETE', path);
}
