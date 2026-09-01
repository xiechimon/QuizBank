// W3 deprecated: bucket logic kept for tests, Today now uses StudyCard queue
class DailyPlan {
  static const bucketSize = 39;
  static const bucketCount = 30;
  static const totalQuestions = bucketSize * bucketCount;

  static int bucketOf(int id) {
    final b = (id - 1) ~/ bucketSize;
    if (b < 0) return 0;
    if (b >= bucketCount) return bucketCount - 1;
    return b;
  }

  static List<int> idsOf(int bucket) {
    final b = bucket.clamp(0, bucketCount - 1);
    final start = b * bucketSize + 1;
    final end = (start + bucketSize).clamp(0, totalQuestions + 1);
    return [for (var i = start; i < end; i++) i];
  }

  static int currentDay(Set<int> answeredIds) {
    for (var b = 0; b < bucketCount; b++) {
      final ids = idsOf(b);
      if (ids.any((id) => !answeredIds.contains(id))) return b + 1;
    }
    return bucketCount;
  }

  static List<int> reviewQueue(List<DueItem> due, int cap) {
    final sorted = List<DueItem>.from(due);
    sorted.sort((a, b) {
      if (a.next != b.next) return a.next.compareTo(b.next);
      if (a.wrongs != b.wrongs) return b.wrongs.compareTo(a.wrongs);
      return a.id.compareTo(b.id);
    });
    return sorted.take(cap.clamp(0, sorted.length)).map((e) => e.id).toList();
  }

  static List<int> stableShuffle(List<int> ids, int seed) {
    var rng = SplitMix64(seed: (seed & 0xFFFFFFFFFFFFFFFF) + 0x9E3779B97F4A7C15);
    final arr = List<int>.from(ids);
    for (var i = arr.length - 1; i > 0; i--) {
      final j = (rng.next() % (i + 1)).toInt();
      final tmp = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
    return arr;
  }
}

class DueItem {
  final int id;
  final DateTime next;
  final int wrongs;
  DueItem({required this.id, required this.next, required this.wrongs});
}

class SplitMix64 {
  int _state;
  SplitMix64({required int seed}) : _state = seed & 0xFFFFFFFFFFFFFFFF;

  int next() {
    _state = (_state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    var z = _state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9 & 0xFFFFFFFFFFFFFFFF;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB & 0xFFFFFFFFFFFFFFFF;
    return (z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF;
  }
}
