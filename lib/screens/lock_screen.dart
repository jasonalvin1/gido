import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../main.dart' show pendingGidoFilePath;
import 'home_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  bool _isAuthenticating = false;
  bool _isCheckingBiometric = false; // 추가: isBiometricAvailable 진행 중 플래그
  bool _showPinInput = false;
  bool _biometricAvailable = false;
  bool _isSettingPin = false;
  bool _isConfirmingPin = false;
  String _pinInput = '';
  String _firstPin = '';
  String _statusMessage = '손가락을 대주세요';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPinAndStart();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // _isAuthenticating 외에도 _checkAndAttemptBiometric 진행 중 여부를 함께 확인
    if (state == AppLifecycleState.resumed &&
        !_isAuthenticating &&
        !_isCheckingBiometric &&  // 추가: isBiometricAvailable 진행 중 중복 방지
        !_showPinInput &&
        !_isSettingPin) {
      _checkAndAttemptBiometric();
    }
  }

  Future<void> _checkPinAndStart() async {
    final isPinSet = await _authService.isPinSet();
    if (!mounted) return;
    if (!isPinSet) {
      setState(() {
        _isSettingPin = true;
        _showPinInput = true;
        _statusMessage = 'PIN 4자리를 설정해주세요';
      });
    } else {
      _checkAndAttemptBiometric();
    }
  }

  Future<void> _checkAndAttemptBiometric() async {
    if (_isAuthenticating || _isCheckingBiometric) return; // 중복 호출 방지
    _isCheckingBiometric = true;
    try {
      _biometricAvailable = await _authService.isBiometricAvailable();
      if (!mounted) return;
      if (!_biometricAvailable) {
        setState(() {
          _showPinInput = true;
          _statusMessage = 'PIN을 입력해주세요';
        });
        return;
      }
      await _attemptBiometric();
    } finally {
      _isCheckingBiometric = false;
    }
  }

  Future<void> _attemptBiometric() async {
    if (_isAuthenticating) return;
    if (!mounted) return;
    setState(() {
      _isAuthenticating = true;
      _statusMessage = '지문을 인식하고 있어요...';
    });
    try {
      final success = await _authService.authenticateWithBiometric();
      if (success && mounted) {
        _navigateToHome();
        return;
      }
    } catch (e) {
      debugPrint('🔐 auth error: $e');
    }
    if (mounted) {
      setState(() {
        _isAuthenticating = false;
        _statusMessage = '다시 눌러주세요';
      });
    }
  }

  void _onPinInput(String digit) {
    if (_pinInput.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() => _pinInput += digit);
    if (_pinInput.length == 4) {
      if (_isSettingPin) {
        _handlePinSetting();
      } else {
        _verifyPin();
      }
    }
  }

  void _onPinDelete() {
    if (_pinInput.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
  }

  Future<void> _handlePinSetting() async {
    if (!_isConfirmingPin) {
      setState(() {
        _firstPin = _pinInput;
        _pinInput = '';
        _isConfirmingPin = true;
        _statusMessage = 'PIN을 한 번 더 입력해주세요';
      });
    } else {
      if (_pinInput == _firstPin) {
        await _authService.setPin(_pinInput);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN이 설정됐어요! ✅', style: TextStyle(fontSize: 16)),
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {
            _isSettingPin = false;
            _isConfirmingPin = false;
            _pinInput = '';
          });
          _checkAndAttemptBiometric();
        }
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _firstPin = '';
          _pinInput = '';
          _isConfirmingPin = false;
          _statusMessage = 'PIN이 달라요. 다시 설정해주세요';
        });
      }
    }
  }

  Future<void> _verifyPin() async {
    final success = await _authService.verifyPin(_pinInput);
    if (success && mounted) {
      _navigateToHome();
    } else if (mounted) {
      setState(() {
        _pinInput = '';
        _statusMessage = 'PIN이 틀렸어요. 다시 입력해주세요';
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen()),
    );
  }

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
          child: Column(
            children: [
              // 백업 파일로 앱이 열렸을 때 힌트 배너
              if (pendingGidoFilePath != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(60)),
                  ),
                  child: const Row(
                    children: [
                      Text('📦', style: TextStyle(fontSize: 22)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '백업 파일을 찾았어요!\nPIN을 입력하면 바로 가져올 수 있어요.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(flex: 2),
              Image.asset('assets/icons/prayer.png', width: 72, height: 72),
              const SizedBox(height: 12),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
                  children: [
                    TextSpan(text: '기', style: TextStyle(color: Color(0xFFFF9800))),
                    TextSpan(text: '억 ', style: TextStyle(color: Colors.white)),
                    TextSpan(text: '도', style: TextStyle(color: Color(0xFFFF9800))),
                    TextSpan(text: '우미', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text('기도', style: TextStyle(fontSize: 20, color: Colors.white.withAlpha(180))),
              const Spacer(flex: 1),

              if (!_showPinInput) ...[
                GestureDetector(
                  onTap: () { if (!_isAuthenticating) _attemptBiometric(); },
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.08);
                      return Transform.scale(
                        scale: _isAuthenticating ? 1.0 : scale,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withAlpha(80), width: 3),
                        color: _isAuthenticating
                            ? Colors.white.withAlpha(60)
                            : Colors.white.withAlpha(25),
                      ),
                      child: const Center(child: Text('👆', style: TextStyle(fontSize: 60))),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: Colors.white.withAlpha(200),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showPinInput = true;
                      _pinInput = '';
                      _statusMessage = 'PIN 4자리를 입력해주세요';
                    });
                  },
                  child: Text('PIN으로 잠금 해제',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: Colors.white.withAlpha(150),
                      )),
                ),
              ] else ...[
                if (_isSettingPin)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isConfirmingPin ? '🔒 PIN 확인 중' : '🔑 처음 사용 시 PIN을 설정해요',
                      style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(180)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: Colors.white.withAlpha(200),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    return Container(
                      width: 24, height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pinInput.length ? Colors.white : Colors.white.withAlpha(50),
                        border: Border.all(color: Colors.white.withAlpha(130), width: 2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                _buildPinKeypad(),
                const SizedBox(height: 16),
                if (_biometricAvailable && !_isSettingPin)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showPinInput = false;
                        _pinInput = '';
                        _isAuthenticating = false;
                        _statusMessage = '손가락을 대주세요';
                      });
                    },
                    child: Text('지문으로 돌아가기',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          color: Colors.white.withAlpha(150),
                        )),
                  ),
              ],
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '←'],
    ];
    return Column(
      children: keys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) return const SizedBox(width: 80, height: 64);
            return GestureDetector(
              onTap: () { key == '←' ? _onPinDelete() : _onPinInput(key); },
              child: Container(
                width: 80, height: 64,
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(key,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      )),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}