/// Web 以外向けの差し替え実装。
///
/// GIS（Google Identity Services）は Web にしか存在しないため、
/// ここでは「描画するものは無い」ことを表す null を返す。
/// 呼び出し側（google_continue_button.dart）は null のときだけ
/// 自前の OutlinedButton を出す。
library;

import 'package:flutter/widgets.dart';

/// GIS が描画する「Google で続行」ボタン。Web 以外では常に null。
///
/// [width] ボタンの最小幅（px）。[locale] ボタン文言のロケール。
Widget? buildGoogleRenderedButton({
  required double width,
  required String locale,
}) =>
    null;
