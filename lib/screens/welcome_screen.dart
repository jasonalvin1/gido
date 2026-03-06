import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import 'lock_screen.dart';

/// 첫 실행 환영 화면
///
/// PIN이 설정되어 있지 않은 최초 실행 시 표시됩니다.
///   - 새로 시작하기 → LockScreen(PIN 설정 플로우)
///   - 내 기억 가져오기 → 파일 선택 → PIN 입력 → 복원 → HomeScreen
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _backupService = BackupService();
  final _authService = AuthService();
  bool _isRestoring = false;

  // ────────────────────────────────────────────────────
  //  빌드
  // ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)],
          ),
        ),
        child: SafeArea(
          child: _isRestoring ? _buildRestoringView() : _buildWelcomeView(),
        ),
      ),
    );
  }

  // ── 복원 중 화면 ──────────────────────────────────────

  Widget _buildRestoringView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white, strokeWidth: 4),
          SizedBox(height: 28),
          Text(
            '데이터를 복원하고 있어요...\n잠시만 기다려주세요',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── 메인 환영 화면 ────────────────────────────────────

  Widget _buildWelcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 64),

          // 앱 로고 + 타이틀
          Center(child: Image.asset('assets/icons/prayer.png', width: 80, height: 80)),
          const SizedBox(height: 16),
          Center(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1),
                children: [
                  TextSpan(
                      text: '기',
                      style: TextStyle(color: Color(0xFFFF9800))),
                  TextSpan(
                      text: '억 ',
                      style: TextStyle(color: Colors.white)),
                  TextSpan(
                      text: '도',
                      style: TextStyle(color: Color(0xFFFF9800))),
                  TextSpan(
                      text: '우미',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '처음 오셨군요!\n어떻게 시작할까요?',
            style: TextStyle(
              fontSize: 17,
              color: Colors.white.withAlpha(200),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 56),

          // ── 새로 시작하기 버튼 ────────────────────────
          ElevatedButton(
            onPressed: _startFresh,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Column(
              children: [
                Text('🆕', style: TextStyle(fontSize: 34)),
                SizedBox(height: 6),
                Text(
                  '새로 시작하기',
                  style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'PIN과 지문 인증을 새로 설정해요',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 내 기억 가져오기 버튼 ────────────────────────
          OutlinedButton(
            onPressed: _restoreFromBackup,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Column(
              children: [
                Text('📂', style: TextStyle(fontSize: 34)),
                SizedBox(height: 6),
                Text(
                  '내 기억 가져오기',
                  style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  '보관한 기억 파일을 가져와요',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────
  //  액션
  // ────────────────────────────────────────────────────

  /// 새로 시작하기 → LockScreen (PIN 설정 플로우 진행)
  void _startFresh() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LockScreen()),
    );
  }

  /// 내 기억 가져오기 → 파일 선택 → PIN 입력 → 복원 → 홈
  Future<void> _restoreFromBackup() async {
    try {
      // 1. 파일 선택
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: '백업 파일(.gido) 선택',
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      if (!filePath.toLowerCase().endsWith('.gido')) {
        _showError(
            '.gido 파일만 복원할 수 있어요.\n선택한 파일: ${filePath.split('/').last}');
        return;
      }

      // 2. 백업 정보 파싱 (v2: PIN 없이 meta 읽기)
      final info = await _backupService.getBackupInfo(filePath);
      if (!mounted) return;

      // 3. PIN 입력 (meta 정보 함께 표시)
      final pin = await _showPinDialog(info);
      if (pin == null || !mounted) return;

      // 4. 복원 실행
      setState(() => _isRestoring = true);

      await _backupService.importBackupWithPin(filePath, pin);

      // 5. 복원한 PIN을 앱 PIN으로 저장 (첫 실행이므로 PIN이 없는 상태)
      await _authService.setPin(pin);

      // 6. 앱 상태 로드 후 홈으로 이동
      if (mounted) await context.read<AppState>().loadData();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      final msg = e.toString().contains('PIN이 올바르지 않거나')
          ? 'PIN이 올바르지 않거나\n백업 파일이 손상되었습니다.'
          : '복원 중 오류가 발생했어요.\n$e';
      _showError(msg);
    }
  }

  // ────────────────────────────────────────────────────
  //  다이얼로그
  // ────────────────────────────────────────────────────

  Future<String?> _showPinDialog(BackupInfo? info) async {
    String pinInput = '';
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('🔐 PIN 입력',
              style:
                  TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 백업 메타 카드 (카운트가 있을 때만 표시)
              if (info != null &&
                  (info.categoryCount > 0 || info.memoCount > 0)) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📦 ${info.categoryCount}개 카테고리'
                        '  📝 ${info.memoCount}개 메모',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🕐 ${info.dateStr}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const Text(
                '백업 파일에 사용한 PIN 4자리를\n입력해주세요.',
                style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 14),
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
                        obscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                  counterText: '',
                ),
              ),
            ],
          ),  // Column
          ),  // SingleChildScrollView
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
              child: const Text('복원하기',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ 오류'),
        content:
            Text(message, style: const TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
