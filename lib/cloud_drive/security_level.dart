enum SecurityLevel { level1, level2 }

extension SecurityLevelJson on SecurityLevel {
  String toJson() {
    return switch (this) {
      SecurityLevel.level1 => 'level1',
      SecurityLevel.level2 => 'level2',
    };
  }

  static SecurityLevel? fromJson(String? value) {
    return switch (value) {
      'level1' => SecurityLevel.level1,
      'level2' => SecurityLevel.level2,
      _ => null,
    };
  }
}

