/// 認証・登録まわりの入力検証をまとめる純粋関数群。
///
/// UI やリポジトリに依存しないため、単体テストしやすい domain 層に置く。
library;

/// パスワードの最小文字数。Supabase の既定（6 文字）より厳しくする。
const int MIN_PASSWORD_LENGTH = 8;

/// 登録に必要な最低年齢（OI-08）。
const int MIN_AGE = 18;

/// メールアドレスの形式を検証する。
///
/// 厳密な RFC 準拠ではなく、明らかな誤入力を弾くことを目的とする。
/// 最終的な妥当性は Supabase 側の検証に委ねる。
bool isValidEmail(String email) {
  final String trimmed = email.trim();
  if (trimmed.isEmpty || trimmed.length > 254 || trimmed.contains(' ')) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$').hasMatch(trimmed);
}

/// パスワードの強度を検証する。
///
/// 戻り値は妥当なら null、問題があれば利用者向けの説明文。
String? validatePassword(String password) {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return 'パスワードは $MIN_PASSWORD_LENGTH 文字以上で入力してください。';
  }
  final bool hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
  final bool hasDigit = RegExp(r'[0-9]').hasMatch(password);
  if (!hasLetter || !hasDigit) {
    return 'パスワードには英字と数字を両方含めてください。';
  }
  return null;
}

/// [birthDate] 時点の年齢が [MIN_AGE] 以上かどうか（OI-08）。
bool isOldEnough(DateTime birthDate, DateTime now) {
  final DateTime threshold = DateTime(now.year - MIN_AGE, now.month, now.day);
  return !birthDate.isAfter(threshold);
}
