// Hand-written FFI bindings for the subset of the FMOD Core and FMOD
// Studio C APIs this backend uses. Symbols are looked up lazily from a
// user-supplied SDK (see FmodLibrary), so merely importing this file
// never touches native code.
//
// All handles are opaque pointers. Functions return FMOD_RESULT;
// callers go through [FmodBindings.check].

// The C API names are kept verbatim, and the signature typedefs are
// deliberately library-private.
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: library_private_types_in_public_api

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_scene_fmod/src/ffi/fmod_library.dart';

/// The FMOD header version these bindings target (2.03.00). Passed to
/// system creation; FMOD fails with a header-mismatch error when the
/// user's SDK is incompatible, in which case construct the engine with
/// the matching version.
const int kFmodDefaultHeaderVersion = 0x00020300;

// FMOD_RESULT values this backend special-cases.
const int fmodOk = 0;
const int fmodErrInvalidHandle = 30;
const int fmodErrChannelStolen = 3;

// FMOD_MODE flags (fmod_common.h).
const int fmodLoopOff = 0x00000001;
const int fmodLoopNormal = 0x00000002;
const int fmod2d = 0x00000008;
const int fmod3d = 0x00000010;
const int fmodCreateSample = 0x00000100;
const int fmod3dInverseRolloff = 0x00100000;
const int fmod3dLinearRolloff = 0x00200000;
const int fmod3dInverseTaperedRolloff = 0x00800000;

// FMOD_STUDIO_* constants (fmod_studio_common.h).
const int fmodStudioInitNormal = 0;
const int fmodStudioInitLiveUpdate = 1;
const int fmodInitNormal = 0;
const int fmodStudioLoadBankNormal = 0;
const int fmodStudioLoadMemory = 0;
const int fmodStudioStopAllowFadeout = 0;
const int fmodStudioStopImmediate = 1;
const int fmodTimeUnitMs = 0x1;

/// FMOD_STUDIO_PLAYBACK_STATE.
const int fmodStudioPlaybackPlaying = 0;
const int fmodStudioPlaybackSustaining = 1;
const int fmodStudioPlaybackStopped = 2;
const int fmodStudioPlaybackStarting = 3;
const int fmodStudioPlaybackStopping = 4;

/// FMOD_STUDIO_EVENT_PROPERTY indices for distance overrides.
const int fmodStudioEventPropertyMinDistance = 3;
const int fmodStudioEventPropertyMaxDistance = 4;

final class FmodVector extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
  @Float()
  external double z;
}

final class Fmod3dAttributes extends Struct {
  external FmodVector position;
  external FmodVector velocity;
  external FmodVector forward;
  external FmodVector up;
}

/// A failed FMOD call.
class FmodException implements Exception {
  FmodException(this.operation, this.result);

  final String operation;

  /// The FMOD_RESULT error code; see fmod_common.h for meanings.
  final int result;

  @override
  String toString() => 'FmodException($operation failed, FMOD_RESULT $result)';
}

typedef _R1<A> = Int32 Function(A);
typedef _D1<A> = int Function(A);
typedef _R2<A, B> = Int32 Function(A, B);
typedef _D2<A, B> = int Function(A, B);
typedef _R3<A, B, C> = Int32 Function(A, B, C);
typedef _D3<A, B, C> = int Function(A, B, C);

