import 'package:uuid/uuid.dart';

class Category {
  final String id;
  final String name;
  final String icon;
  final String color; // hex color string
  final List<String> fields;
  final bool isDefault;
  final int sortOrder;

  Category({
    String? id,
    required this.name,
    required this.icon,
    required this.color,
    required this.fields,
    this.isDefault = false,
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  // 민감 정보 필드 (눈 아이콘 토글)
  static const sensitiveFields = ['비밀번호'];

  // 숫자 입력 필드
  static const numericFields = ['계좌번호', '전화번호'];

  // 날짜 선택 필드 (달력 UI 사용)
  static const dateFields = ['날짜'];

  // 날짜+시간 선택 필드 (달력 + 시간 UI 사용, 요일/시간 형식)
  static const dateTimeFields = ['요일/시간'];

  // 날짜+시간 선택 필드 (달력 + 시간 UI, 알람 예약용)
  // 저장 형식: 'yyyy년 M월 d일 HH:mm'
  static const alarmDateTimeFields = ['마감일'];

  bool isSensitiveField(String fieldName) {
    return sensitiveFields.contains(fieldName);
  }

  bool isNumericField(String fieldName) {
    return numericFields.contains(fieldName);
  }

  bool isDateField(String fieldName) {
    return dateFields.contains(fieldName);
  }

  bool isDateTimeField(String fieldName) {
    return dateTimeFields.contains(fieldName);
  }

  bool isAlarmDateTimeField(String fieldName) {
    return alarmDateTimeFields.contains(fieldName);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'fields': fields.join('||'),
      'isDefault': isDefault ? 1 : 0,
      'sortOrder': sortOrder,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
      color: map['color'],
      fields: (map['fields'] as String).split('||'),
      isDefault: map['isDefault'] == 1,
      sortOrder: map['sortOrder'] ?? 0,
    );
  }

  // 기본 카테고리들
  static List<Category> defaults() {
    return [
      Category(
        id: 'bank',
        name: '은행/계좌',
        icon: 'assets/icons/bank.png',
        color: '#2196F3',
        fields: ['은행명', '계좌번호', '비밀번호', '메모'],
        isDefault: true,
        sortOrder: 0,
      ),
      Category(
        id: 'site',
        name: '사이트/앱',
        icon: 'assets/icons/site.png',
        color: '#4CAF50',
        fields: ['사이트명', '아이디', '비밀번호', '웹주소', '메모'],
        isDefault: true,
        sortOrder: 1,
      ),
      Category(
        id: 'birthday',
        name: '생일/기념일',
        icon: 'assets/icons/birthday.png',
        color: '#E91E63',
        fields: ['이름', '날짜', '관계', '메모'],
        isDefault: true,
        sortOrder: 2,
      ),
      Category(
        id: 'church',
        name: '약속/모임',
        icon: 'assets/icons/church.png',
        color: '#9C27B0',
        fields: ['모임명', '요일/시간', '장소', '담당자', '전화번호', '메모'],
        isDefault: true,
        sortOrder: 3,
      ),
      Category(
        id: 'todo',
        name: '할일',
        icon: 'assets/icons/todo.png',
        color: '#FF9800',
        fields: ['할일', '마감일', '메모'],
        isDefault: true,
        sortOrder: 4,
      ),
    ];
  }
}

class Memo {
  final String id;
  final String categoryId;
  String title;
  Map<String, String> data;
  bool isDone;
  final DateTime createdAt;
  DateTime updatedAt;

  Memo({
    String? id,
    required this.categoryId,
    required this.title,
    required this.data,
    this.isDone = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryId': categoryId,
      'title': title,
      'isDone': isDone ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Memo.fromMap(Map<String, dynamic> map, Map<String, String> fieldData) {
    return Memo(
      id: map['id'],
      categoryId: map['categoryId'],
      title: map['title'],
      isDone: map['isDone'] == 1,
      data: fieldData,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
    );
  }
}