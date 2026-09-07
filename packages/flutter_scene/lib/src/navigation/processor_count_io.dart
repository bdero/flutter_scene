/// Native: the platform's own count.
library;

import 'dart:io' show Platform;

int platformProcessorCount() => Platform.numberOfProcessors;
