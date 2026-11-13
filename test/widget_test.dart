import 'package:flutter_test/flutter_test.dart';
import 'package:sribees_ai/screens/task_view.dart';
import 'package:sribees_ai/util.dart';

void main() {
  test('tool summary shows the command for Bash and the path for file tools', () {
    expect(toolSummary('Bash', {'command': 'pytest -q'}), 'pytest -q');
    expect(toolSummary('Edit', {'file_path': 'app/main.py', 'old_string': 'x'}), 'app/main.py');
    expect(toolSummary('Grep', {'pattern': 'TODO'}), 'TODO');
  });

  test('times are shown in Sri Lanka time', () {
    expect(fmt('2026-11-13T12:00:00+00:00'), '2026-11-13 17:30');
    expect(fmt('2026-11-13T20:00:00'), '2026-11-14 01:30');
  });
}
