/// Who owns a networked object, and what may be done about it.
///
/// Ownership is not just bookkeeping: it decides who may write the properties
/// marked owner-writable and who may send the events marked owner-only. So the
/// rules for changing it are a security surface, and every refusal below is a
/// rule rather than an inconvenience.
///
/// An object declares what is *allowed*, not what happens. A crate that anyone
/// may pick up says so; a player's own character says nothing, and is therefore
/// static — nobody takes it, nobody asks for it, and it stays where the session
/// put it. Saying nothing being the locked-down case is deliberate: the safe
/// default should be the one you get by not thinking about it.
library;

/// What an object permits to be done with its ownership.
///
/// A set rather than one value, because these compose: a crate can be both
/// takeable by anyone and redistributed when its owner leaves, and those are
/// different questions.
enum OwnershipPermission {
  /// The session may hand it to someone else on its own when a client joins or
  /// leaves.
  ///
  /// For objects that need *an* owner but not a particular one: a physics prop
  /// that somebody has to simulate.
  distributable,

  /// Any client may take it outright, without asking.
  ///
  /// For things where the contest is the point and the loser finding out a
  /// moment later is fine: a dropped weapon, a control point.
  transferable,

  /// A client must ask the current owner, who may refuse.
  ///
  /// For things where being interrupted matters — a vehicle someone is
  /// driving, a turret someone is firing.
  requestRequired,

  /// Only whoever owns the session may hold it.
  ///
  /// For objects that *are* the session: the match state, the round timer.
  sessionOwner,
}

/// Why an attempt to take or grant ownership was refused.
enum OwnershipRefusal {
  /// The object is locked by its owner.
  locked,

  /// The object permits no transfer at all.
  notTransferable,

  /// It must be asked for rather than taken.
  requestRequired,

  /// Somebody is already asking, and is entitled to an answer first.
  requestPending,

  /// Only the session owner may hold it.
  sessionOwnerOnly,

  /// The asker already owns it.
  alreadyOwner,

  /// The session is not the authority, so it does not get to decide.
  notAuthority,
}

/// What a refusal should say to whoever hit it.
String ownershipRefusalMessage(OwnershipRefusal refusal) => switch (refusal) {
  OwnershipRefusal.locked =>
    'Its owner has locked it, so it cannot change hands until they unlock it.',
  OwnershipRefusal.notTransferable =>
    'It does not permit its ownership to change. Mark it transferable or '
        'requestRequired if it should.',
  OwnershipRefusal.requestRequired =>
    'It has to be asked for rather than taken. Send a request instead.',
  OwnershipRefusal.requestPending =>
    'Somebody is already asking for it, and is owed an answer first.',
  OwnershipRefusal.sessionOwnerOnly => 'Only the session owner may hold it.',
  OwnershipRefusal.alreadyOwner => 'It is already theirs.',
  OwnershipRefusal.notAuthority => 'Only the authority decides who owns what.',
};

/// The result of trying to change ownership.
class OwnershipOutcome {
  const OwnershipOutcome._(this.granted, this.refusal, this.owner);

  /// It changed hands (or, for a request, the request was sent).
  const OwnershipOutcome.granted(int owner) : this._(true, null, owner);

  /// It did not, for [refusal].
  const OwnershipOutcome.refused(OwnershipRefusal refusal, int owner)
    : this._(false, refusal, owner);

  /// Whether the attempt succeeded.
  final bool granted;

  /// Why not, when it did not.
  final OwnershipRefusal? refusal;

  /// Who owns the object now, either way.
  final int owner;

  /// What to show whoever tried.
  String get message =>
      granted ? 'Owned by $owner.' : ownershipRefusalMessage(refusal!);

  @override
  String toString() => granted
      ? 'OwnershipOutcome.granted($owner)'
      : 'OwnershipOutcome.refused(${refusal!.name})';
}

/// One object's ownership, and the rules it plays by.
///
/// Pure state and pure decisions. Nothing here sends anything: the authority
/// runs these and then tells everyone, which is the only order that works —
/// deciding on a client and announcing it is how two clients end up each
/// believing they own the same crate.
class Ownership {
  Ownership({
    required this.owner,
    Set<OwnershipPermission> permissions = const {},
    this.locked = false,
  }) : permissions = Set.unmodifiable(permissions);

  /// The peer that owns it. The server is peer 1.
  int owner;

  /// What is permitted. Empty means static: nobody takes it, nobody asks.
  final Set<OwnershipPermission> permissions;

