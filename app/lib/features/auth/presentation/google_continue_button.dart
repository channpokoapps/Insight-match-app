import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/error/app_failure.dart';
import '../data/auth_repository.dart';
// Web でだけ GIS のボタンを描画する。Web 以外は stub が null を返す。
import 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart';

/// 「Google で続行」ボタン。ログイン画面・新規登録画面で共用する。
///
/// **Web はページを離れない。** Google Identity Services（GIS）が描画する
/// ボタンをそのまま置き、アカウント選択の結果として返ってくる ID トークンを
/// `signInWithIdToken` に渡す。Android も同じ ID トークン方式。
///
/// リダイレクト方式（`signInWithOAuth`）をやめた理由は
/// [AuthRepository] のファイル冒頭コメントを参照。
///
/// 成功しても画面遷移はここでは行わない。セッションが張られると
/// `onAuthStateChange` 経由で router が次の段階へ運ぶ（app_router.dart）。
class GoogleContinueButton extends ConsumerStatefulWidget {
  const GoogleContinueButton({
    required this.onFailure,
    required this.onBusyChanged,
    this.enabled = true,
    super.key,
  });

  /// 表示すべき失敗が起きたときに呼ばれる。中断（利用者が閉じた）では呼ばれない。
  final ValueChanged<String> onFailure;

  /// ID トークンを Supabase に渡している間の状態変化を親へ伝える。
  final ValueChanged<bool> onBusyChanged;

  /// false の間は押せない（親フォームが送信中のときなど）。
  final bool enabled;

  @override
  ConsumerState<GoogleContinueButton> createState() =>
      _GoogleContinueButtonState();
}

class _GoogleContinueButtonState extends ConsumerState<GoogleContinueButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;

  /// GIS の初期化が済んだか。Web はこれが true になるまでボタンを描画できない。
  bool _ready = false;

  /// 初期化そのものに失敗した場合の文言（クライアント ID 未注入など）。
  String? _setupError;

  /// Supabase にセッションを張っている最中かどうか。
  bool _exchanging = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _prepare() async {
    final AuthRepository auth = ref.read(authRepositoryProvider);
    // 先に購読しておく。Web は GIS ボタンを押した時点で結果が流れてくるため、
    // 初期化完了を待ってから購読すると取りこぼす可能性がある。
    _events = auth.googleAuthenticationEvents.listen(
      _onEvent,
      onError: _onError,
    );
    try {
      await auth.ensureGoogleSignInReady();
      if (mounted) {
        setState(() => _ready = true);
      }
    } on Object catch (error) {
      final AppFailure? failure = AuthRepository.describeGoogleFailure(error);
      if (mounted) {
        setState(() => _setupError = failure?.message);
      }
    }
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    if (event is! GoogleSignInAuthenticationEventSignIn) {
      // サインアウト通知はログイン画面ですることがない。
      return;
    }
    unawaited(_exchange(event.user));
  }

  void _onError(Object error) {
    final AppFailure? failure = AuthRepository.describeGoogleFailure(error);
    _setBusy(false);
    if (failure != null) {
      widget.onFailure(failure.message);
    }
  }

  /// 受け取った Google アカウントで Supabase のセッションを張る。
  Future<void> _exchange(GoogleSignInAccount account) async {
    _setBusy(true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogleAccount(account);
    } on AppFailure catch (failure) {
      widget.onFailure(failure.message);
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool busy) {
    if (!mounted || _exchanging == busy) {
      return;
    }
    setState(() => _exchanging = busy);
    widget.onBusyChanged(busy);
  }

  Future<void> _start() async {
    _setBusy(true);
    try {
      await ref.read(authRepositoryProvider).startGoogleSignIn();
      // 成功時の続きは authenticationEvents 側で処理する。
    } on Object catch (error) {
      final AppFailure? failure = AuthRepository.describeGoogleFailure(error);
      if (failure != null) {
        widget.onFailure(failure.message);
      }
    } finally {
      // Web 以外は authenticate() が戻った時点でダイアログは閉じている。
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? setupError = _setupError;
    if (setupError != null) {
      // 設定が無い状態でボタンだけ出すと、押しても何も起きない画面になる。
      // 押せないことと理由が分かるようにしておく。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _fallbackButton(onPressed: null),
          const SizedBox(height: 8),
          Text(
            setupError,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final bool disabled = !widget.enabled || _exchanging;
    if (!_ready) {
      // 初期化中。押しても何も起きない時間を無効表示で示す。
      return _fallbackButton(onPressed: null);
    }

    if (!kIsWeb) {
      return _fallbackButton(onPressed: disabled ? null : _start);
    }

    // Web は GIS が描画したボタンを使う。GIS は自前のボタンからの
    // プログラム的な起動を認めておらず、これが唯一の開始方法。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // GIS の最小幅は 400px まで。端数で毎フレーム作り直さないよう丸める。
        final double width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
        final Widget? rendered = buildGoogleRenderedButton(
          width: width.clamp(200, 400).roundToDouble(),
          locale: Localizations.localeOf(context).toLanguageTag(),
        );
        if (rendered == null) {
          return _fallbackButton(onPressed: disabled ? null : _start);
        }
        return Opacity(
          // 交換中は押せないことを見た目でも示す（GIS 側は無効化できない）。
          opacity: disabled ? 0.5 : 1,
          child: IgnorePointer(ignoring: disabled, child: Center(child: rendered)),
        );
      },
    );
  }

  /// GIS を使わない場合のボタン。Android と、Web で GIS が使えない場合に出す。
  Widget _fallbackButton({required VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.account_circle_outlined),
      label: const Text('Google で続行'),
      onPressed: onPressed,
    );
  }
}
