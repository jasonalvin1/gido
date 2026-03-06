import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/memo_model.dart';
import 'database_service.dart';

/// 백업 파일 정보 (RestoreScreen 미리보기용)
class BackupInfo {
  final String filePath;
  final String fileName;
  final String fileSizeStr;
  final int categoryCount;
  final int memoCount;
  final String dateStr;

  /// true이면 구버전 .gido 파일 → 복원 성공 후 재백업 권고
  final bool isLegacy;

  BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.fileSizeStr,
    required this.categoryCount,
    required this.memoCount,
    required this.dateStr,
    this.isLegacy = false,
  });
}

class BackupService {
  final DatabaseService _db = DatabaseService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _pinKey = 'gido_pin';
  static const int _pbkdf2Iterations = 100000;
  static const int _keyLength = 32; // AES-256
  static const int _saltLength = 16;
  static const int _ivLength = 12; // AES-GCM 권장 IV 크기

  // ──────────────────────────────────────────────────────────────────
  //  보안 저장소 헬퍼
  // ──────────────────────────────────────────────────────────────────

  Future<String?> _getPin() async {
    return await _secureStorage.read(key: _pinKey);
  }

  // ──────────────────────────────────────────────────────────────────
  //  암호화 키 파생
  // ──────────────────────────────────────────────────────────────────

  /// PBKDF2-HMAC-SHA256 키 파생 (버전 2 포맷용)
  ///
  /// iterations=100000, keyLength=32byte
  Uint8List _pbkdf2(String password, Uint8List salt) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final result = Uint8List(_keyLength);
    int generated = 0;
    int blockNum = 1;

    while (generated < _keyLength) {
      // U1 = HMAC(password, salt || INT32_BE(blockNum))
      final saltAndBlock = Uint8List(salt.length + 4);
      saltAndBlock.setAll(0, salt);
      saltAndBlock[salt.length + 0] = (blockNum >> 24) & 0xFF;
      saltAndBlock[salt.length + 1] = (blockNum >> 16) & 0xFF;
      saltAndBlock[salt.length + 2] = (blockNum >> 8) & 0xFF;
      saltAndBlock[salt.length + 3] = blockNum & 0xFF;

      final hmac = Hmac(sha256, passwordBytes);
      var u = Uint8List.fromList(hmac.convert(saltAndBlock).bytes);
      final block = Uint8List.fromList(u);

      for (int i = 1; i < _pbkdf2Iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int j = 0; j < block.length; j++) {
          block[j] ^= u[j];
        }
      }

