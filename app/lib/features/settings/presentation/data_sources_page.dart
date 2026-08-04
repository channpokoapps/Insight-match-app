import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// マスタデータの出典表示。
///
/// 駅・路線データは CC BY 4.0 で提供されており、**クレジット表示が利用条件**。
/// 出典を差し替えたら `scripts/README.md` とこの画面の両方を更新すること。
class DataSourcesPage extends StatelessWidget {
  const DataSourcesPage({super.key});

  static const List<_DataSource> _sources = <_DataSource>[
    _DataSource(
      title: '都道府県・市区町村',
      author: 'code4fukui/address-japan',
      license: 'MIT License',
      note: 'デジタル庁「アドレス・ベース・レジストリ 市区町村マスターデータセット」を'
          '加工したものを利用しています。',
      url: 'https://github.com/code4fukui/address-japan',
    ),
    _DataSource(
      title: '鉄道路線・駅',
      author: 'Seo-4d696b75/station_database',
      license: 'CC BY 4.0',
      note: '当アプリの路線・駅データは上記を加工して利用しています。',
      url: 'https://github.com/Seo-4d696b75/station_database',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('データ出典')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              '本アプリで使用しているオープンデータの出典とライセンスです。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 16),
            for (final _DataSource s in _sources)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(s.author,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        s.license,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.note,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => launchUrl(Uri.parse(s.url)),
                          child: const Text('出典を開く'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DataSource {
  const _DataSource({
    required this.title,
    required this.author,
    required this.license,
    required this.note,
    required this.url,
  });

  final String title;
  final String author;
  final String license;
  final String note;
  final String url;
}
