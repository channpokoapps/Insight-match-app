/// 登録時に表示する同意文言を定義するファイル。
///
/// 文言をウィジェットから切り離し、役割ごとの内容と免責の有無を
/// `app/test/consent_terms_test.dart` で検証できるようにする。
/// 改定したら `AppConfig.termsVersion` を上げて再同意を求めること。
library;

import 'app_role.dart';

/// 同意画面に表示する 1 セクション。
class ConsentSection {
  const ConsentSection({
    required this.title,
    required this.bullets,
    this.isDisclaimer = false,
  });

  final String title;
  final List<String> bullets;

  /// 免責事項のセクションかどうか。画面上で強調して表示する。
  final bool isDisclaimer;
}

/// 役割に応じた同意文言を返す。
///
/// 免責セクション（[ConsentSection.isDisclaimer]）はどの役割でも必ず含める。
List<ConsentSection> consentSectionsFor(AppRole role) => <ConsentSection>[
      if (role == AppRole.client) ..._clientSections else ..._creatorSections,
      _serviceScope,
      _disclaimer,
    ];

const ConsentSection _serviceScope = ConsentSection(
  title: '本サービスの位置づけ',
  bullets: <String>[
    '本サービスは、店舗（PR依頼者）と投稿者が出会う場を提供するものです。'
        '運営は取引の当事者ではなく、代理人でも仲介人でもありません。',
    '案件の内容・報酬・来店日時・投稿方法などの条件は、当事者同士で確認し'
        '合意してください。',
    '景品表示法（ステルスマーケティング規制）や食品衛生法などの法令遵守は、'
        '各利用者の責任で行ってください。',
  ],
);

const ConsentSection _disclaimer = ConsentSection(
  title: '免責事項（必ずお読みください）',
  isDisclaimer: true,
  bullets: <String>[
    '当事者間で生じたトラブル・損害について、運営は一切の責任を負いません。'
        '報酬の未払い、来店の拒否、投稿内容の相違、無断キャンセル、飲食物に'
        '起因する事故・アレルギー・体調不良などを含みます。当事者間で解決して'
        'ください。',
    '各 SNS の仕様変更・障害・アカウント停止によってインサイトが取得できなく'
        'なった場合や、それにより案件へ応募できなくなった場合も、運営は責任を'
        '負いません。',
    '本サービスの中断・終了・データの消失によって生じた損害について、'
        '運営は責任を負いません。',
    '利用者間の紛争に運営が関与する義務はありません。'
        '運営が任意で対応する場合も、解決を保証するものではありません。',
  ],
);

const List<ConsentSection> _creatorSections = <ConsentSection>[
  ConsentSection(
    title: '投稿者のみなさまへ',
    bullets: <String>[
      'インサイトの実数値は応募条件の判定にのみ使われ、PR依頼者にも運営にも'
          '表示されません。',
      'PR 投稿には #PR などの広告であることの明示が必要です'
          '（ステルスマーケティング規制）。明示を怠って生じた責任は投稿者が'
          '負います。',
      '報酬（商品・サービスの提供を含む）の支払いは店舗が行います。'
          '未払いや条件の相違があっても、運営が補償することはありません。',
      '来店・飲食はご自身の判断と責任で行ってください。'
          'アレルギーや体調については、事前に店舗へご確認ください。',
    ],
  ),
];

const List<ConsentSection> _clientSections = <ConsentSection>[
  ConsentSection(
    title: 'PR依頼者（店舗）のみなさまへ',
    bullets: <String>[
      '投稿者の氏名・SNS アカウント名・インサイトの実数値は開示されません。'
          '案件内で表示されるのは応募順の連番のみです。',
      '応募者数や条件に合う人数は、個人が特定されないよう丸めて表示されること'
          'があります。実数の推定を目的とした利用は禁止します。',
      '投稿の実施・時期・内容・効果を運営が保証するものではありません。'
          '期待した効果が得られなかった場合も、運営は責任を負いません。',
      'ステルスマーケティング規制上、広告であることの明示は広告主である店舗側'
          'の義務でもあります。投稿者に #PR などの表示を必ず依頼してください。',
      '提供する飲食物の安全・衛生管理と、来店した投稿者に生じた事故への対応は'
          '店舗の責任で行ってください。',
    ],
  ),
];
