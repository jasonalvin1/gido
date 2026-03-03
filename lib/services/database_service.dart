import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/memo_model.dart';

class DatabaseService {
  static Database? _database;
  static Future<Database>? _initFuture; // 추가: 중복 초기화 방지용 Future 캐시

  Future<Database> get database async {
    if (_database != null) return _database!;
    // 이미 초기화 중이면 같은 Future를 공유하여 중복 openDatabase 호출 방지
    _initFuture ??= _initDB();
    _database = await _initFuture!;
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'gido.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      // ─────────────────────────────────────────────────────────────────
      // onOpen: DB가 완전히 열린 후 실행 (onCreate/onUpgrade 이후)
      //   • Foreign Keys만 활성화 — ON DELETE CASCADE 정상 동작 보장
      //   • WAL PRAGMA는 onConfigure 단계에서 충돌을 일으킬 수 있어 제거
      // ─────────────────────────────────────────────────────────────────
      onOpen: _onOpenDB,
    );
  }

  /// DB가 완전히 열린 뒤 외래키만 활성화 (안정적인 최소 설정)
  Future<void> _onOpenDB(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    // IF NOT EXISTS로 혹시 모를 중복 생성 방지
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        fields TEXT NOT NULL,
        isDefault INTEGER DEFAULT 0,
        sortOrder INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memos(
        id TEXT PRIMARY KEY,
        categoryId TEXT NOT NULL,
        title TEXT NOT NULL,
        isDone INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_fields(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        memoId TEXT NOT NULL,
        fieldName TEXT NOT NULL,
        fieldValue TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (memoId) REFERENCES memos(id) ON DELETE CASCADE
      )
    ''');

    for (final cat in Category.defaults()) {
      await db.insert('categories', cat.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // onUpgrade: 버전이 올라갈 때만 실행. 기존 데이터는 절대 삭제하지 않습니다.
  //
  // 규칙:
  //   • 각 마이그레이션 블록은 반드시 `if (oldVersion < X)` 형태로 작성
  //   • 새 컬럼 추가 시 ALTER TABLE 사용 (테이블 재생성 금지)
  //   • 새 테이블 추가 시 CREATE TABLE IF NOT EXISTS 사용
  //   • 전체 블록을 트랜잭션으로 감싸 실패 시 롤백 보장
  //
  // 다음 버전(v4) 추가 예시:
  //   if (oldVersion < 4) {
  //     await db.execute('ALTER TABLE memos ADD COLUMN isPinned INTEGER DEFAULT 0');
  //   }
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    await db.transaction((txn) async {
      // v1 → v2: 은행/계좌 카테고리 fields에서 카드비번 제거
      if (oldVersion < 2) {
        final maps = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: ['bank'],
        );
        if (maps.isNotEmpty) {
          final fields = (maps.first['fields'] as String).split('||');
          final updatedFields = fields.where((f) => f != '카드비번').toList();
          await txn.update(
            'categories',
            {'fields': updatedFields.join('||')},
            where: 'id = ?',
            whereArgs: ['bank'],
          );
        }
      }

      // v2 → v3: 기본 카테고리 아이콘을 3D 이미지 경로로 업데이트
      if (oldVersion < 3) {
        final iconUpdates = {
          'bank':     'assets/icons/bank.png',
          'site':     'assets/icons/site.png',
          'birthday': 'assets/icons/birthday.png',
          'church':   'assets/icons/church.png',
          'todo':     'assets/icons/todo.png',
        };
        for (final entry in iconUpdates.entries) {
          await txn.update(
            'categories',
            {'icon': entry.value},
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }
      }

      // ── 향후 버전 마이그레이션은 여기에 추가 ──
      // if (oldVersion < 4) { ... }
      // if (oldVersion < 5) { ... }
    });
  }

  // ========== 카테고리 CRUD ==========

  Future<void> updateCategoryIcon(String id, String icon) async {
    final db = await database;
    await db.update(
      'categories',
      {'icon': icon},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Category>> getCategories() async {
    final db = await database;
    final maps = await db.query('categories', orderBy: 'sortOrder ASC');
    return maps.map((m) => Category.fromMap(m)).toList();
  }

  Future<Category?> getCategory(String id) async {
    final db = await database;
    final maps = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Category.fromMap(maps.first);
  }

  Future<void> insertCategory(Category category) async {
    final db = await database;
    await db.insert('categories', category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    final memos = await db.query('memos', where: 'categoryId = ?', whereArgs: [id]);
    for (final memo in memos) {
      await db.delete('memo_fields', where: 'memoId = ?', whereArgs: [memo['id']]);
    }
    await db.delete('memos', where: 'categoryId = ?', whereArgs: [id]);
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateCategory(Category category) async {
    final db = await database;
    await db.update('categories', category.toMap(),
        where: 'id = ?', whereArgs: [category.id]);
  }

  // ========== 메모 CRUD ==========

  Future<List<Memo>> getMemosByCategory(String categoryId) async {
    final db = await database;
    final memoMaps = await db.query(
      'memos',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'updatedAt DESC',
    );

    List<Memo> memos = [];
    for (final memoMap in memoMaps) {
      final fieldMaps = await db.query(
        'memo_fields',
        where: 'memoId = ?',
        whereArgs: [memoMap['id']],
      );
      final fieldData = <String, String>{};
      for (final f in fieldMaps) {
        fieldData[f['fieldName'] as String] = f['fieldValue'] as String;
      }
      memos.add(Memo.fromMap(memoMap, fieldData));
    }
    return memos;
  }

  Future<List<Memo>> getAllMemos() async {
    final db = await database;
    final memoMaps = await db.query('memos', orderBy: 'updatedAt DESC');

    List<Memo> memos = [];
    for (final memoMap in memoMaps) {
      final fieldMaps = await db.query(
        'memo_fields',
        where: 'memoId = ?',
        whereArgs: [memoMap['id']],
      );
      final fieldData = <String, String>{};
      for (final f in fieldMaps) {
        fieldData[f['fieldName'] as String] = f['fieldValue'] as String;
      }
      memos.add(Memo.fromMap(memoMap, fieldData));
    }
    return memos;
  }

  Future<void> insertMemo(Memo memo) async {
    final db = await database;
    await db.insert('memos', memo.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    for (final entry in memo.data.entries) {
      await db.insert('memo_fields', {
        'memoId': memo.id,
        'fieldName': entry.key,
        'fieldValue': entry.value,
      });
    }
  }

  Future<void> updateMemo(Memo memo) async {
    final db = await database;
    await db.update('memos', memo.toMap(),
        where: 'id = ?', whereArgs: [memo.id]);

    await db.delete('memo_fields', where: 'memoId = ?', whereArgs: [memo.id]);
    for (final entry in memo.data.entries) {
      await db.insert('memo_fields', {
        'memoId': memo.id,
        'fieldName': entry.key,
        'fieldValue': entry.value,
      });
    }
  }

  Future<void> toggleMemoDone(String memoId, bool isDone) async {
    final db = await database;
    await db.update(
      'memos',
      {'isDone': isDone ? 1 : 0, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [memoId],
    );
  }

  Future<void> deleteMemo(String memoId) async {
    final db = await database;
    await db.delete('memo_fields', where: 'memoId = ?', whereArgs: [memoId]);
    await db.delete('memos', where: 'id = ?', whereArgs: [memoId]);
  }

  // ========== 검색 ==========

  Future<List<Memo>> searchMemos(String query) async {
    final db = await database;
    final q = '%$query%';

    final titleResults = await db.query(
      'memos',
      where: 'title LIKE ?',
      whereArgs: [q],
    );

    final fieldResults = await db.rawQuery('''
      SELECT DISTINCT m.* FROM memos m
      INNER JOIN memo_fields mf ON m.id = mf.memoId
      WHERE mf.fieldValue LIKE ?
    ''', [q]);

    final allResults = <String, Map<String, dynamic>>{};
    for (final r in [...titleResults, ...fieldResults]) {
      allResults[r['id'] as String] = r;
    }

    List<Memo> memos = [];
    for (final memoMap in allResults.values) {
      final fieldMaps = await db.query(
        'memo_fields',
        where: 'memoId = ?',
        whereArgs: [memoMap['id']],
      );
      final fieldData = <String, String>{};
      for (final f in fieldMaps) {
        fieldData[f['fieldName'] as String] = f['fieldValue'] as String;
      }
      memos.add(Memo.fromMap(memoMap, fieldData));
    }

    memos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return memos;
  }

  Future<int> getMemoCount(String categoryId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM memos WHERE categoryId = ?',
      [categoryId],
    );
    return result.first['cnt'] as int;
  }

  // ========== 카테고리 간 메모 이동 ==========

  /// ID 기반으로 메모의 카테고리를 변경하고 필드 데이터를 교체
  Future<void> moveMemo(String memoId, String newCategoryId, Map<String, String> newData) async {
    final db = await database;
    await db.update(
      'memos',
      {
        'categoryId': newCategoryId,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [memoId],
    );
    // 기존 필드 삭제 후 새 필드 삽입
    await db.delete('memo_fields', where: 'memoId = ?', whereArgs: [memoId]);
    for (final entry in newData.entries) {
      if (entry.value.isEmpty) continue;
      await db.insert('memo_fields', {
        'memoId': memoId,
        'fieldName': entry.key,
        'fieldValue': entry.value,
      });
    }
  }

  // ========== 유사 메모 감지 (중복 방지) ==========

  /// 같은 카테고리에서 제목 또는 필드 값이 유사한 메모 반환 (최대 3개)
  Future<List<Memo>> getSimilarMemos(String categoryId, String query, {String? excludeId}) async {
    if (query.trim().length < 2) return [];
    final db = await database;
    final q = '%${query.trim()}%';

    final titleResults = await db.query(
      'memos',
      where: excludeId != null
          ? 'categoryId = ? AND title LIKE ? AND id != ?'
          : 'categoryId = ? AND title LIKE ?',
      whereArgs: excludeId != null ? [categoryId, q, excludeId] : [categoryId, q],
      limit: 3,
    );

    final fieldQuery = excludeId != null
        ? '''SELECT DISTINCT m.* FROM memos m
             INNER JOIN memo_fields mf ON m.id = mf.memoId
             WHERE m.categoryId = ? AND mf.fieldValue LIKE ? AND m.id != ?
             LIMIT 3'''
        : '''SELECT DISTINCT m.* FROM memos m
             INNER JOIN memo_fields mf ON m.id = mf.memoId
             WHERE m.categoryId = ? AND mf.fieldValue LIKE ?
             LIMIT 3''';
    final fieldArgs = excludeId != null ? [categoryId, q, excludeId] : [categoryId, q];
    final fieldResults = await db.rawQuery(fieldQuery, fieldArgs);

    final allResults = <String, Map<String, dynamic>>{};
    for (final r in [...titleResults, ...fieldResults]) {
      allResults[r['id'] as String] = r;
    }

    final List<Memo> memos = [];
    for (final memoMap in allResults.values.take(3)) {
      final fieldMaps = await db.query(
        'memo_fields',
        where: 'memoId = ?',
        whereArgs: [memoMap['id']],
      );
      final fieldData = <String, String>{};
      for (final f in fieldMaps) {
        fieldData[f['fieldName'] as String] = f['fieldValue'] as String;
      }
      memos.add(Memo.fromMap(memoMap, fieldData));
    }
    return memos;
  }
}