  /// Whether the owner has pinned it in place.
  ///
  /// A lock outranks every permission, including [OwnershipPermission
  /// .transferable]: it is the owner saying "not right now" about a thing that
  /// is normally free to take, which is what you want while driving the car
  /// everyone else may drive.
  bool locked;

  int? _pendingFrom;

  /// Who is currently asking, or null.
  int? get pendingRequestFrom => _pendingFrom;

  /// Whether anybody may hold this but the session owner.
  bool get isSessionOwnerOnly =>
      permissions.contains(OwnershipPermission.sessionOwner);

  /// Whether the session may reassign it on its own.
  bool get isDistributable =>
      permissions.contains(OwnershipPermission.distributable);

  /// Hands it to [peerId] outright.
  ///
  /// [sessionOwner] is who currently owns the session, needed only to enforce
  /// [OwnershipPermission.sessionOwner]. [force] is the authority overriding
  /// the rules — used when a client leaves and the object has to go somewhere,
  /// which is not a transfer anybody asked for.
  OwnershipOutcome give(int peerId, {int? sessionOwner, bool force = false}) {
    if (force) {
      _pendingFrom = null;
      owner = peerId;
      return OwnershipOutcome.granted(owner);
    }
    if (peerId == owner) {
      return OwnershipOutcome.refused(OwnershipRefusal.alreadyOwner, owner);
    }
    if (isSessionOwnerOnly && peerId != sessionOwner) {
      return OwnershipOutcome.refused(OwnershipRefusal.sessionOwnerOnly, owner);
    }
    if (locked) {
      return OwnershipOutcome.refused(OwnershipRefusal.locked, owner);
    }
    if (_pendingFrom != null && _pendingFrom != peerId) {
      return OwnershipOutcome.refused(OwnershipRefusal.requestPending, owner);
    }
    if (!permissions.contains(OwnershipPermission.transferable)) {
      // Asking is still open if the object allows it: a refusal that names the
      // way forward beats one that just says no.
      return OwnershipOutcome.refused(
        permissions.contains(OwnershipPermission.requestRequired)
            ? OwnershipRefusal.requestRequired
            : OwnershipRefusal.notTransferable,
        owner,
      );
    }
    _pendingFrom = null;
    owner = peerId;
    return OwnershipOutcome.granted(owner);
  }

  /// Asks the current owner for it on [peerId]'s behalf.
  ///
  /// Succeeding here means the request was *sent*, not that it was granted;
  /// the owner answers with [answerRequest].
  OwnershipOutcome request(int peerId, {int? sessionOwner}) {
    if (peerId == owner) {
      return OwnershipOutcome.refused(OwnershipRefusal.alreadyOwner, owner);
    }
    if (isSessionOwnerOnly && peerId != sessionOwner) {
      return OwnershipOutcome.refused(OwnershipRefusal.sessionOwnerOnly, owner);
    }
    if (locked) {
      return OwnershipOutcome.refused(OwnershipRefusal.locked, owner);
    }
    if (!permissions.contains(OwnershipPermission.requestRequired)) {
      // Either it is free to take, in which case asking is the wrong verb, or
      // it is static. Both are worth saying differently.
      return OwnershipOutcome.refused(
        permissions.contains(OwnershipPermission.transferable)
            ? OwnershipRefusal.alreadyOwner
            : OwnershipRefusal.notTransferable,
        owner,
      );
    }
    if (_pendingFrom != null) {
      return OwnershipOutcome.refused(OwnershipRefusal.requestPending, owner);
    }
    _pendingFrom = peerId;
    return OwnershipOutcome.granted(owner);
  }

  /// The owner's answer to the pending request.
  ///
  /// Granting locks the object, because an object that had to be asked for is
  /// one where being interrupted matters — handing it over and leaving it
  /// free for the next taker defeats the point of having asked.
  OwnershipOutcome answerRequest({required bool approve}) {
    final asker = _pendingFrom;
    if (asker == null) {
      return OwnershipOutcome.refused(OwnershipRefusal.notTransferable, owner);
    }
    _pendingFrom = null;
    if (!approve) {
      return OwnershipOutcome.refused(OwnershipRefusal.locked, owner);
    }
    owner = asker;
    locked = true;
    return OwnershipOutcome.granted(owner);
  }

  /// Withdraws a pending request, for an asker who left or changed their mind.
  void cancelRequest() => _pendingFrom = null;

  /// Pins it in place, or releases it.
  void setLocked(bool value) => locked = value;
}
