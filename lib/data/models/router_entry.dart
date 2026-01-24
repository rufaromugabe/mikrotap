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
}

