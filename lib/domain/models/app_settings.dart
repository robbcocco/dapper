class AppSettings {
  const AppSettings({this.transferConcurrency = 4});
  final int transferConcurrency;

  AppSettings copyWith({int? transferConcurrency}) => AppSettings(
        transferConcurrency: transferConcurrency ?? this.transferConcurrency,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        transferConcurrency: (j['transferConcurrency'] as int?) ?? 4,
      );

  Map<String, dynamic> toJson() => {
        'transferConcurrency': transferConcurrency,
      };
}
