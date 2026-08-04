import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/auth/domain/app_role.dart';
import 'package:insight_match/features/auth/domain/consent_terms.dart';

void main() {
  group('consentSectionsFor', () {
    test('どの役割でも免責セクションを必ず含む', () {
      for (final AppRole role in AppRole.values) {
        final List<ConsentSection> sections = consentSectionsFor(role);
        expect(
          sections.where((ConsentSection s) => s.isDisclaimer),
          hasLength(1),
          reason: '${role.key} に免責セクションがない',
        );
      }
    });

    test('免責は運営が責任を負わないことを明記している', () {
      for (final AppRole role in AppRole.values) {
        final ConsentSection disclaimer = consentSectionsFor(role)
            .firstWhere((ConsentSection s) => s.isDisclaimer);
        expect(disclaimer.bullets, isNotEmpty);
        expect(
          disclaimer.bullets.any((String b) => b.contains('責任を負いません')),
          isTrue,
          reason: '${role.key} の免責に責任否認の文言がない',
        );
      }
    });

    test('役割ごとに専用のセクションが出し分けられる', () {
      final List<String> creator = consentSectionsFor(AppRole.creator)
          .map((ConsentSection s) => s.title)
          .toList();
      final List<String> client = consentSectionsFor(AppRole.client)
          .map((ConsentSection s) => s.title)
          .toList();
      expect(creator, isNot(equals(client)));
      expect(creator.first, contains('投稿者'));
      expect(client.first, contains('PR依頼者'));
    });

    test('PR依頼者向けの文言に投稿者の識別情報を示唆する表現がない', () {
      // R-5: 連番以外を見せないという約束を、同意文言のレベルでも崩さない。
      final List<String> bullets = consentSectionsFor(AppRole.client)
          .expand((ConsentSection s) => s.bullets)
          .toList();
      expect(
        bullets.any((String b) => b.contains('開示されません')),
        isTrue,
      );
    });

    test('セクションはすべて本文を持つ', () {
      for (final AppRole role in AppRole.values) {
        for (final ConsentSection section in consentSectionsFor(role)) {
          expect(section.title, isNotEmpty);
          expect(section.bullets, isNotEmpty);
        }
      }
    });
  });
}
