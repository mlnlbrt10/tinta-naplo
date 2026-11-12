import 'generic.dart';

class Subject extends NameUid {
  final NameUidDesc category;
  final int sortIndex;

  Subject({
    required super.uid,
    required super.name,
    required this.category,
    required this.sortIndex,
  });

  @override
  Map<String, dynamic> toJson() => {
        'Uid': uid,
        'Nev': name,
        'Kategoria': category.toJson(),
        'SortIndex': sortIndex,
      };

  factory Subject.fromJson(Map<String, dynamic> json) {
    final uid = (json['Uid'] ?? '').toString();
    final name = (json['Nev'] ?? '').toString();
    return Subject(
      uid: uid,
      name: name,
      category: json.nameUidDesc('Kategoria') ??
          NameUidDesc(uid: uid, name: name, description: name),
      sortIndex: (json['SortIndex'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'Subject('
        'uid: "$uid", '
        'name: "$name", '
        'category: $category, '
        'sortIndex: $sortIndex, '
        ')';
  }
}
