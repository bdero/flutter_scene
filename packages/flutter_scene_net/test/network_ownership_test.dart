// Who owns an object, and what may be done about it. Ownership decides who may
// write owner-writable properties and send owner-only events, so every refusal
// here is a rule rather than an inconvenience.

import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Ownership owned({
    int by = 2,
    Set<OwnershipPermission> permissions = const {},
    bool locked = false,
  }) => Ownership(owner: by, permissions: permissions, locked: locked);

  group('an object that permits nothing', () {
    test('is static: it cannot be taken', () {
      // Saying nothing being the locked-down case is deliberate. The safe
      // default should be the one you get by not thinking about it.
      final it = owned();
      final outcome = it.give(3);
      expect(outcome.granted, isFalse);
      expect(outcome.refusal, OwnershipRefusal.notTransferable);
      expect(it.owner, 2);
    });

    test('and cannot be asked for either', () {
      final outcome = owned().request(3);
      expect(outcome.refusal, OwnershipRefusal.notTransferable);
    });
  });

  group('transferable', () {
    test('anyone may take it', () {
      final it = owned(permissions: {OwnershipPermission.transferable});
      expect(it.give(3).granted, isTrue);
      expect(it.owner, 3);
    });

    test('the owner taking it again is told so, not handed it', () {
      final it = owned(permissions: {OwnershipPermission.transferable});
      expect(it.give(2).refusal, OwnershipRefusal.alreadyOwner);
    });

    test('a lock outranks it', () {
      // The owner saying "not right now" about a thing that is normally free
      // to take: what you want while driving the car everyone else may drive.
      final it = owned(
        permissions: {OwnershipPermission.transferable},
        locked: true,
      );
      expect(it.give(3).refusal, OwnershipRefusal.locked);
      it.setLocked(false);
      expect(it.give(3).granted, isTrue);
    });
  });

  group('requestRequired', () {
    test('taking it is refused, and the refusal names the way forward', () {
      // A refusal that says what to do instead beats one that just says no.
      final it = owned(permissions: {OwnershipPermission.requestRequired});
      expect(it.give(3).refusal, OwnershipRefusal.requestRequired);
    });

    test('asking is allowed, and records who asked', () {
      final it = owned(permissions: {OwnershipPermission.requestRequired});
      expect(it.request(3).granted, isTrue);
      expect(it.pendingRequestFrom, 3);
      // Sent, not granted: the owner still owns it.
      expect(it.owner, 2);
    });

    test('a second asker is told somebody is ahead of them', () {
      final it = owned(permissions: {OwnershipPermission.requestRequired})
        ..request(3);
      expect(it.request(4).refusal, OwnershipRefusal.requestPending);
    });

    test('approving hands it over and locks it', () {
      // An object that had to be asked for is one where being interrupted
      // matters; leaving it free for the next taker defeats having asked.
      final it = owned(permissions: {OwnershipPermission.requestRequired})
        ..request(3);
      final outcome = it.answerRequest(approve: true);
      expect(outcome.granted, isTrue);
      expect(it.owner, 3);
      expect(it.locked, isTrue);
      expect(it.pendingRequestFrom, isNull);
    });

    test('refusing leaves it where it was and clears the request', () {
      final it = owned(permissions: {OwnershipPermission.requestRequired})
        ..request(3);
      expect(it.answerRequest(approve: false).granted, isFalse);
      expect(it.owner, 2);
      expect(it.pendingRequestFrom, isNull);
    });

    test('answering when nobody asked is refused', () {
      final it = owned(permissions: {OwnershipPermission.requestRequired});
      expect(it.answerRequest(approve: true).granted, isFalse);
    });

    test('a withdrawn request lets the next asker through', () {
      final it = owned(permissions: {OwnershipPermission.requestRequired})
        ..request(3)
        ..cancelRequest();
      expect(it.request(4).granted, isTrue);
    });

    test('a pending request blocks a taking, even on a transferable one', () {
      // Whoever asked is owed an answer before somebody else grabs it.
      final it = owned(
        permissions: {
          OwnershipPermission.transferable,
          OwnershipPermission.requestRequired,
        },
      )..request(3);
      expect(it.give(4).refusal, OwnershipRefusal.requestPending);
      // The asker themselves may still be handed it.
      expect(it.give(3).granted, isTrue);
    });
  });

  group('sessionOwner', () {
    test('only the session owner may hold it', () {
      final it = owned(
        permissions: {
          OwnershipPermission.sessionOwner,
          OwnershipPermission.transferable,
        },
      );
      expect(
        it.give(3, sessionOwner: 1).refusal,
        OwnershipRefusal.sessionOwnerOnly,
      );
      expect(it.give(1, sessionOwner: 1).granted, isTrue);
    });

    test('and nobody else may even ask', () {
      final it = owned(
        permissions: {
          OwnershipPermission.sessionOwner,
          OwnershipPermission.requestRequired,
        },
      );
      expect(
        it.request(3, sessionOwner: 1).refusal,
        OwnershipRefusal.sessionOwnerOnly,
      );
    });
  });

  group('the authority overriding', () {
    test('force ignores every rule, because it is not a transfer', () {
      // What happens when a client leaves and the object has to go somewhere.
      final it = owned(locked: true)..request(3);
      expect(it.give(1, force: true).granted, isTrue);
      expect(it.owner, 1);
      expect(it.pendingRequestFrom, isNull, reason: 'the asker is moot now');
    });
  });

  test('every refusal says something useful', () {
    // "Could not take ownership" tells nobody what to do next.
    for (final refusal in OwnershipRefusal.values) {
      final message = ownershipRefusalMessage(refusal);
      expect(message, isNotEmpty, reason: refusal.name);
      expect(message, endsWith('.'), reason: refusal.name);
    }
  });

  group('the document form', () {
    test('a permission set round trips', () {
      const permissions = {
        OwnershipPermission.transferable,
        OwnershipPermission.distributable,
      };
      expect(decodeOwnership(encodeOwnership(permissions)), permissions);
    });

    test('nothing encodes to nothing', () {
      expect(encodeOwnership(const {}), '');
      expect(decodeOwnership(''), isEmpty);
    });

    test('the order is stable, so a document does not churn on save', () {
      expect(
        encodeOwnership({
          OwnershipPermission.transferable,
          OwnershipPermission.distributable,
        }),
        encodeOwnership({
          OwnershipPermission.distributable,
          OwnershipPermission.transferable,
        }),
      );
    });

    test('an unknown permission is skipped, not fatal', () {
      // A document from a newer build should lose the permission it names,
      // not the whole object.
      expect(decodeOwnership('transferable,teleportable'), {
        OwnershipPermission.transferable,
      });
    });

    test('whitespace and empties are tolerated', () {
      expect(decodeOwnership(' transferable , '), {
        OwnershipPermission.transferable,
      });
    });
  });
}
