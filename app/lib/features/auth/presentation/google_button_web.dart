/// Web 向けの「Google で続行」ボタン実装。
///
/// GIS（Google Identity Services）は、自分が描画したボタン以外からの
/// 認証開始を認めていない（`GoogleSignIn.authenticate()` は Web では
/// UnimplementedError を投げる）。そのため見た目も Google 提供のものを使う。
/// 文言は `continueWith` を選ぶので、日本語ロケールでは他プラットフォームと
/// 同じ「Google で続行」になる。
library;

import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;

/// GIS が描画する「Google で続行」ボタン。
///
/// [width] ボタンの最小幅（px。GIS の上限は 400）。
/// [locale] ボタン文言のロケール（例: `ja`）。
Widget? buildGoogleRenderedButton({
  required double width,
  required String locale,
}) {
  return gis.renderButton(
    configuration: gis.GSIButtonConfiguration(
      type: gis.GSIButtonType.standard,
      theme: gis.GSIButtonTheme.outline,
      size: gis.GSIButtonSize.large,
      text: gis.GSIButtonText.continueWith,
      shape: gis.GSIButtonShape.rectangular,
      logoAlignment: gis.GSIButtonLogoAlignment.left,
      minimumWidth: width,
      locale: locale,
    ),
  );
}
