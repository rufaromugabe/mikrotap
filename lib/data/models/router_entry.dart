class RouterEntry {
  const RouterEntry({
    required this.id,
    required this.name,
    required this.host,
    this.macAddress,
    this.identity,
    this.boardName,
    this.platform,
    this.version,
    required this.createdAt,
    required this.updatedAt,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String host; // IPv4/hostname used to connect
  final String? macAddress;
  final String? identity;
  final String? boardName;
  final String? platform;
  final String? version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSeenAt;

  RouterEntry copyWith({
    String? id,
    String? name,
    String? host,
    String? macAddress,
    String? identity,
    String? boardName,
    String? platform,
    String? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSeenAt,
  }) {
    return RouterEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      macAddress: macAddress ?? this.macAddress,
      identity: identity ?? this.identity,
      boardName: boardName ?? this.boardName,
      platform: platform ?? this.platform,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'host': host,
      'macAddress': macAddress,
      'identity': identity,
      'boardName': boardName,
      'platform': platform,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastSeenAt': lastSeenAt?.toIso8601String(),
    };
  }

  static RouterEntry fromMap(Map<String, dynamic> map) {
    DateTime parseDt(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return RouterEntry(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      host: (map['host'] as String?) ?? '',
      macAddress: map['macAddress'] as String?,
      identity: map['identity'] as String?,
      boardName: map['boardName'] as String?,
      platform: map['platform'] as String?,
      version: map['version'] as String?,
      createdAt: parseDt(map['createdAt']),
      updatedAt: parseDt(map['updatedAt']),
      lastSeenAt: map['lastSeenAt'] == null ? null : parseDt(map['lastSeenAt']),
    );
  }
}

