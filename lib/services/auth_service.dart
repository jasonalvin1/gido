import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _pinKey = 'gido_pin';

  // 생체인증 가능 여부 확인
  Future<bool> isBiometricAvailable() async {
    try {
      // getAvailableBiometrics() 제거 - 불필요한 시스템 호출로 동시 호출 시 교착 유발
      final isAvailable = await _localAuth.canCheckBiometrics
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      final isDeviceSupported = await _localAuth.isDeviceSupported()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);

      debugPrint('🔐 canCheckBiometrics: $isAvailable');
      debugPrint('🔐 isDeviceSupported: $isDeviceSupported');

      // AND 조건: 둘 다 true여야 생체인증 시도 (OR은 오동작 유발)
      return isAvailable && isDeviceSupported;
    } catch (e) {
      debugPrint('🔐 isBiometricAvailable error: $e');
      return false;
    }
  }

  // 지문 인증
  Future<bool> authenticateWithBiometric() async {
    try {
      debugPrint('🔐 Starting biometric authentication...');
      final result = await _localAuth.authenticate(
        localizedReason: '기억 도우미에 접근하려면 인증해주세요',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // 지문 + 기기 PIN/패턴 모두 허용
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      ).timeout(
        const Duration(seconds: 60), // 60초 후 자동 실패 처리 (stickyAuth 무한 대기 방지)
        onTimeout: () {
          debugPrint('🔐 Biometric authentication timed out');
          return false;
        },
      );
      debugPrint('🔐 Biometric result: $result');
      return result;
    } catch (e) {
      debugPrint('🔐 authenticateWithBiometric error: $e');
      return false;
    }
  }

  // PIN 설정
  Future<void> setPin(String pin) async {
    await _secureStorage.write(key: _pinKey, value: pin);
  }

  // PIN 확인
  Future<bool> verifyPin(String pin) async {
    final storedPin = await _secureStorage.read(key: _pinKey);
    return storedPin == pin;
  }

  // PIN 설정 여부
  Future<bool> isPinSet() async {
    final pin = await _secureStorage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  // 민감 데이터 암호화 저장
  Future<void> saveSecureData(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  // 민감 데이터 읽기
  Future<String?> readSecureData(String key) async {
    return await _secureStorage.read(key: key);
  }

  // 민감 데이터 삭제
  Future<void> deleteSecureData(String key) async {
    await _secureStorage.delete(key: key);
  }
}
