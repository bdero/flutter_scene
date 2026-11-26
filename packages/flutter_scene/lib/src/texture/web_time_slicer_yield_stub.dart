/// Yields to the event loop on non-web platforms.
Future<void> yieldWebTimeSlice() => Future<void>.delayed(Duration.zero);
