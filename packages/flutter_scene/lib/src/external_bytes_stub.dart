import 'package:flutter/foundation.dart';

/// Does nothing on the web, whose collector takes no external size.
@internal
void statesExternalBytes(Object owner, int bytes) {}

/// Always 0 on the web.
@visibleForTesting
int debugStatedExternalBytes(Object owner) => 0;
