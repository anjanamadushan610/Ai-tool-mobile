import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'state.dart';
import 'util.dart';

/// Tap to speak into a text field; tap again to stop. Uses the phone's speech service
/// (Sinhala when the app is in Sinhala, English otherwise). Spoken words are appended to the text.
class MicButton extends StatefulWidget {
  const MicButton({super.key, required this.controller, this.enabled = true});
  final TextEditingController controller;
  final bool enabled;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  static final SpeechToText _stt = SpeechToText();
  static bool? _ready;
  bool _listening = false;
  String _base = '';

  Future<void> _toggle() async {
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _ready ??= await _stt.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (_ready != true) {
      if (mounted) toast(context, 'Voice input is not available on this phone.');
      return;
    }
    if (!mounted) return;
    final si = AppScope.read(context).locale.languageCode == 'si';
    final locales = await _stt.locales();
    final wanted = si ? 'si' : 'en';
    final localeId = locales.where((l) => l.localeId.toLowerCase().startsWith(wanted)).map((l) => l.localeId).firstOrNull;
    if (si && localeId == null && mounted) {
      toast(context, 'සිංහල voice එක මේ phone එකේ නැහැ. English වලින් කතා කරන්න, නැත්නම් Google voice typing එකට සිංහල එකතු කරන්න.');
    }
    _base = widget.controller.text.trimRight();
    setState(() => _listening = true);
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        final words = r.recognizedWords;
        final text = _base.isEmpty ? words : '$_base $words';
        widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      },
    );
  }

  @override
  void dispose() {
    if (_listening) _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Stop' : 'Speak',
      onPressed: widget.enabled ? _toggle : null,
      icon: Icon(_listening ? Icons.stop_circle : Icons.mic_none, color: _listening ? Colors.red : null),
    );
  }
}
