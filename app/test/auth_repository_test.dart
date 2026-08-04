import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/auth/data/auth_repository.dart';

void main() {
  group('AuthRepository.webRedirectUrl', () {
    test('本番 URL はクエリを落として末尾スラッシュ付きオリジンにする', () {
      // Redirect URLs は `https://host/**` 形式で登録されているため、
      // 素の origin ではパターンに一致せず Site URL へ無言フォールバックする。
      expect(
        AuthRepository.webRedirectUrl(
          Uri.parse('https://insight-match-2fbaa.web.app/?code=x'),
        ),
        'https://insight-match-2fbaa.web.app/',
      );
    });

    test('プレビューチャンネルの深いパスもオリジン + / に丸める', () {
      expect(
        AuthRepository.webRedirectUrl(
          Uri.parse(
            'https://insight-match-2fbaa--preview-abc.web.app/deep/path',
          ),
        ),
        'https://insight-match-2fbaa--preview-abc.web.app/',
      );
    });

    test('localhost はポートを維持する', () {
      expect(
        AuthRepository.webRedirectUrl(Uri.parse('http://localhost:8080/')),
        'http://localhost:8080/',
      );
    });

    test('http(s) 以外（Android の file URI）は null を返し例外を投げない', () {
      // Uri.origin は http(s) 以外で投げる。ここで落ちるとログイン処理ごと死ぬ。
      expect(
        AuthRepository.webRedirectUrl(Uri.parse('file:///data/user/0/app/')),
        isNull,
      );
    });
  });
}
