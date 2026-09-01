class Grader {
  static String normalize(List<String> chosen) {
    final list = chosen.map((e) => e.toUpperCase()).toList()..sort();
    return list.join();
  }

  static String normalizeJoined(List<String> chosen) {
    final list = chosen.map((e) => e.toUpperCase()).toList()..sort();
    return list.join();
  }

  static String normalizeJudge(bool chosen) => chosen ? 'T' : 'F';

  static bool isCorrect({required List<String> chosen, required String answer}) {
    return normalizeJoined(chosen) == answer.toUpperCase();
  }

  static bool isCorrectJudge({required bool chosen, required String answer}) {
    return normalizeJudge(chosen) == answer.toUpperCase();
  }

  static String display(String answer) {
    switch (answer.toUpperCase()) {
      case 'T':
        return '正确';
      case 'F':
        return '错误';
      default:
        return answer.toUpperCase();
    }
  }
}
