class NavidromeServer {
  const NavidromeServer({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
  });

  final String id;
  final String name;
  final String url;
  final String username;

  NavidromeServer copyWith({String? name, String? url, String? username}) =>
      NavidromeServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        username: username ?? this.username,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
      };

  factory NavidromeServer.fromJson(Map<String, dynamic> json) =>
      NavidromeServer(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        username: json['username'] as String,
      );
}
