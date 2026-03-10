import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/backup_service.dart';
import '../services/database_service.dart';
import '../utils/app_theme.dart';

/// 내 기억 가져오기 화면
///
/// 진입 경로:
///   1. 카카오톡에서 .gido 파일 탭 → 자동으로 열림 (initialFilePath 제공)
///   2. 홈 화면 "내 기억 가져오기" 버튼 탭 → 수동으로 파일 선택
class RestoreScreen extends StatefulWidget {
  /// 카카오톡 등 외부에서 받아온 파일 경로 (없으면 null)
  final String? initialFilePath;

  const RestoreScreen({super.key, this.initialFilePath});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _backupService = BackupService();

  BackupInfo? _selectedBackup;   // 현재 선택된 파일
  List<BackupInfo> _foundFiles = []; // 자동 검색 결과
  bool _isSearching = false;
  bool _isRestoring = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 1) 외부(카카오톡)에서 파일 경로가 넘어온 경우
    if (widget.initialFilePath != null) {
      final info = await _backupService.getBackupInfo(widget.initialFilePath!);
      if (mounted) {
        setState(() => _selectedBackup = info);
        if (info == null) {
          _showError('올바른 백업 파일이 아닙니다.\n(.gido 파일만 복원할 수 있어요)');
        }
      }
    }

    // 2) 다운로드 폴더 자동 검색 (Android 12 이하에서 권한 있을 때만 동작)
    _searchDownloads();
  }

  Future<void> _searchDownloads() async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    final files = await _backupService.findGidoFiles();

    if (!mounted) return;
    setState(() {
      _foundFiles = files;
      _isSearching = false;
    });
  }

  // ─────────────────────────────────────────────
  //  저장소 선택 바텀 시트
  // ─────────────────────────────────────────────
  Future<String?> _showSourcePicker() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '어디서 가져올까요?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sourceOption(ctx, 'kakaotalk', '📱', '카카오톡',    '카카오톡 저장 폴더'),
            _sourceOption(ctx, 'google',    '☁️', '구글 드라이브', '구글 드라이브에서 찾기'),
            _sourceOption(ctx, 'whatsapp',  '💬', 'WhatsApp',    'WhatsApp 저장 폴더'),
            _sourceOption(ctx, 'download',  '📥', '다운로드',    '기기 다운로드 폴더'),
            _sourceOption(ctx, 'other',     '📂', '직접 찾기',   '파일 탐색기에서 선택'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Widget _sourceOption(BuildContext ctx, String key, String emoji,
      String title, String subtitle) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  파일 직접 선택
  // ─────────────────────────────────────────────
  Future<void> _pickFile() async {
    // 저장소 선택
    final source = await _showSourcePicker();
    if (source == null) return;

    // 선택한 저장소에 따라 초기 디렉토리 결정
    String? initialDir;
    if (source == 'kakaotalk') {
      // 카카오톡 파일은 다운로드/KakaoTalk 폴더에 저장됨
      final paths = [
        '/storage/emulated/0/Download/KakaoTalk',
        '/storage/emulated/0/Downloads/KakaoTalk',
        '/storage/emulated/0/KakaoTalk',
      ];
      for (final p in paths) {
        if (await Directory(p).exists()) { initialDir = p; break; }
      }
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('📱 카카오톡에서 찾기',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            content: const Text(
              '파일 선택 화면이 열리면\n\n'
              '다운로드 → KakaoTalk 폴더에서\n'
              '백업 파일을 선택해주세요!',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    } else if (source == 'whatsapp') {
      final d = Directory('/storage/emulated/0/WhatsApp');
      initialDir = await d.exists() ? d.path : null;
    } else if (source == 'download') {
      final d = Directory('/storage/emulated/0/Download');
      initialDir = await d.exists() ? d.path : null;
    } else {
      initialDir = null;
      // 구글 드라이브 선택 시 → 먼저 안내 다이얼로그 표시
      if (source == 'google' && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('☁️ 구글 드라이브에서 찾기',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            content: const Text(
              '파일 선택 화면이 열리면\n\n'
              '구글 드라이브 → 내 드라이브\n'
              '폴더에서 백업 파일을 선택해주세요!',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: '백업 파일 선택 (.gido)',
        allowMultiple: false,
        initialDirectory: initialDir,
      );

      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;

      // 파일 내용으로 유효성 검사 (확장자 없어도 OK - 구글 드라이브 등)
      final info = await _backupService.getBackupInfo(path);
      if (!mounted) return;

      if (info == null) {
        _showError('올바른 백업 파일이 아닙니다.');
        return;
      }

      setState(() => _selectedBackup = info);
    } catch (e) {
      if (!mounted) return;
      _showError('파일 선택 중 오류가 발생했어요.\n$e');
    }
  }

  // ─────────────────────────────────────────────
  //  복원 실행
  // ─────────────────────────────────────────────
  Future<void> _startRestore(BackupInfo backup) async {
    // Step 1: 확인 다이얼로그
    final confirmed = await _showConfirmDialog(backup);
    if (!confirmed || !mounted) return;

    // Step 2: PIN 입력 다이얼로그 (저장된 PIN 자동 사용 금지)
    final pin = await _showPinDialog();
    if (pin == null || !mounted) return;

    setState(() {
      _isRestoring = true;
      _statusMessage = '기억을 가져오는 중이에요...\n잠시만 기다려주세요';
    });

    try {
      await _backupService.importBackupWithPin(backup.filePath, pin);

      if (mounted) await context.read<AppState>().loadData();
      if (!mounted) return;

      // 레거시 파일이면 재백업 권고 메시지
      if (backup.isLegacy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ 내 기억을 가져왔어요!\n⚠️ 구버전 파일이에요. 보안을 위해 다시 보관해 두세요.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            backgroundColor: Color(0xFFF57C00),
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 내 기억을 가져왔어요!'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 3),
          ),
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestoring = false;
        _statusMessage = '';
      });
      // PIN 오류와 기타 오류 구분
      final msg = e.toString().contains('PIN이 올바르지 않거나')
          ? 'PIN이 올바르지 않거나\n백업 파일이 손상되었습니다.'
          : '복원 중 오류가 발생했어요.\n$e';
      _showError(msg);
    }
  }

  // ─────────────────────────────────────────────
  //  PIN 입력 다이얼로그
  // ─────────────────────────────────────────────
  Future<String?> _showPinDialog() async {
    String pinInput = '';
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('🔐 PIN 입력',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '기억 보관 시 사용한\nPIN 4자리를 입력해주세요.',
                  style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  obscureText: obscure,
                  maxLength: 4,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8),
                  textAlign: TextAlign.center,
                  onChanged: (v) => pinInput = v,
                  decoration: InputDecoration(
                    hintText: '● ● ● ●',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        letterSpacing: 6,
                        fontSize: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryColor, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                    counterText: '',
                  ),
                ),
              ],
            ),  // Column
          ),    // SingleChildScrollView
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx2, null),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (pinInput.length == 4) Navigator.pop(ctx2, pinInput);
              },
              child: const Text('확인',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  다이얼로그
  // ─────────────────────────────────────────────
  Future<bool> _showConfirmDialog(BackupInfo backup) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('기억을 가져올까요?',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('📦', '카테고리', '${backup.categoryCount}개'),
                const SizedBox(height: 6),
                _infoRow('📝', '메모', '${backup.memoCount}개'),
                const SizedBox(height: 6),
                _infoRow('🕐', '보관 날짜', backup.dateStr),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠️', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '현재 저장된 데이터가\n보관 파일로 교체됩니다.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFFD32F2F),
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('가져오기'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ 확인 필요'),
        content:
            Text(message, style: const TextStyle(height: 1.5, fontSize: 16)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(color: AppTheme.textSecondary,
                fontSize: 15)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('내 기억 가져오기',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryColor,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: _isRestoring ? _buildRestoringView() : _buildBody(),
    );
  }

  Widget _buildRestoringView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primaryColor, strokeWidth: 4),
            const SizedBox(height: 28),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ══════════════════════════════════════
          //  카카오톡에서 받은 파일 (자동 인식)
          // ══════════════════════════════════════
          if (_selectedBackup != null) ...[
            _sectionHeader('📲', '받은 기억 파일'),
            const SizedBox(height: 12),
            _buildBackupCard(_selectedBackup!, highlight: true),
            const SizedBox(height: 32),
          ],

          // ══════════════════════════════════════
          //  직접 파일 선택 버튼 (가장 중요!)
          // ══════════════════════════════════════
          _sectionHeader('📁', '파일 선택으로 가져오기'),
          const SizedBox(height: 12),

          // 안내 박스
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 어디에 저장했는지 선택해 주세요',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.primaryColor),
                ),
                SizedBox(height: 6),
                Text(
                  '카카오톡, 구글 드라이브, WhatsApp 등\n'
                  '저장한 곳을 선택하면 바로 해당 폴더가 열려요!',
                  style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 파일 선택 버튼 (크고 눈에 띄게)
          ElevatedButton(
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 2,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📂', style: TextStyle(fontSize: 26)),
                SizedBox(width: 10),
                Text(
                  '저장 위치 선택해서 가져오기',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ══════════════════════════════════════
          //  자동 검색 결과 (Android 11 이하 기기에서만 표시)
          // ══════════════════════════════════════
          _sectionHeader('🔍', '자동으로 찾은 파일'),
          const SizedBox(height: 12),

          if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryColor),
                    SizedBox(height: 10),
                    Text('다운로드 폴더 검색 중...',
                        style:
                            TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else if (_foundFiles.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Text('📭', style: TextStyle(fontSize: 36)),
                  SizedBox(height: 10),
                  Text(
                    '자동으로 찾지 못했어요.\n위에서 직접 파일을 선택해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._foundFiles
                .where((f) => f.filePath != _selectedBackup?.filePath)
                .map((info) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildBackupCard(info),
                    )),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBackupCard(BackupInfo info, {bool highlight = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? AppTheme.primaryColor
              : const Color(0xFFE0E0E0),
          width: highlight ? 2.5 : 1.5,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 파일명 + 크기 + 레거시 배지
            Row(
              children: [
                const Text('💾', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.fileName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (info.isLegacy) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFF57C00), width: 1),
                          ),
                          child: const Text(
                            '⚠️ 구버전 파일',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF57C00)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(info.fileSizeStr,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary)),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 14),

            // 카테고리 / 메모 수
            Row(
              children: [
                _chip('📦 ${info.categoryCount}개 카테고리'),
                const SizedBox(width: 8),
                _chip('📝 ${info.memoCount}개 메모'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '🕐 ${info.dateStr}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 16),

            // 복원 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startRestore(info),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text(
                  '이 파일로 가져오기',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor),
      ),
    );
  }
}
