/// Starting, joining and running a session.
///
/// Three ways in, and the difference between them is only who is authoritative
/// and who is looking:
///
///  * **Host** — this machine runs the simulation *and* plays. One process,
///    no round trip for the local player, and the cheapest thing to test with.
///  * **Server** — runs the simulation and nobody plays on it. What a
///    dedicated server is, and the only shape where the authority cannot also
///    be a cheat.
///  * **Client** — plays, and believes what it is told.
///
/// A host is a server with a player attached, which is why they share
/// everything below except that one fact.
///
/// **Approval happens before anything is spawned.** A connection is a stranger
/// until the game says otherwise: wrong build, wrong password, server full,
/// banned. Deciding after spawning would mean un-spawning, and un-spawning is
/// where the half-joined states live.
library;

import 'dart:async';

import 'package:flutter_scene/scene.dart' show Node;

import 'component_sync.dart';
import 'network_ownership.dart';
import 'network_prefabs.dart';

/// The peer id the server holds. Peer numbering starts at the authority.
const int serverPeerId = 1;

/// Which end of a session this process is.
enum NetworkRole {
  /// Simulates and plays.
  host,

  /// Simulates and does not play.
  server,

  /// Plays and believes what it is told.
  client;

  /// Whether this end decides what is true.
  bool get isAuthority => this != NetworkRole.client;

  /// Whether a player is spawned for this process itself.
  bool get hasLocalPlayer => this != NetworkRole.server;
}

/// What the game decides about one connection attempt.
class ConnectionApproval {
  const ConnectionApproval._({
    required this.approved,
    this.reason = '',
    this.spawnPlayer = true,
    this.playerType,
  });

  /// Let them in.
  ///
  /// [playerType] names the prefab to spawn for them, or null for the
  /// session's default; [spawnPlayer] false lets someone in as a spectator.
  const ConnectionApproval.approve({
    bool spawnPlayer = true,
    String? playerType,
  }) : this._(approved: true, spawnPlayer: spawnPlayer, playerType: playerType);

  /// Turn them away, saying why.
  ///
  /// The reason is required rather than optional: a refusal with no reason
  /// gives the player nothing to act on, and "could not connect" is the
  /// least useful sentence in multiplayer.
  const ConnectionApproval.reject(String reason)
    : this._(approved: false, reason: reason, spawnPlayer: false);

  /// Whether the connection is allowed.
  final bool approved;

  /// Why it was refused, shown to whoever was refused.
  final String reason;

  /// Whether to spawn a player for them.
  final bool spawnPlayer;

  /// Which prefab to spawn, or null for the session's default.
  final String? playerType;
}

/// Decides whether a connection may join, given whatever it presented.
///
/// Given the raw payload the connecting end sent — a build id, a password, a
/// ticket — because what counts as a valid one is a game's business, not this
/// layer's.
typedef ConnectionApprover =
    FutureOr<ConnectionApproval> Function(String payload);

/// One connected peer, and what was spawned for it.
class NetworkClient {
  NetworkClient({
    required this.peerId,
    this.player,
    this.replica,
    Ownership? ownership,
    this.keepOnOwnerLeave = false,
  }) : ownership = ownership ?? Ownership(owner: peerId);

  /// The peer's id. The server itself is peer 1, as dashwire numbers them.
  final int peerId;

  /// The node spawned for this peer, or null for a spectator.
  final Node? player;

  /// The replica driving that node.
  final ComponentReplica? replica;

  /// Who owns the spawned object, and what may be done about it.
  final Ownership ownership;

  /// Whether the object outlives this client.
  final bool keepOnOwnerLeave;
}

/// Two sessions started at once, or one started twice.
class SessionAlreadyRunning implements Exception {
  @override
  String toString() =>
      'flutter_scene_net: this session is already running. Stop it before '
      'starting another -- two sessions in one process would both claim to be '
      'authoritative, and the scene can only be one of them.';
}

/// A player prefab that is not in the spawn table.
class UnknownPlayerPrefab implements Exception {
  UnknownPlayerPrefab(this.typeKey, this.known);

