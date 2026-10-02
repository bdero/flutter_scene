#!/usr/bin/env bash
# Chrome with extra flags from CHROME_EXTRA_FLAGS, for CHROME_EXECUTABLE.
# flutter test has no browser-flag option, so the WebGPU CI probe injects
# flags through this wrapper.
exec google-chrome $CHROME_EXTRA_FLAGS "$@"
