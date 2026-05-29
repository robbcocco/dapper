class LidarrInstance {
  const LidarrInstance({
    required this.id,
    required this.name,
    required this.url,
    this.defaultRootFolderId,
    this.defaultRootFolderPath,
    this.defaultQualityProfileId,
    this.defaultQualityProfileName,
  });

  final String id;
  final String name;
  final String url;
  final int? defaultRootFolderId;
  final String? defaultRootFolderPath;
  final int? defaultQualityProfileId;
  final String? defaultQualityProfileName;

  LidarrInstance copyWith({
    String? name,
    String? url,
    int? defaultRootFolderId,
    String? defaultRootFolderPath,
    int? defaultQualityProfileId,
    String? defaultQualityProfileName,
  }) =>
      LidarrInstance(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        defaultRootFolderId: defaultRootFolderId ?? this.defaultRootFolderId,
        defaultRootFolderPath: defaultRootFolderPath ?? this.defaultRootFolderPath,
        defaultQualityProfileId: defaultQualityProfileId ?? this.defaultQualityProfileId,
        defaultQualityProfileName: defaultQualityProfileName ?? this.defaultQualityProfileName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (defaultRootFolderId != null) 'defaultRootFolderId': defaultRootFolderId,
        if (defaultRootFolderPath != null) 'defaultRootFolderPath': defaultRootFolderPath,
        if (defaultQualityProfileId != null) 'defaultQualityProfileId': defaultQualityProfileId,
        if (defaultQualityProfileName != null) 'defaultQualityProfileName': defaultQualityProfileName,
      };

  factory LidarrInstance.fromJson(Map<String, dynamic> json) => LidarrInstance(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        defaultRootFolderId: json['defaultRootFolderId'] as int?,
        defaultRootFolderPath: json['defaultRootFolderPath'] as String?,
        defaultQualityProfileId: json['defaultQualityProfileId'] as int?,
        defaultQualityProfileName: json['defaultQualityProfileName'] as String?,
      );
}
