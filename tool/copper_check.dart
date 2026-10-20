// ignore_for_file: avoid_print
import 'dart:math' as math;

double channel(int c) {
  final v = c / 255.0;
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double lum(List<int> c) => 0.2126 * channel(c[0]) + 0.7152 * channel(c[1]) + 0.0722 * channel(c[2]);

double dist(List<int> a, List<int> b) {
  final dr = (a[0] - b[0]).toDouble(), dg = (a[1] - b[1]).toDouble(), db = (a[2] - b[2]).toDouble();
  return math.sqrt(dr * dr + dg * dg + db * db);
}

List<int> hex(int v) => [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

// name: [dark, mid, bright, highlight]. Two sets, both from the owner on 2026-10-11.
const setA = <String, List<int>>{
  '铜    ': [0x4B271B, 0xB87333, 0xEFA85D, 0xFFF0CE],
  '古铜  ': [0x292119, 0x755437, 0xB68D5A, 0xEFD6A2],
  '亮红铜': [0x421B1C, 0xE45A43, 0xFF9B78, 0xFFE0CF],
  '黄铜  ': [0x352509, 0xC99F26, 0xF3CD55, 0xFFF2B7],
  '白铜  ': [0x28333A, 0xC3CED3, 0xEAF3F5, 0xFFFFFF],
  '铜紫  ': [0x24182F, 0x70459B, 0xB989DF, 0xF3D8FF],
  '铜绿  ': [0x0C2F29, 0x218A68, 0x68D2A0, 0xD8FFE9],
  '铜蓝  ': [0x0A1934, 0x23488D, 0x4D9DD5, 0xD8F3FF],
  '铜黑  ': [0x030608, 0x252D31, 0x697A80, 0xDEE5E4],
};

/// The set with pigment identities: PY184, PV23, PG7, PB15:3, TiO2, Cu2O.
const setB = <String, List<int>>{
  '铜    ': [0x49251D, 0xB46B42, 0xE8A477, 0xFFE2C7],
  '古铜  ': [0x34231A, 0x76543A, 0xB98C54, 0xE7D3AA],
  '亮红铜': [0x481B20, 0xA83B31, 0xE7654E, 0xFFD4BE],
  '黄铜  ': [0x513A12, 0xB78D24, 0xE8C34C, 0xFFF0B4],
  '白铜  ': [0x37424B, 0xBAC6CB, 0xEDF2F2, 0xFFFFFF],
  '铜紫  ': [0x22162F, 0x7042A2, 0xBB89E9, 0xF5DFFF],
  '铜绿  ': [0x05362E, 0x007D5D, 0x31C69B, 0xD7FFEB],
  '铜蓝  ': [0x061D37, 0x075C9A, 0x3CA9E0, 0xDDF5FF],
  '铜黑  ': [0x020406, 0x232B30, 0x6C7B81, 0xE2E9E9],
};

const wine = 0x3A1219;

List<int> raisedOf(List<int> ground) {
  final target = lum(ground) + 0.02;
  var best = ground;
  var bestGap = 1e9;
  for (final k in [1.2, 1.4, 1.6, 1.8, 2.0, 2.4, 2.8, 3.2, 3.8, 4.4]) {
    final c = [for (final ch in ground) math.min(255, (ch * k).round())];
    final gap = (lum(c) - target).abs();
    if (gap < bestGap) { bestGap = gap; best = c; }
  }
  return best;
}

String row(String name, List<int> ramp) {
  final ground = hex(ramp[0]);
  final sr = raisedOf(ground);
  final seen = 3.0 * (lum(sr) + 0.05) - 0.05;
  final text = 4.5 * (lum(sr) + 0.05) - 0.05;
  final steps = ramp.map(hex).toList();
  final seenCount = steps.where((c) => lum(c) >= seen).length;
  final textCount = steps.where((c) => lum(c) >= text).length;
  final d = dist(ground, hex(wine));
  return '$name  L=${lum(ground).toStringAsFixed(3)}  raised=${lum(sr).toStringAsFixed(3)}  '
      'seen $seenCount/4  text $textCount/4  vs酒红 ${d.toStringAsFixed(1)}  '
      '${d >= 27 ? "safe" : (d >= 22 ? "marginal" : "refused")}';
}

void main() {
  print('=== set A (the first nine families) ===');
  for (final e in setA.entries) {
    print(row(e.key, e.value));
  }
  print('');
  print('=== set B (with pigment identities) ===');
  for (final e in setB.entries) {
    print(row(e.key, e.value));
  }
  print('');
  print('=== where the two disagree ===');
  for (final k in setA.keys) {
    final a = setA[k]!, b = setB[k]!;
    final changes = <String>[];
    const labels = ['dark', 'mid', 'bright', 'highlight'];
    for (var i = 0; i < 4; i++) {
      if (a[i] != b[i]) {
        final da = lum(hex(a[i])), db = lum(hex(b[i]));
        final sign = db > da ? 'lighter' : 'darker';
        changes.add('$labels[$i] $sign by ${(db - da).abs().toStringAsFixed(3)}');
      }
    }
    if (changes.isNotEmpty) print('$k  ${changes.join("; ")}');
  }
}