  final String typeKey;
  final List<String> known;

  @override
  String toString() =>
      'flutter_scene_net: the player prefab "$typeKey" is not in the spawn '
      'table, so a joining client would be let in and given nothing to play. '
      'The table holds: ${known.isEmpty ? '(nothing)' : known.join(', ')}.';
}

/// The session: what is running, who is connected, and what they are playing.
///
/// Deliberately transport-free. Everything here is the decision-making — who
/// may join, what gets spawned for them, what is cleaned up when they go — and
/// none of it needs a socket to be true or to be tested. The transport plugs
/// into [admit] and [drop].
class NetworkSession {
  /// Creates a session in [role] that spawns [playerPrefab] for each player.
  ///
  /// The player prefab is checked against the spawn table now rather than at
  /// the first join: letting someone in and then having nothing to give them
  /// is a worse failure, and it happens to the player rather than the
  /// developer.
  NetworkSession({
    required this.role,
    required this.prefabs,
    required this.playerPrefab,
    this.approve,
  }) {
    if (prefabs.prefabFor(playerPrefab) == null) {
      throw UnknownPlayerPrefab(playerPrefab, prefabs.typeKeys.toList());
    }
  }

  /// Which end this is.
  final NetworkRole role;

  /// What this session can spawn.
  final NetworkPrefabs prefabs;

  /// The prefab spawned for a joining player.
  final String playerPrefab;

  /// The game's say on who may join, or null to admit everyone.
  ///
  /// Null means an open session, which is the right default for a game being
  /// built and the wrong one for a game being played. Saying so here is
  /// better than a silent allow-list nobody knows to fill in.
  final ConnectionApprover? approve;

  final Map<int, NetworkClient> _clients = {};
  bool _running = false;

  /// Whether the session has been started.
  bool get isRunning => _running;

  /// Everyone connected, including the host's own player.
  Iterable<NetworkClient> get clients => _clients.values;

  /// The peer ids connected.
  Iterable<int> get peerIds => _clients.keys;

  /// The client for [peerId], or null.
  NetworkClient? clientFor(int peerId) => _clients[peerId];

  /// Whether this end decides what is true.
  bool get isAuthority => role.isAuthority;

  /// The peer that owns the session itself. The authority, by default.
  ///
  /// Separate from "the server" because they need not be the same in every
  /// topology: a session can be hosted by one machine and run by another.
  int sessionOwner = serverPeerId;

  /// Whether [peerId] owns the object spawned for [ownerOf].
  bool ownsObjectOf(int peerId, int ownerOf) =>
      _clients[ownerOf]?.ownership.owner == peerId;

  /// Called after a player is spawned, for whatever the game wants to do with
  /// it — parent it, position it, hand it an input source.
  void Function(NetworkClient client)? onPlayerSpawned;

  /// Called before a player is removed.
  void Function(NetworkClient client)? onPlayerDespawned;

  /// Starts the session.
  void start() {
    if (_running) throw SessionAlreadyRunning();
    _running = true;
  }

  /// Stops it, dropping everyone.
  ///
  /// Everyone including the host's own player: leaving it behind would leave a
  /// node in the scene that nothing owns and no snapshot will ever update
  /// again.
  void stop() {
    for (final peerId in _clients.keys.toList()) {
      drop(peerId);
    }
    _running = false;
  }

  /// Asks the game whether [payload] may join.
  ///
  /// Only the authority answers this. A client asking itself whether someone
  /// else may join is a client deciding something it does not get to decide.
  Future<ConnectionApproval> vet(String payload) async {
    if (!isAuthority) {
      return const ConnectionApproval.reject(
        'Only the server decides who may join.',
      );
    }
    if (!_running) {
      return const ConnectionApproval.reject('The session is not running.');
    }
    final approver = approve;
    if (approver == null) return const ConnectionApproval.approve();
    return approver(payload);
  }