/// Looked-up FMOD entry points over an opened [FmodLibrary].
class FmodBindings {
  FmodBindings(FmodLibrary library)
    : Studio_System_Create = library.studio
          .lookupFunction<
            _R2<Pointer<Pointer<Void>>, Uint32>,
            _D2<Pointer<Pointer<Void>>, int>
          >('FMOD_Studio_System_Create'),
      Studio_System_Initialize = library.studio
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Uint32, Uint32, Pointer<Void>),
            int Function(Pointer<Void>, int, int, int, Pointer<Void>)
          >('FMOD_Studio_System_Initialize'),
      Studio_System_Release = library.studio
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Studio_System_Release',
          ),
      Studio_System_Update = library.studio
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Studio_System_Update',
          ),
      Studio_System_GetCoreSystem = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Pointer<Void>>>,
            _D2<Pointer<Void>, Pointer<Pointer<Void>>>
          >('FMOD_Studio_System_GetCoreSystem'),
      Studio_System_LoadBankFile = library.studio
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Uint32,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              int,
              Pointer<Pointer<Void>>,
            )
          >('FMOD_Studio_System_LoadBankFile'),
      Studio_System_LoadBankMemory = library.studio
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Int32,
              Int32,
              Uint32,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              int,
              int,
              Pointer<Pointer<Void>>,
            )
          >('FMOD_Studio_System_LoadBankMemory'),
      Studio_System_GetEvent = library.studio
          .lookupFunction<
            _R3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>,
            _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
          >('FMOD_Studio_System_GetEvent'),
      Studio_System_GetBus = library.studio
          .lookupFunction<
            _R3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>,
            _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
          >('FMOD_Studio_System_GetBus'),
      Studio_System_SetListenerAttributes = library.studio
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Pointer<Fmod3dAttributes>,
              Pointer<FmodVector>,
            ),
            int Function(
              Pointer<Void>,
              int,
              Pointer<Fmod3dAttributes>,
              Pointer<FmodVector>,
            )
          >('FMOD_Studio_System_SetListenerAttributes'),
      Studio_Bank_Unload = library.studio
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Studio_Bank_Unload',
          ),
      Studio_Bus_SetVolume = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Studio_Bus_SetVolume'),
      Studio_EventDescription_CreateInstance = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Pointer<Void>>>,
            _D2<Pointer<Void>, Pointer<Pointer<Void>>>
          >('FMOD_Studio_EventDescription_CreateInstance'),
      Studio_EventInstance_Start = library.studio
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Studio_EventInstance_Start',
          ),
      Studio_EventInstance_Stop = library.studio
          .lookupFunction<_R2<Pointer<Void>, Int32>, _D2<Pointer<Void>, int>>(
            'FMOD_Studio_EventInstance_Stop',
          ),
      Studio_EventInstance_Release = library.studio
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Studio_EventInstance_Release',
          ),
      Studio_EventInstance_SetPaused = library.studio
          .lookupFunction<_R2<Pointer<Void>, Int32>, _D2<Pointer<Void>, int>>(
            'FMOD_Studio_EventInstance_SetPaused',
          ),
      Studio_EventInstance_SetVolume = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Studio_EventInstance_SetVolume'),
      Studio_EventInstance_SetPitch = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Studio_EventInstance_SetPitch'),
      Studio_EventInstance_Set3DAttributes = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Fmod3dAttributes>>,
            _D2<Pointer<Void>, Pointer<Fmod3dAttributes>>
          >('FMOD_Studio_EventInstance_Set3DAttributes'),
      Studio_EventInstance_SetParameterByName = library.studio
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Float, Int32),
            int Function(Pointer<Void>, Pointer<Utf8>, double, int)
          >('FMOD_Studio_EventInstance_SetParameterByName'),
      Studio_EventInstance_GetPlaybackState = library.studio
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Int32>>,
            _D2<Pointer<Void>, Pointer<Int32>>
          >('FMOD_Studio_EventInstance_GetPlaybackState'),
      Studio_EventInstance_SetProperty = library.studio
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Float),
            int Function(Pointer<Void>, int, double)
          >('FMOD_Studio_EventInstance_SetProperty'),
      System_GetMasterChannelGroup = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Pointer<Void>>>,
            _D2<Pointer<Void>, Pointer<Pointer<Void>>>
          >('FMOD_System_GetMasterChannelGroup'),
      System_CreateSound = library.core
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Uint32,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              int,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >('FMOD_System_CreateSound'),
      System_PlaySound = library.core
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Int32,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<Pointer<Void>>,
            )
          >('FMOD_System_PlaySound'),
      System_CreateChannelGroup = library.core
          .lookupFunction<
            _R3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>,
            _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
          >('FMOD_System_CreateChannelGroup'),
      Sound_Release = library.core
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Sound_Release',
          ),
      Sound_GetLength = library.core
          .lookupFunction<
            _R3<Pointer<Void>, Pointer<Uint32>, Uint32>,
            int Function(Pointer<Void>, Pointer<Uint32>, int)
          >('FMOD_Sound_GetLength'),
      ChannelGroup_SetVolume = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_ChannelGroup_SetVolume'),
      ChannelGroup_AddGroup = library.core
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Int32,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<Pointer<Void>>,
            )
          >('FMOD_ChannelGroup_AddGroup'),
      ChannelGroup_SetPaused = library.core
          .lookupFunction<_R2<Pointer<Void>, Int32>, _D2<Pointer<Void>, int>>(
            'FMOD_ChannelGroup_SetPaused',
          ),
      Channel_Stop = library.core
          .lookupFunction<_R1<Pointer<Void>>, _D1<Pointer<Void>>>(
            'FMOD_Channel_Stop',
          ),
      Channel_SetPaused = library.core
          .lookupFunction<_R2<Pointer<Void>, Int32>, _D2<Pointer<Void>, int>>(
            'FMOD_Channel_SetPaused',
          ),
      Channel_SetVolume = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Channel_SetVolume'),
      Channel_SetPitch = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Channel_SetPitch'),
      Channel_SetMode = library.core
          .lookupFunction<_R2<Pointer<Void>, Uint32>, _D2<Pointer<Void>, int>>(
            'FMOD_Channel_SetMode',
          ),
      Channel_IsPlaying = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Int32>>,
            _D2<Pointer<Void>, Pointer<Int32>>
          >('FMOD_Channel_IsPlaying'),
      Channel_Set3DAttributes = library.core
          .lookupFunction<
            _R3<Pointer<Void>, Pointer<FmodVector>, Pointer<FmodVector>>,
            _D3<Pointer<Void>, Pointer<FmodVector>, Pointer<FmodVector>>
          >('FMOD_Channel_Set3DAttributes'),
      Channel_Set3DMinMaxDistance = library.core
          .lookupFunction<
            Int32 Function(Pointer<Void>, Float, Float),
            int Function(Pointer<Void>, double, double)
          >('FMOD_Channel_Set3DMinMaxDistance'),
      Channel_Set3DDopplerLevel = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Float>,
            int Function(Pointer<Void>, double)
          >('FMOD_Channel_Set3DDopplerLevel'),
      Channel_SetChannelGroup = library.core
          .lookupFunction<
            _R2<Pointer<Void>, Pointer<Void>>,
            _D2<Pointer<Void>, Pointer<Void>>
          >('FMOD_Channel_SetChannelGroup');

  final _D2<Pointer<Pointer<Void>>, int> Studio_System_Create;
  final int Function(Pointer<Void>, int, int, int, Pointer<Void>)
  Studio_System_Initialize;
  final _D1<Pointer<Void>> Studio_System_Release;
  final _D1<Pointer<Void>> Studio_System_Update;
  final _D2<Pointer<Void>, Pointer<Pointer<Void>>> Studio_System_GetCoreSystem;
  final int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Pointer<Void>>)
  Studio_System_LoadBankFile;
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    int,
    Pointer<Pointer<Void>>,
  )
  Studio_System_LoadBankMemory;
  final _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
  Studio_System_GetEvent;
  final _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
  Studio_System_GetBus;
  final int Function(
    Pointer<Void>,
    int,
    Pointer<Fmod3dAttributes>,
    Pointer<FmodVector>,
  )
  Studio_System_SetListenerAttributes;
  final _D1<Pointer<Void>> Studio_Bank_Unload;
  final int Function(Pointer<Void>, double) Studio_Bus_SetVolume;
  final _D2<Pointer<Void>, Pointer<Pointer<Void>>>
  Studio_EventDescription_CreateInstance;
  final _D1<Pointer<Void>> Studio_EventInstance_Start;
  final _D2<Pointer<Void>, int> Studio_EventInstance_Stop;
  final _D1<Pointer<Void>> Studio_EventInstance_Release;
  final _D2<Pointer<Void>, int> Studio_EventInstance_SetPaused;
  final int Function(Pointer<Void>, double) Studio_EventInstance_SetVolume;
  final int Function(Pointer<Void>, double) Studio_EventInstance_SetPitch;
  final _D2<Pointer<Void>, Pointer<Fmod3dAttributes>>
  Studio_EventInstance_Set3DAttributes;
  final int Function(Pointer<Void>, Pointer<Utf8>, double, int)
  Studio_EventInstance_SetParameterByName;
  final _D2<Pointer<Void>, Pointer<Int32>>
  Studio_EventInstance_GetPlaybackState;
  final int Function(Pointer<Void>, int, double)
  Studio_EventInstance_SetProperty;
  final _D2<Pointer<Void>, Pointer<Pointer<Void>>> System_GetMasterChannelGroup;
  final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    int,
    Pointer<Void>,
    Pointer<Pointer<Void>>,
  )
  System_CreateSound;
  final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<Pointer<Void>>,
  )
  System_PlaySound;
  final _D3<Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>>
  System_CreateChannelGroup;
  final _D1<Pointer<Void>> Sound_Release;
  final int Function(Pointer<Void>, Pointer<Uint32>, int) Sound_GetLength;
  final int Function(Pointer<Void>, double) ChannelGroup_SetVolume;
  final int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Pointer<Void>>)
  ChannelGroup_AddGroup;
  final _D2<Pointer<Void>, int> ChannelGroup_SetPaused;
  final _D1<Pointer<Void>> Channel_Stop;
  final _D2<Pointer<Void>, int> Channel_SetPaused;
  final int Function(Pointer<Void>, double) Channel_SetVolume;
  final int Function(Pointer<Void>, double) Channel_SetPitch;
  final _D2<Pointer<Void>, int> Channel_SetMode;
  final _D2<Pointer<Void>, Pointer<Int32>> Channel_IsPlaying;
  final _D3<Pointer<Void>, Pointer<FmodVector>, Pointer<FmodVector>>
  Channel_Set3DAttributes;
  final int Function(Pointer<Void>, double, double) Channel_Set3DMinMaxDistance;
  final int Function(Pointer<Void>, double) Channel_Set3DDopplerLevel;
  final _D2<Pointer<Void>, Pointer<Void>> Channel_SetChannelGroup;

  /// Throws [FmodException] when [result] is not FMOD_OK.
  void check(int result, String operation) {
    if (result != fmodOk) throw FmodException(operation, result);
  }

  /// Like [check], but treats an invalid or stolen channel handle as a
  /// clean "finished" signal (returns false) instead of an error.
  bool checkChannel(int result, String operation) {
    if (result == fmodOk) return true;
    if (result == fmodErrInvalidHandle || result == fmodErrChannelStolen) {
      return false;
    }
    throw FmodException(operation, result);
  }
}
