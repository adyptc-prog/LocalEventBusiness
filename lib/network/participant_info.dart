/// Un participant al evenimentului curent, așa cum e afișat organizatorului
/// pe ecranul de moderare (`ParticipantsScreen`) — agregat peste toate
/// camerele, nu specific uneia singure (spre deosebire de `RoomParticipant`).
class ParticipantInfo {
  final String profileId;
  final String name;
  final String? roomCode;
  final String? activityTitle;
  final bool connected;
  final bool blocked;
  final bool muted;

  const ParticipantInfo({
    required this.profileId,
    required this.name,
    required this.roomCode,
    required this.activityTitle,
    required this.connected,
    required this.blocked,
    required this.muted,
  });

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'name': name,
        'roomCode': roomCode,
        'activityTitle': activityTitle,
        'connected': connected,
        'blocked': blocked,
        'muted': muted,
      };

  factory ParticipantInfo.fromJson(Map<String, dynamic> json) => ParticipantInfo(
        profileId: json['profileId'] as String,
        name: json['name'] as String,
        roomCode: json['roomCode'] as String?,
        activityTitle: json['activityTitle'] as String?,
        connected: json['connected'] as bool,
        blocked: json['blocked'] as bool,
        muted: json['muted'] as bool? ?? false,
      );
}
