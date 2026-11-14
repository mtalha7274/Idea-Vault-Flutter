import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';

Matcher throwsBackupError(CloudBackupErrorType type) {
  return throwsA(
    isA<CloudBackupException>().having((error) => error.type, 'type', type),
  );
}

void main() {
  final idea = Idea(
    id: 'idea-1',
    title: 'Backup idea',
    createdAt: DateTime.utc(2026, 5, 16),
    updatedAt: DateTime.utc(2026, 5, 16),
    lastOpenedSectionId: 'section-1',
    sections: const [
      IdeaSection(
        id: 'section-1',
        name: 'Idea',
        content: '',
      ),
    ],
  );
  final addition = RandomAddition(
    id: 'random-1',
    content: 'Loose note',
    createdAt: DateTime.utc(2026, 5, 16, 12),
  );

  CloudBackupSnapshot buildSnapshot() {
    return CloudBackupSnapshot.fromContent(
      ideas: [idea],
      randomAdditions: [addition],
      deviceId: 'abcdef0123456789',
      deviceName: 'Pixel 8',
      appVersion: '1.2.3+4',
      createdAt: DateTime.utc(2026, 11, 2, 9),
    );
  }

  group('CloudBackupSnapshot', () {
    test('serializes random additions in current backup format', () {
      final snapshot = buildSnapshot();
      final restored = CloudBackupSnapshot.fromJson(snapshot.toJson());

      expect(restored.version, CloudBackupSnapshot.currentVersion);
      expect(restored.ideas.single.title, 'Backup idea');
      expect(restored.ideas.single.lastOpenedSectionId, 'section-1');
      expect(restored.randomAdditions.single, addition);
    });

    test('parses old backups without random additions', () {
      final snapshot = CloudBackupSnapshot.fromJson({
        'version': 1,
        'exportedAt': '2026-05-16T00:00:00.000Z',
        'ideas': const [],
      });

      expect(snapshot.version, 1);
      expect(snapshot.ideas, isEmpty);
      expect(snapshot.randomAdditions, isEmpty);
    });

    test('writes a v3 header with counts, hash and a null lock block', () {
      final encoded = buildSnapshot().encode();
      final json = jsonDecode(encoded) as Map<String, dynamic>;

      expect(json['version'], 3);
      expect(json['backupId'], isA<String>());
      expect(json['deviceId'], 'abcdef0123456789');
      expect(json['deviceName'], 'Pixel 8');
      expect(json['appVersion'], '1.2.3+4');
      expect(json['counts'], {'ideas': 1, 'randomAdditions': 1});
      expect(json['contentHash'], startsWith('sha256:'));
      expect(json.containsKey('lock'), isTrue);
      expect(json['lock'], isNull);
      expect(encoded.contains('\n'), isFalse);
    });

    test('validates and decodes a v3 backup', () {
      final decoded =
          CloudBackupSnapshot.decodeAndValidate(buildSnapshot().encode());

      expect(decoded.version, 3);
      expect(decoded.deviceName, 'Pixel 8');
      expect(decoded.ideas.single, idea);
      expect(decoded.randomAdditions.single, addition);
    });

    test('preserves an unknown lock block on read', () {
      final json = buildSnapshot().toJson();
      json['lock'] = {'kdf': 'argon2id', 'wrap': 'abc'};

      final decoded =
          CloudBackupSnapshot.decodeAndValidate(jsonEncode(json));

      expect(decoded.lock, {'kdf': 'argon2id', 'wrap': 'abc'});
      expect(decoded.toJson()['lock'], {'kdf': 'argon2id', 'wrap': 'abc'});
    });

    test('content hash is stable for identical content', () {
      final first = CloudBackupSnapshot.contentHashFor(
        ideas: [idea],
        randomAdditions: [addition],
      );
      final second = buildSnapshot().contentHash;
      final changed = CloudBackupSnapshot.contentHashFor(
        ideas: [idea.copyWith(title: 'Changed')],
        randomAdditions: [addition],
      );

      expect(first, second);
      expect(changed, isNot(first));
    });

    test('rejects text that is not valid JSON', () {
      expect(
        () => CloudBackupSnapshot.decodeAndValidate('{not json'),
        throwsBackupError(CloudBackupErrorType.invalidBackup),
      );
    });

    test('rejects a backup from a newer app version', () {
      final json = buildSnapshot().toJson();
      json['version'] = CloudBackupSnapshot.currentVersion + 1;

      expect(
        () => CloudBackupSnapshot.decodeAndValidate(jsonEncode(json)),
        throwsBackupError(CloudBackupErrorType.newerVersion),
      );
    });

    test('rejects an idea that cannot be parsed instead of skipping it', () {
      final legacy = {
        'version': 2,
        'exportedAt': '2026-05-16T00:00:00.000Z',
        'ideas': [
          idea.toJson(),
          {'id': 'idea-2', 'title': 'Broken', 'createdAt': 'not a date'},
        ],
      };

      expect(
        () => CloudBackupSnapshot.decodeAndValidate(jsonEncode(legacy)),
        throwsBackupError(CloudBackupErrorType.invalidBackup),
      );
    });

    test('rejects a random note that cannot be parsed', () {
      final legacy = {
        'version': 2,
        'ideas': const [],
        'randomAdditions': ['just text'],
      };

      expect(
        () => CloudBackupSnapshot.decodeAndValidate(jsonEncode(legacy)),
        throwsBackupError(CloudBackupErrorType.invalidBackup),
      );
    });

    test('rejects a v3 backup whose content hash does not match', () {
      final json = buildSnapshot().toJson();
      (json['ideas'] as List<dynamic>).first['title'] = 'Tampered';

      expect(
        () => CloudBackupSnapshot.decodeAndValidate(jsonEncode(json)),
        throwsBackupError(CloudBackupErrorType.integrityFailed),
      );
    });

    test('rejects a v3 backup without a content hash', () {
      final json = buildSnapshot().toJson()..remove('contentHash');

      expect(
        () => CloudBackupSnapshot.decodeAndValidate(jsonEncode(json)),
        throwsBackupError(CloudBackupErrorType.integrityFailed),
      );
    });

    test('reads v1 backups with legacy delta section content', () {
      final legacy = {
        'version': 1,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'ideas': [
          {
            'id': 'legacy-1',
            'title': 'Old idea',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-02T00:00:00.000Z',
            'sections': [
              {
                'id': 'legacy-section',
                'name': 'Idea',
                'delta': [
                  {'insert': 'Hello '},
                  {'insert': 'world\n'},
                ],
              },
            ],
          },
        ],
      };

      final decoded =
          CloudBackupSnapshot.decodeAndValidate(jsonEncode(legacy));

      expect(decoded.version, 1);
      expect(decoded.ideas.single.sections.single.content, 'Hello world\n');
      expect(decoded.randomAdditions, isEmpty);
    });

    test('reads pretty printed v2 backups without a hash', () {
      final legacy = {
        'version': 2,
        'exportedAt': '2026-05-16T00:00:00.000Z',
        'ideas': [idea.toJson()],
        'randomAdditions': [addition.toJson()],
      };

      final decoded = CloudBackupSnapshot.decodeAndValidate(
        const JsonEncoder.withIndent('  ').convert(legacy),
      );

      expect(decoded.version, 2);
      expect(decoded.ideas.single, idea);
      expect(decoded.randomAdditions.single, addition);
    });
  });
}
