import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'i18n.dart';
import 'state.dart';
import 'util.dart';

/// Screenshots for a prompt: pick from the gallery, upload, keep the ids (max 5, 8 MB each).
class Attachments extends ChangeNotifier {
  final List<(String name, String id)> items = [];

  Future<void> pick(BuildContext context) async {
    final api = AppScope.read(context).api;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2400, limit: 5);
    for (final f in picked.take(5 - items.length)) {
      try {
        final bytes = await f.readAsBytes();
        if (bytes.length > 8 * 1024 * 1024) throw Exception('${f.name}: images up to 8 MB');
        final r = await api.post('/tasks/uploads', {'filename': f.name, 'data_b64': base64Encode(bytes)});
        items.add((f.name, r['id'] as String));
        notifyListeners();
      } catch (e) {
        if (context.mounted) toast(context, e);
      }
    }
  }

  List<String> get ids => [for (final i in items) i.$2];

  void remove(String id) {
    items.removeWhere((x) => x.$2 == id);
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }
}

class AttachRow extends StatelessWidget {
  const AttachRow({super.key, required this.attachments, this.enabled = true});
  final Attachments attachments;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: attachments,
      builder: (context, _) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          onPressed: enabled && attachments.items.length < 5 ? () => attachments.pick(context) : null,
          icon: const Icon(Icons.attach_file),
          label: Text(tr(context, 'attach')),
        ),
        for (final (name, id) in attachments.items)
          InputChip(
            label: Text(name, overflow: TextOverflow.ellipsis),
            onDeleted: () => attachments.remove(id),
          ),
      ]),
    );
  }
}