  /// Admits [peerId] under [approval], spawning their player.
  ///
  /// Returns the client, or null when the approval was a refusal. Admitting
  /// the same peer twice returns the client it already has rather than
  /// spawning a second player for them.
  NetworkClient? admit(int peerId, ConnectionApproval approval) {
    if (!approval.approved) return null;
    final existing = _clients[peerId];
    if (existing != null) return existing;

    if (!approval.spawnPlayer) {
      // A spectator: connected, counted, and given nothing to drive.
      return _clients[peerId] = NetworkClient(peerId: peerId);
    }

    final typeKey = approval.playerType ?? playerPrefab;
    final prefab = prefabs.prefabFor(typeKey);
    if (prefab == null) {
      throw UnknownPlayerPrefab(typeKey, prefabs.typeKeys.toList());
    }
    final replica = prefabs.replicaFor(typeKey)!..owner = peerId;
    final player = prefabs.spawn(replica);
    final client = NetworkClient(
      peerId: peerId,
      player: player,
      replica: replica,
      ownership: Ownership(owner: peerId, permissions: prefab.ownership),
      keepOnOwnerLeave: prefab.keepOnOwnerLeave,
    );
    _clients[peerId] = client;
    onPlayerSpawned?.call(client);
    return client;
  }

  /// Hands the object spawned for [objectOf] to [peerId].
  ///
  /// Only the authority may: deciding on a client and announcing it is how two
  /// clients end up each believing they own the same crate.
  OwnershipOutcome giveOwnership(int objectOf, int peerId) {
    final client = _clients[objectOf];
    if (client == null) {
      return const OwnershipOutcome.refused(
        OwnershipRefusal.notTransferable,
        serverPeerId,
      );
    }
    if (!isAuthority) {
      return OwnershipOutcome.refused(
        OwnershipRefusal.notAuthority,
        client.ownership.owner,
      );
    }
    final outcome = client.ownership.give(peerId, sessionOwner: sessionOwner);
    if (outcome.granted) client.replica?.owner = peerId;
    return outcome;
  }

  /// Asks the owner of [objectOf]'s object to hand it to [peerId].
  OwnershipOutcome requestOwnership(int objectOf, int peerId) {
    final client = _clients[objectOf];
    if (client == null) {
      return const OwnershipOutcome.refused(
        OwnershipRefusal.notTransferable,
        serverPeerId,
      );
    }
    return client.ownership.request(peerId, sessionOwner: sessionOwner);
  }

  /// The owner's answer to a pending request on [objectOf]'s object.
  OwnershipOutcome answerOwnershipRequest(
    int objectOf, {
    required bool approve,
  }) {
    final client = _clients[objectOf];
    if (client == null) {
      return const OwnershipOutcome.refused(
        OwnershipRefusal.notTransferable,
        serverPeerId,
      );
    }
    final outcome = client.ownership.answerRequest(approve: approve);
    if (outcome.granted) client.replica?.owner = outcome.owner;
    return outcome;
  }

  /// Removes [peerId] and whatever was spawned for them.
  ///
  /// Detaches the node from the scene as well as forgetting it: a player that
  /// left and whose body stayed is the bug people report as ghosts.
  void drop(int peerId) {
    final client = _clients.remove(peerId);
    if (client == null) return;

    // An object somebody merely happened to be holding stays in the world and
    // passes to the authority; an object that *was* them goes with them. Most
    // owned objects are the second kind -- their character, their cursor --
    // which is why keeping it is the opt-in.
    if (client.keepOnOwnerLeave && client.player != null) {
      client.ownership.give(sessionOwner, force: true);
      client.replica?.owner = sessionOwner;
      onOwnerLeft?.call(client);
      return;
    }

    onPlayerDespawned?.call(client);
    client.replica?.unbind();
    client.player?.detach();
  }

  /// Called when an object outlived the client that owned it.
  ///
  /// It is still in the scene and now belongs to the authority, which is a
  /// different event from a despawn and wants a different reaction: a dropped
  /// weapon should probably keep falling, not vanish.
  void Function(NetworkClient client)? onOwnerLeft;
}
