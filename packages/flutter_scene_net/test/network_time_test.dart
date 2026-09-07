// Network time. Two machines can agree on a tick number and cannot agree on a
// clock, so everything that has to agree across machines is counted in ticks.

import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a point in time', () {
    test('seconds are derived, so every machine agrees on them', () {
      // A measured clock would not agree. This one is arithmetic on a number
      // both ends were sent.
      const time = NetworkTime(tick: 60, tickRate: 30);
      expect(time.seconds, 2);
      expect(time.fixedDelta, closeTo(1 / 30, 1e-12));
    });

    test('advancing counts ticks, not seconds', () {
      const start = NetworkTime(tick: 10, tickRate: 60);
      expect((start + 5).tick, 15);
      expect((start + 5).tickRate, 60);
    });

    test('the gap between two times is signed', () {
      // Negative is the normal case on a client: the authority's last word is
      // always a little behind where the client has simulated to.
      const local = NetworkTime(tick: 100, tickRate: 50);
      const server = NetworkTime(tick: 94, tickRate: 50);
      expect(local.ticksAhead(server), 6);
      expect(server.ticksAhead(local), -6);
      expect(local.secondsAhead(server), closeTo(0.12, 1e-12));
    });

    test('two times at the same tick and rate are the same time', () {
      expect(
        const NetworkTime(tick: 7, tickRate: 30),
        const NetworkTime(tick: 7, tickRate: 30),
      );
      expect(
        const NetworkTime(tick: 7, tickRate: 30),
        isNot(const NetworkTime(tick: 7, tickRate: 60)),
      );
    });
  });

  group('the clock', () {
    test('starts at zero on both sides', () {
      final clock = NetworkClock(tickRate: 30);
      expect(clock.local.tick, 0);
      expect(clock.server.tick, 0);
      expect(clock.lag, 0);
    });

    test('local time advances a tick at a time', () {
      final clock = NetworkClock(tickRate: 30);
      for (var i = 0; i < 5; i++) {
        clock.advance();
      }
      expect(clock.local.tick, 5);
    });

    test('lag is how far behind the authority’s last word is', () {
      final clock = NetworkClock(tickRate: 50);
      for (var i = 0; i < 10; i++) {
        clock.advance();
      }
      clock.observeServerTick(6);
      expect(clock.server.tick, 6);
      expect(clock.lag, closeTo(4 / 50, 1e-12));
    });

    test('an out-of-order snapshot does not rewind the clock', () {
      // Snapshots ride an unreliable channel, so an older one can arrive after
      // a newer one; letting it rewind would make everything derived jump.
      final clock = NetworkClock(tickRate: 30)..observeServerTick(20);
      clock.observeServerTick(14);
      expect(clock.server.tick, 20);
    });

    test('a client behind the server is pulled forward, not left negative', () {
      // Being behind what the authority has already sent is being behind.
      final clock = NetworkClock(tickRate: 30)..observeServerTick(40);
      expect(clock.local.tick, 40);
      expect(clock.lag, 0);
    });

    test('joining in progress starts both clocks where the session is', () {
      final clock = NetworkClock(tickRate: 60)..resetTo(9000);
      expect(clock.local.tick, 9000);
      expect(clock.server.tick, 9000);
      expect(clock.lag, 0);
    });

    test('the rate is fixed, because it is part of what was agreed', () {
      // A client counting at a different rate reads every stamp wrong.
      final clock = NetworkClock(tickRate: 30);
      expect(clock.local.tickRate, 30);
      expect(clock.server.tickRate, 30);
    });
  });
}