      final toCopy = min(_keyLength - generated, block.length);
      result.setRange(generated, generated + toCopy, block);
      generated += toCopy;
      blockNum++;
    }

    return result;
  }

  /// 구버전 호환 키 파생 (버전 1 레거시용)
  enc.Key _legacyKeyFromPin(String pin) {
    final padded = pin.padRight(32, '0').substring(0, 32);
    return enc.Key.fromUtf8(padded);
  }

  // ──────────────────────────────────────────────────────────────────
  //  랜덤 바이트 생성
  // ──────────────────────────────────────────────────────────────────

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // ──────────────────────────────────────────────────────────────────
  //  백업 생성 (버전 2: PBKDF2 + AES-GCM + JSON 포맷)
  // ──────────────────────────────────────────────────────────────────

  Future<bool> createBackup(BuildContext context) async {
    try {
      final pin = await _getPin();
      if (pin == null || pin.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN이 설정되지 않았어요. 앱을 재시작해주세요.',
                  style: TextStyle(fontSize: 16)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }

      final categories = await _db.getCategories();
      final allMemos = await _db.getAllMemos();

      // 암호화할 내용 (plain JSON)
      final plainJson = jsonEncode({
        'categories': categories.map((c) => c.toMap()).toList(),
        'memos': allMemos.map((m) => {...m.toMap(), 'fields': m.data}).toList(),
      });

      // PBKDF2 키 파생
      final salt = _randomBytes(_saltLength);
      final iv = _randomBytes(_ivLength);
      final derivedKey = _pbkdf2(pin, salt);

      // AES-GCM 암호화
      final key = enc.Key(derivedKey);
      final encIv = enc.IV(iv);
      final encrypter =
          enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));
      final encrypted = encrypter.encrypt(plainJson, iv: encIv);

      // 버전2 JSON 파일 구성
      final now = DateTime.now();
      final backupJson = jsonEncode({
        'version': 2,
        'meta': {
          'createdAt': now.toIso8601String(),
          'categoryCount': categories.length,
          'memoCount': allMemos.length,
          'appVersion': '1.0.0',
        },
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': _pbkdf2Iterations,
        'salt': base64Encode(salt),
        'iv': base64Encode(iv),
        'data': encrypted.base64,
      });

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'gido_backup_${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.gido';
      final filePath = '${dir.path}/$fileName';

      await File(filePath).writeAsString(backupJson);
      debugPrint('✅ 백업 파일 저장: $filePath');

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: '기억 도우미 백업',
        text: '기억 도우미 백업 파일이에요.\n카카오톡 나와의 채팅에 보관하세요.',
      );

      return true;
    } catch (e, stack) {
      debugPrint('백업 오류: $e\n$stack');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  복원: PIN을 명시적으로 받아서 복호화 (1순위 보안 수정)
  // ──────────────────────────────────────────────────────────────────

  /// 백업 파일을 복원합니다.
  ///
  /// - [pin]: 사용자가 직접 입력한 PIN (저장된 PIN 자동 사용 금지)
  /// - PIN이 틀리거나 파일이 손상된 경우 [Exception]을 throw합니다.
  /// - 레거시 파일은 [BackupInfo.isLegacy] == true 로 구분하세요.
  Future<void> importBackupWithPin(String filePath, String pin) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('파일이 존재하지 않습니다');

    final raw = await file.readAsString();

    Map<String, dynamic> plainData;
    bool isLegacyFile = false;

    if (raw.trimLeft().startsWith('{')) {
      // ── 버전 2 (JSON) ─────────────────────────────────────────
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as int? ?? 0;

      if (version < 2) {
        throw Exception('지원하지 않는 백업 파일 형식입니다 (version=$version)');
      }

      final saltBytes = base64Decode(json['salt'] as String);
      final ivBytes = base64Decode(json['iv'] as String);
      final encData = json['data'] as String;

      final derivedKey = _pbkdf2(pin, saltBytes);
      final key = enc.Key(derivedKey);
      final iv = enc.IV(ivBytes);
      final encrypter =
          enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));

      try {
        final decrypted = encrypter.decrypt64(encData, iv: iv);
        plainData = jsonDecode(decrypted) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('PIN이 올바르지 않거나 백업 파일이 손상되었습니다.');
      }
    } else {
      // ── 레거시 버전 1 (iv:encData 포맷) ──────────────────────
      isLegacyFile = true;
      final colonIdx = raw.indexOf(':');
      if (colonIdx == -1) throw Exception('잘못된 백업 파일 형식입니다.');

      final ivBase64 = raw.substring(0, colonIdx);
      final encData = raw.substring(colonIdx + 1);

      final iv = enc.IV.fromBase64(ivBase64);
      final key = _legacyKeyFromPin(pin);
      final encrypter = enc.Encrypter(enc.AES(key));

      try {
        final decrypted = encrypter.decrypt64(encData, iv: iv);
        plainData = jsonDecode(decrypted) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('PIN이 올바르지 않거나 백업 파일이 손상되었습니다.');
      }
    }

    await _restoreData(plainData);
    debugPrint('✅ 복원 완료 (레거시: $isLegacyFile)');
  }

  // ──────────────────────────────────────────────────────────────────
  //  내부 데이터 복원 로직 (공통)
  // ──────────────────────────────────────────────────────────────────

  Future<void> _restoreData(Map<String, dynamic> data) async {
    final categoriesData = data['categories'] as List? ?? [];
    final memosData = data['memos'] as List? ?? [];

    debugPrint('복원할 카테고리: ${categoriesData.length}개, 메모: ${memosData.length}개');

    // 기존 데이터 삭제
    final existing = await _db.getCategories();
    for (final cat in existing) {
      await _db.deleteCategory(cat.id);
    }

    // 카테고리 복원
    for (final raw in categoriesData) {
      final cat = Category.fromMap(Map<String, dynamic>.from(raw as Map));
      await _db.insertCategory(cat);
    }

    // 기본 카테고리 아이콘 업데이트
    const iconUpdates = {
      'bank': 'assets/icons/bank.png',
      'site': 'assets/icons/site.png',
      'birthday': 'assets/icons/birthday.png',
      'church': 'assets/icons/church.png',
      'todo': 'assets/icons/todo.png',
    };
    for (final e in iconUpdates.entries) {
      await _db.updateCategoryIcon(e.key, e.value);
    }

    // 메모 복원
    for (final raw in memosData) {
      final map = Map<String, dynamic>.from(raw as Map);
      final fields =
          Map<String, dynamic>.from(map['fields'] as Map? ?? {});
      final fieldData = fields.map((k, v) => MapEntry(k, v.toString()));

      final memo = Memo(
        id: map['id'] as String,
        categoryId: map['categoryId'] as String,
        title: map['title'] as String,
        isDone: (map['isDone'] as int? ?? 0) == 1,
        data: fieldData,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      );
      await _db.insertMemo(memo);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  백업 파일 정보 파싱 (PIN 없이 미리보기)
  // ──────────────────────────────────────────────────────────────────

  /// .gido 파일의 메타 정보를 반환합니다.
  ///
  /// 버전2: meta 필드가 평문이므로 PIN 불필요
  /// 레거시: 저장된 PIN으로 시도 → 실패 시 "(알 수 없음)" 반환
  Future<BackupInfo?> getBackupInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      if (!filePath.toLowerCase().endsWith('.gido')) return null;

      final raw = await file.readAsString();
      final fileSize = await file.length();

      String fileSizeStr;
      if (fileSize < 1024) {
        fileSizeStr = '${fileSize}B';
      } else if (fileSize < 1024 * 1024) {
        fileSizeStr = '${(fileSize / 1024).toStringAsFixed(1)}KB';
      } else {
        fileSizeStr =
            '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
      }

      final fileName = filePath.split('/').last;

      if (raw.trimLeft().startsWith('{')) {
        // ── 버전 2: meta는 평문 ──────────────────────────────
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final meta = json['meta'] as Map<String, dynamic>? ?? {};

        final createdAt = meta['createdAt'] as String? ?? '';
        String dateStr = '(알 수 없음)';
        try {
          dateStr = DateFormat('yyyy년 M월 d일 HH:mm')
              .format(DateTime.parse(createdAt));
        } catch (_) {}

        return BackupInfo(
          filePath: filePath,
          fileName: fileName,
          fileSizeStr: fileSizeStr,
          categoryCount: meta['categoryCount'] as int? ?? 0,
          memoCount: meta['memoCount'] as int? ?? 0,
          dateStr: dateStr,
          isLegacy: false,
        );
      } else {
        // ── 레거시: 저장된 PIN으로 시도 (미리보기 전용) ───────
        final pin = await _getPin();
        if (pin != null && pin.isNotEmpty) {
          try {
            final colonIdx = raw.indexOf(':');
            if (colonIdx != -1) {
              final iv = enc.IV.fromBase64(raw.substring(0, colonIdx));
              final key = _legacyKeyFromPin(pin);
              final encrypter = enc.Encrypter(enc.AES(key));
              final decrypted =
                  encrypter.decrypt64(raw.substring(colonIdx + 1), iv: iv);
              final data = jsonDecode(decrypted) as Map<String, dynamic>;

              final cats = (data['categories'] as List?)?.length ?? 0;
              final memos = (data['memos'] as List?)?.length ?? 0;
              final createdAt = data['createdAt'] as String? ?? '';
              String dateStr = '(알 수 없음)';
              try {
                dateStr = DateFormat('yyyy년 M월 d일 HH:mm')
                    .format(DateTime.parse(createdAt));
              } catch (_) {}

              return BackupInfo(
                filePath: filePath,
                fileName: fileName,
                fileSizeStr: fileSizeStr,
                categoryCount: cats,
                memoCount: memos,
                dateStr: dateStr,
                isLegacy: true,
              );
            }
          } catch (_) {
            // 저장된 PIN이 다른 경우 → 정보 없이 반환
          }
        }

        // 저장된 PIN이 없거나 맞지 않음 → 정보만 없이 반환 (파일 자체는 유효)
        return BackupInfo(
          filePath: filePath,
          fileName: fileName,
          fileSizeStr: fileSizeStr,
          categoryCount: 0,
          memoCount: 0,
          dateStr: '(알 수 없음)',
          isLegacy: true,
        );
      }
    } catch (e) {
      debugPrint('백업 정보 파싱 오류: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  다운로드 폴더 자동 검색
  // ──────────────────────────────────────────────────────────────────

  Future<List<BackupInfo>> findGidoFiles() async {
    final result = <BackupInfo>[];
    try {
      final downloadPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
      ];
      for (final dirPath in downloadPaths) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File &&
              entity.path.toLowerCase().endsWith('.gido')) {
            final info = await getBackupInfo(entity.path);
            if (info != null) result.add(info);
          }
        }
      }
    } catch (e) {
      debugPrint('자동 검색 오류: $e');
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────
  //  파일 선택 → 복원 (레거시 API, 저장된 PIN 사용)
  //  ※ RestoreScreen에서 직접 호출하지 않음 (PIN 다이얼로그로 대체)
  // ──────────────────────────────────────────────────────────────────

  Future<bool> restoreBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return false;
      final filePath = result.files.single.path;
      if (filePath == null) return false;

      return await restoreFromPath(context, filePath);
    } catch (e, stack) {
      debugPrint('복원 오류: $e\n$stack');
      return false;
    }
  }

  /// 저장된 PIN으로 복원 (레거시 호환용, 직접 사용 지양)
  Future<bool> restoreFromPath(BuildContext context, String filePath) async {
    try {
      final pin = await _getPin();
      if (pin == null || pin.isEmpty) return false;
      await importBackupWithPin(filePath, pin);
      return true;
    } catch (e, stack) {
      debugPrint('복원 오류: $e\n$stack');
      return false;
    }
  }

  /// 저장된 PIN으로 복원 (레거시 호환용)
  Future<void> importBackup(String filePath, {bool merge = false}) async {
    final pin = await _getPin();
    if (pin == null || pin.isEmpty) throw Exception('PIN이 설정되지 않았습니다');
    await importBackupWithPin(filePath, pin);
  }
}
