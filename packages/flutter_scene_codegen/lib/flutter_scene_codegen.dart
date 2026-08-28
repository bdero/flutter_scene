/// Static extraction and code generation for annotated flutter_scene
/// components: parse `@SceneComponent` classes, generate their fscene
/// codecs and a project registrar, and read/write the
/// `flutter_scene_components.json` manifest.
///
/// The CLI entry point is `dart run flutter_scene_codegen:generate`.
library;

export 'src/extractor.dart'
    show
        ExtractedComponent,
        ExtractedProperty,
        ExtractionDiagnostic,
        ExtractionResult,
        ExtractionSeverity,
        extractComponents;
export 'src/generator.dart'
    show codecClassNameFor, generateCodecLibrary, generateProjectRegistrar;
export 'src/native_script_template.dart'
    show
        hookBuildsNativeComponents,
        hookWithNativeComponents,
        nativeComponentBinding,
        nativeComponentHookCall,
        nativeComponentSource;
export 'src/script_template.dart'
    show
        componentClassName,
        componentClassNameError,
        componentFileName,
        componentScriptSource,
        componentTypeTag;
export 'src/manifest.dart'
    show
        ComponentManifest,
        componentManifestFileName,
        decodeComponentManifest,
        encodeComponentManifest,
        scanPackageManifests;
export 'src/project_generator.dart'
    show ProjectGenerationResult, generateProjectComponents;
