import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/memo_model.dart';
import 'database_service.dart';

class BackupService {
  final DatabaseService _db = DatabaseService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _pinKey = 'gido_pin';

  enc.Key _keyFromPin(String pin) {
    final padded = pin.padRight(32, '0').substring(0, 32);
    return enc.Key.fromUtf8(padded);
  }

  Future<String?> _getPin() async {
    return await _secureStorage.read(key: _pinKey);
  }

  // 백업 생성
  Future<bool> createBackup(BuildContext context) async {
    try {
      final pin = await _getPin();
      if (pin == null || pin.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN이 설정되지 않았어요. 앱을 재시작해주세요.', style: TextStyle(fontSize: 16)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }

      final categories = await _db.getCategories();
      final allMemos = await _db.getAllMemos();

      final backupData = {
        'version': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'categories': categories.map((c) => c.toMap()).toList(),
        'memos': allMemos.map((m) => {
          ...m.toMap(),
          'fields': m.data,
        }).toList(),
      };

      final jsonStr = jsonEncode(backupData);
      debugPrint('백업 데이터: 카테고리 ${categories.length}개, 메모 ${allMemos.length}개');

      final key = _keyFromPin(pin);
      final iv = enc.IV.fromLength(16);
      final encrypter = enc.Encrypter(enc.AES(key));
      final encrypted = encrypter.encrypt(jsonStr, iv: iv);
      final finalData = '${iv.base64}:${encrypted.base64}';

      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final fileName = 'gido_backup_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour}${now.minute}.gido';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(finalData);
      debugPrint('백업 파일 저장: $filePath');

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: '기억 도우미 백업',
        text: '기억 도우미 백업 파일이에요.\n카카오톡 나와의 채팅에 보관하세요.',
      );

      return true;
    } catch (e, stack) {
      debugPrint('백업 오류: $e');
      debugPrint('스택: $stack');
      return false;
    }
  }

  // 파일 선택으로 복원
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
      debugPrint('복원 오류: $e');
      debugPrint('스택: $stack');
      return false;
    }
  }

  // 파일 경로로 직접 복원
  Future<bool> restoreFromPath(BuildContext context, String filePath) async {
    try {
      debugPrint('복원 시작: $filePath');

      final pin = await _getPin();
      debugPrint('PIN: $pin');
      if (pin == null || pin.isEmpty) return false;

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('파일이 존재하지 않음!');
        return false;
      }

      final fileContent = await file.readAsString();
      debugPrint('파일 읽기 성공, 길이: ${fileContent.length}');

      final colonIndex = fileContent.indexOf(':');
      if (colonIndex == -1) {
        debugPrint('잘못된 파일 형식');
        return false;
      }

      final ivBase64 = fileContent.substring(0, colonIndex);
      final encryptedData = fileContent.substring(colonIndex + 1);

      final iv = enc.IV.fromBase64(ivBase64);
      final key = _keyFromPin(pin);
      final encrypter = enc.Encrypter(enc.AES(key));
      final decrypted = encrypter.decrypt64(encryptedData, iv: iv);
      debugPrint('복호화 성공, 길이: ${decrypted.length}');

      final backupData = jsonDecode(decrypted) as Map<String, dynamic>;
      final categoriesData = backupData['categories'] as List;
      final memosData = backupData['memos'] as List;
      debugPrint('복원할 카테고리: ${categoriesData.length}개, 메모: ${memosData.length}개');

      // 기존 데이터 삭제
      final existingCategories = await _db.getCategories();
      for (final cat in existingCategories) {
        await _db.deleteCategory(cat.id);
      }
      debugPrint('기존 데이터 삭제 완료');

      // 카테고리 복원
      for (final catMap in categoriesData) {
        final map = Map<String, dynamic>.from(catMap as Map);
        final cat = Category.fromMap(map);
        await _db.insertCategory(cat);
        debugPrint('카테고리 복원: ${cat.name}');
      }

      // 기본 카테고리 아이콘을 최신 3D 이미지로 강제 업데이트
      const iconUpdates = {
        'bank':     'assets/icons/bank.png',
        'site':     'assets/icons/site.png',
        'birthday': 'assets/icons/birthday.png',
        'church':   'assets/icons/church.png',
        'todo':     'assets/icons/todo.png',
      };
      for (final entry in iconUpdates.entries) {
        await _db.updateCategoryIcon(entry.key, entry.value);
        debugPrint('아이콘 업데이트: ${entry.key} → ${entry.value}');
      }

      // 메모 복원
      for (final memoMap in memosData) {
        final map = Map<String, dynamic>.from(memoMap as Map);
        final fields = Map<String, dynamic>.from(map['fields'] as Map? ?? {});
        final fieldData = fields.map((k, v) => MapEntry(k, v.toString()));

        final memo = Memo(
          id: map['id'] as String,
          categoryId: map['categoryId'] as String,
          title: map['title'] as String,
          isDone: (map['isDone'] as int? ?? 0) == 1,
          data: fieldData,
          createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
        );
        await _db.insertMemo(memo);
        debugPrint('메모 복원: ${memo.title}');
      }

      debugPrint('복원 완료!');
      return true;
    } catch (e, stack) {
      debugPrint('복원 오류: $e');
      debugPrint('스택: $stack');
      return false;
    }
  }
}