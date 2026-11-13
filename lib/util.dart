import 'package:flutter/material.dart';

import 'api.dart';

/// The server stores UTC; people read Sri Lanka time (UTC+05:30, no daylight saving).
DateTime colombo(String iso) {
  final s = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
  return DateTime.parse(s).toUtc().add(const Duration(hours: 5, minutes: 30));
}

String two(int n) => n.toString().padLeft(2, '0');

String fmt(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = colombo(iso);
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String ago(String? iso) {
  if (iso == null) return '—';
  final s = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
  final diff = DateTime.now().toUtc().difference(DateTime.parse(s).toUtc());
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 48) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

const statusColors = {
  'queued': Colors.blue,
  'running': Colors.indigo,
  'done': Colors.green,
  'failed': Colors.red,
  'stopped': Colors.orange,
};

Widget statusChip(String status) => Chip(
      label: Text(status, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: statusColors[status] ?? Colors.grey),
    );

void toast(BuildContext context, Object message) {
  final text = message is ApiException ? message.message : message.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
