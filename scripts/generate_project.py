"""Generate the small Xcode project without requiring a global XcodeGen install."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "BikeNavi.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = []


def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(name, body):
    key = ident(name)
    objects.append(f"{key} = {{ {body} }};")
    return key


files = sorted((ROOT / "ios/BikeNavi").rglob("*.swift")) + sorted((ROOT / "ios/Shared").rglob("*.swift"))
refs, builds = [], []
file_refs = {}
for path in files:
    relative = path.relative_to(ROOT).as_posix()
    ref = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    file_refs[relative] = ref
    builds.append(obj(relative + "/build", f"isa = PBXBuildFile; fileRef = {ref};"))
app = obj("app", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = BikeNavi.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_app = obj("ui-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = BikeNaviUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
test_ref = obj("ui-test-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = tests/UI/PlannerUITests.swift; sourceTree = SOURCE_ROOT;')
refs.append(test_ref)
widget_files = sorted((ROOT / "ios/BikeNaviWidget").rglob("*.swift"))
widget_builds = []
for path in widget_files:
    relative = path.relative_to(ROOT).as_posix()
    ref = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    file_refs[relative] = ref
    widget_builds.append(obj(relative + "/widget-build", f"isa = PBXBuildFile; fileRef = {ref};"))
for path in sorted((ROOT / "ios/Shared").rglob("*.swift")):
    relative = path.relative_to(ROOT).as_posix()
    widget_builds.append(obj(relative + "/widget-build", f"isa = PBXBuildFile; fileRef = {file_refs[relative]};"))
package = obj("maplibre-package", 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/maplibre/maplibre-gl-native-distribution"; requirement = { kind = exactVersion; version = 6.31.0; };')
product = obj("maplibre-product", f"isa = XCSwiftPackageProductDependency; package = {package}; productName = MapLibre;")
framework = obj("maplibre-build", f"isa = PBXBuildFile; productRef = {product};")
frameworks = obj("frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework},); runOnlyForDeploymentPostprocessing = 0;")
sources = obj("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(builds)},); runOnlyForDeploymentPostprocessing = 0;")
assets = obj("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = ios/BikeNavi/Assets.xcassets; sourceTree = SOURCE_ROOT;')
refs.append(assets)
asset_build = obj("assets-build", f"isa = PBXBuildFile; fileRef = {assets};")
resources = obj("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({asset_build},); runOnlyForDeploymentPostprocessing = 0;")
widget_app = obj("widget-product", 'isa = PBXFileReference; explicitFileType = wrapper.app-extension; path = BikeNaviLiveActivity.appex; sourceTree = BUILT_PRODUCTS_DIR;')
widget_sources = obj("widget-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(widget_builds)},); runOnlyForDeploymentPostprocessing = 0;")
widget_frameworks = obj("widget-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
widget_resources = obj("widget-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
products = obj("products", f"isa = PBXGroup; children = ({app},{widget_app},{test_app},); name = Products; sourceTree = \"<group>\";")
group = obj("group", f"isa = PBXGroup; children = ({','.join(refs + [products])},); sourceTree = \"<group>\";")
settings = '''
    CLANG_ENABLE_MODULES = YES;
    SWIFT_VERSION = 5.0;
    IPHONEOS_DEPLOYMENT_TARGET = 17.0;
    SDKROOT = iphoneos;
    TARGETED_DEVICE_FAMILY = 1;
    PRODUCT_BUNDLE_IDENTIFIER = de.michaelhein.BikeNavi;
    PRODUCT_NAME = "$(TARGET_NAME)";
    INFOPLIST_FILE = ios/BikeNavi/Info.plist;
    MARKETING_VERSION = 0.1.0;
    CURRENT_PROJECT_VERSION = 1;
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    CODE_SIGN_STYLE = Automatic;
    GENERATE_INFOPLIST_FILE = NO;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
    ENABLE_USER_SCRIPT_SANDBOXING = YES;
    SWIFT_EMIT_LOC_STRINGS = YES;
'''
configs = []
for name in ["Debug", "Release"]:
    extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name == "Debug" else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    configs.append(obj("config" + name, f"isa = XCBuildConfiguration; name = {name}; buildSettings = {{{settings} {extra} }};"))
config_list = obj("config-list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
widget_configs = []
for name in ["Debug", "Release"]:
    widget_extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name == "Debug" else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    widget_configs.append(obj("widget-config-" + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
        PRODUCT_BUNDLE_IDENTIFIER = de.michaelhein.BikeNavi.LiveActivity;
        PRODUCT_NAME = BikeNaviLiveActivity;
        INFOPLIST_FILE = ios/BikeNaviWidget/Info.plist;
        MARKETING_VERSION = 0.1.0;
        CURRENT_PROJECT_VERSION = 1;
        SWIFT_VERSION = 5.0;
        IPHONEOS_DEPLOYMENT_TARGET = 17.0;
        SDKROOT = iphoneos;
        TARGETED_DEVICE_FAMILY = 1;
        CODE_SIGN_STYLE = Automatic;
        GENERATE_INFOPLIST_FILE = NO;
        APPLICATION_EXTENSION_API_ONLY = YES;
        SKIP_INSTALL = YES;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
        {widget_extra}
        }};'''))
widget_config_list = obj("widget-config-list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(widget_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
widget_target = obj("widget-target", f'isa = PBXNativeTarget; buildConfigurationList = {widget_config_list}; buildPhases = ({widget_sources},{widget_frameworks},{widget_resources},); buildRules = (); dependencies = (); name = BikeNaviLiveActivity; packageProductDependencies = (); productName = BikeNaviLiveActivity; productReference = {widget_app}; productType = "com.apple.product-type.app-extension";')
widget_proxy = obj("widget-proxy", f"isa = PBXContainerItemProxy; containerPortal = {ident('project')}; proxyType = 1; remoteGlobalIDString = {widget_target}; remoteInfo = BikeNaviLiveActivity;")
widget_dependency = obj("widget-dependency", f"isa = PBXTargetDependency; target = {widget_target}; targetProxy = {widget_proxy};")
widget_embed_build = obj("widget-embed-build", f"isa = PBXBuildFile; fileRef = {widget_app}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};")
embed_extensions = obj("embed-extensions", f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({widget_embed_build},); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
target = obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = ({sources},{frameworks},{resources},{embed_extensions},); buildRules = (); dependencies = ({widget_dependency},); name = BikeNavi; packageProductDependencies = ({product},); productName = BikeNavi; productReference = {app}; productType = "com.apple.product-type.application";')
test_build = obj("ui-test-build", f"isa = PBXBuildFile; fileRef = {test_ref};")
test_sources = obj("ui-test-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({test_build},); runOnlyForDeploymentPostprocessing = 0;")
test_configs = []
for name in ["Debug", "Release"]:
    test_configs.append(obj("ui-config-" + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
        PRODUCT_BUNDLE_IDENTIFIER = de.michaelhein.BikeNavi.UITests;
        PRODUCT_NAME = BikeNaviUITests;
        INFOPLIST_FILE = "";
        GENERATE_INFOPLIST_FILE = YES;
        ASSETCATALOG_COMPILER_APPICON_NAME = "";
        TEST_TARGET_NAME = BikeNavi;
        SWIFT_VERSION = 5.0;
        IPHONEOS_DEPLOYMENT_TARGET = 17.0;
        CODE_SIGN_STYLE = Automatic;
        }};'''))
test_config_list = obj("ui-config-list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(test_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;")
proxy = obj("ui-test-proxy", f"isa = PBXContainerItemProxy; containerPortal = {ident('project')}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = BikeNavi;")
dependency = obj("ui-test-dependency", f"isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};")
test_target = obj("ui-test-target", f'isa = PBXNativeTarget; buildConfigurationList = {test_config_list}; buildPhases = ({test_sources},); buildRules = (); dependencies = ({dependency},); name = BikeNaviUITests; productName = BikeNaviUITests; productReference = {test_app}; productType = "com.apple.product-type.bundle.ui-testing";')
root = obj("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2610; }}; buildConfigurationList = {config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de,en,Base); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},{widget_target},{test_target},);')
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(objects) + f"\n}}; rootObject = {root}; }}\n")
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "BikeNavi.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2610" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="BikeNavi.app" BlueprintName="BikeNavi" ReferencedContainer="container:BikeNavi.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="BikeNavi.app" BlueprintName="BikeNavi" ReferencedContainer="container:BikeNavi.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="BikeNaviUITests.xctest" BlueprintName="BikeNaviUITests" ReferencedContainer="container:BikeNavi.xcodeproj"/></TestableReference></Testables></TestAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f"Generated {PROJECT.name} with {len(files)} Swift files")
