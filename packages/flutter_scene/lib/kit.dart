/// High-level gameplay, camera, character, environment, audio, and debug utilities for Flutter Scene.
///
/// Import this barrel to access ready-to-use game components:
/// - [CameraRig] to assemble a whole camera in one call, per kind of game.
/// - [SpringArmComponent] and [CameraShake] for camera rigs.
/// - [ThirdPersonControllerComponent] and [Steering] for character motion.
/// - [DayNightCycleComponent] and [WaterSurfaceComponent] for atmospheric environments.
/// - [weatherPresets] and [setSceneWeather] to put a sky into named weather.
/// - [SoundManager] and [SurfaceFootstepAudio] for game sound.
/// - [NodePool] and [PoissonDiscSampler] for object recycling and spawning.
/// - [ScenePicker], [SceneSelection], and [PathFollowerComponent] for
///   click-to-select and click-to-move.
/// - [DebugDraw] and [PerformanceOverlay3D] for immediate-mode visualization.
library;

export 'src/kit/audio/sound_manager.dart' show SoundManager;
export 'src/kit/audio/surface_footstep_audio.dart'
    show SurfaceFootstepAudio, SurfaceMaterialType;
export 'src/kit/camera/bounds_framing.dart' show BoundsFraming;
export 'src/kit/camera/camera_rig.dart' show CameraRig;
export 'src/kit/camera/camera_shake.dart' show CameraShake, CameraShakeOffset;
export 'src/kit/camera/spring_arm_component.dart' show SpringArmComponent;
export 'src/kit/camera/virtual_joystick.dart'
    show JoystickCallback, VirtualJoystick;
export 'src/kit/character/steering_behaviors.dart' show Steering;
export 'src/kit/character/third_person_controller.dart'
    show ThirdPersonControllerComponent;
export 'src/kit/debug/debug_draw.dart' show DebugDraw;
export 'src/kit/interaction/path_follower_component.dart'
    show PathFollowerComponent;
export 'src/kit/interaction/scene_picker.dart' show ScenePicker;
export 'src/kit/interaction/scene_selection.dart' show SceneSelection;
export 'src/kit/debug/performance_overlay_3d.dart' show PerformanceOverlay3D;
export 'src/kit/environment/day_night_cycle_component.dart'
    show AtmosphericLighting, DayNightCycleComponent;
export 'src/kit/environment/floating_motion_component.dart'
    show FloatingMotionComponent;
export 'src/kit/environment/lightning_component.dart'
    show LightningComponent, LightningStrike, sunDirectionForHour;
export 'src/kit/environment/water_component.dart'
    show WaterComponent, WaterStyle, WaterTraversal;
export 'src/kit/environment/buoyancy_component.dart' show BuoyancyComponent;
export 'src/kit/environment/gerstner_field.dart' show GerstnerField;
export 'src/kit/environment/wind.dart' show Wind;
export 'src/kit/environment/wind_component.dart'
    show WindComponent, windVelocity;
export 'src/kit/environment/weather.dart'
    show
        WeatherPreset,
        setSceneWeather,
        setWaterChoppiness,
        weatherPresetById,
        weatherPresets;
export 'src/kit/environment/water_surface_component.dart'
    show GerstnerWave, WaterSurfaceComponent;
export 'src/kit/pooling/node_pool.dart' show NodePool;
export 'src/kit/pooling/volume_spawner.dart' show PoissonDiscSampler;
