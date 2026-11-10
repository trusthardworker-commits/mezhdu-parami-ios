"""Generate the dependency-free Xcode project using only the Python standard library."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
objects = {}

class Ref(str):
    pass

def oid(name):
    return Ref(hashlib.sha1(name.encode()).hexdigest()[:24].upper())

def add(object_key, isa, **values):
    key = oid(object_key)
    objects[key] = dict(isa=isa, **values)
    return key

def render(value, level=0):
    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, dict):
        return "{\n" + "".join("\t"*(level+1)+str(k)+" = "+render(v, level+1)+";\n" for k,v in value.items()) + "\t"*level+"}"
    if isinstance(value, list):
        return "("+", ".join(render(v, level) for v in value)+("," if value else "")+")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)

files = {}
def file(path, kind):
    ref = add(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")
    files[path] = ref
    return ref

for path, kind in [
    ("Shared/ScheduleCore.swift", "sourcecode.swift"),
    ("ScheduleApp/ScheduleApp.swift", "sourcecode.swift"),
    ("ScheduleWidget/ScheduleWidget.swift", "sourcecode.swift"),
    ("ScheduleApp/Resources/schedule.json", "text.json"),
    ("ScheduleApp/Resources/timetable.pdf", "image.pdf"),
    ("ScheduleApp/Resources/academic-weeks.pdf", "image.pdf"),
    ("ScheduleApp/Assets.xcassets", "folder.assetcatalog"),
    ("Configuration/Shared.xcconfig", "text.xcconfig"),
    ("Shared/PrivacyInfo.xcprivacy", "text.xml"),
    ("ScheduleApp/Info.plist", "text.plist.xml"),
    ("ScheduleWidget/Info.plist", "text.plist.xml"),
    ("Configuration/App.entitlements", "text.plist.entitlements"),
    ("Configuration/Widget.entitlements", "text.plist.entitlements"),
]:
    file(path, kind)

app_product = add("app-product", "PBXFileReference", explicitFileType="wrapper.application", path="ScheduleApp.app", sourceTree="BUILT_PRODUCTS_DIR")
widget_product = add("widget-product", "PBXFileReference", explicitFileType="wrapper.app-extension", path="ScheduleWidget.appex", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[app_product, widget_product], name="Products", sourceTree="<group>")
main = add("main", "PBXGroup", children=list(files.values())+[products], sourceTree="<group>")

def phase(target, isa, paths, **kwargs):
    buildfiles = [add(target+":"+p, "PBXBuildFile", fileRef=files[p]) for p in paths]
    return add(target+isa, isa, buildActionMask=2147483647, files=buildfiles, runOnlyForDeploymentPostprocessing=0, **kwargs)

def configurations(name, settings, base=False):
    refs = []
    for config in ["Debug", "Release"]:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if config=="Debug" else "-O",
                      DEBUG_INFORMATION_FORMAT="dwarf" if config=="Debug" else "dwarf-with-dsym")
        if config == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) DEBUG"
            values["ENABLE_TESTABILITY"] = "YES"
        extra = dict(baseConfigurationReference=files["Configuration/Shared.xcconfig"]) if base else {}
        refs.append(add(name+config, "XCBuildConfiguration", buildSettings=values, name=config, **extra))
    return add(name+"config-list", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_config = configurations("project", dict(
    CLANG_ENABLE_MODULES="YES", SWIFT_VERSION="5.0", IPHONEOS_DEPLOYMENT_TARGET="17.0",
    SDKROOT="iphoneos", TARGETED_DEVICE_FAMILY="1", CODE_SIGN_STYLE="Automatic",
    CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="1.0", ENABLE_USER_SCRIPT_SANDBOXING="YES",
    SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SUPPORTS_MACCATALYST="NO"))

common = dict(GENERATE_INFOPLIST_FILE="NO", PRODUCT_NAME="$(TARGET_NAME)",
              LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"])
app_config = configurations("app", dict(common, PRODUCT_BUNDLE_IDENTIFIER="$(APP_BUNDLE_IDENTIFIER)",
    INFOPLIST_FILE="ScheduleApp/Info.plist", CODE_SIGN_ENTITLEMENTS="Configuration/App.entitlements",
    ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon"), True)
widget_config = configurations("widget", dict(common, PRODUCT_BUNDLE_IDENTIFIER="$(APP_BUNDLE_IDENTIFIER).widget",
    INFOPLIST_FILE="ScheduleWidget/Info.plist", CODE_SIGN_ENTITLEMENTS="Configuration/Widget.entitlements",
    APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]), True)

widget_id = oid("widget-target")
project_id = oid("project")
proxy = add("dependency-proxy", "PBXContainerItemProxy", containerPortal=project_id,
            proxyType=1, remoteGlobalIDString=widget_id, remoteInfo="ScheduleWidget")
dependency = add("dependency", "PBXTargetDependency", target=widget_id, targetProxy=proxy)
embedfile = add("embed-widget-file", "PBXBuildFile", fileRef=widget_product, settings={"ATTRIBUTES":["RemoveHeadersOnCopy"]})
embed = add("embed-widget", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13,
            files=[embedfile], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)

app = add("app-target", "PBXNativeTarget", buildConfigurationList=app_config,
    buildPhases=[phase("app", "PBXSourcesBuildPhase", ["Shared/ScheduleCore.swift", "ScheduleApp/ScheduleApp.swift"]),
                 phase("app", "PBXFrameworksBuildPhase", []),
                 phase("app", "PBXResourcesBuildPhase", ["ScheduleApp/Resources/schedule.json", "ScheduleApp/Resources/timetable.pdf", "ScheduleApp/Resources/academic-weeks.pdf", "ScheduleApp/Assets.xcassets", "Shared/PrivacyInfo.xcprivacy"]), embed],
    buildRules=[], dependencies=[dependency], name="ScheduleApp", productName="ScheduleApp",
    productReference=app_product, productType="com.apple.product-type.application")
widget = add("widget-target", "PBXNativeTarget", buildConfigurationList=widget_config,
    buildPhases=[phase("widget", "PBXSourcesBuildPhase", ["Shared/ScheduleCore.swift", "ScheduleWidget/ScheduleWidget.swift"]),
                 phase("widget", "PBXFrameworksBuildPhase", []),
                 phase("widget", "PBXResourcesBuildPhase", ["ScheduleApp/Resources/schedule.json", "Shared/PrivacyInfo.xcprivacy"])],
    buildRules=[], dependencies=[], name="ScheduleWidget", productName="ScheduleWidget",
    productReference=widget_product, productType="com.apple.product-type.app-extension")
add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel":"YES", "LastUpgradeCheck":"1600"},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="ru",
    hasScannedForEncodings=0, knownRegions=["ru", "en", "Base"], mainGroup=main,
    productRefGroup=products, projectDirPath="", projectRoot="", targets=[app, widget])

directory = ROOT / "Schedule.xcodeproj"
directory.mkdir(exist_ok=True)
(directory/"project.pbxproj").write_text("// !$*UTF8*$!\n"+render(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id))+"\n", encoding="utf-8")
schemes = directory / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ScheduleApp.app" BlueprintName="ScheduleApp" ReferencedContainer="container:Schedule.xcodeproj"/>'
(schemes/"ScheduleApp.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")

base_plist = dict(CFBundleDevelopmentRegion="ru", CFBundleExecutable="$(EXECUTABLE_NAME)",
    CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)", CFBundleInfoDictionaryVersion="6.0",
    CFBundleName="$(PRODUCT_NAME)", CFBundleShortVersionString="$(MARKETING_VERSION)",
    CFBundleVersion="$(CURRENT_PROJECT_VERSION)", CFBundleDisplayName="Между парами")
app_info = dict(base_plist, CFBundlePackageType="APPL", LSRequiresIPhoneOS=True,
    UILaunchScreen={}, UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes":False},
    UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"],
    CFBundleURLTypes=[dict(CFBundleURLName="schedule", CFBundleURLSchemes=["fiteuschedule"])])
widget_info = dict(base_plist, CFBundlePackageType="XPC!", NSExtension={"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"})
for path, contents in [("ScheduleApp/Info.plist", app_info), ("ScheduleWidget/Info.plist", widget_info)]:
    (ROOT/path).write_bytes(plistlib.dumps(contents, sort_keys=False))
(ROOT/"Configuration").mkdir(exist_ok=True)
for name in ["App", "Widget"]:
    (ROOT/f"Configuration/{name}.entitlements").write_bytes(plistlib.dumps({}))
print("Generated Schedule.xcodeproj with app, embedded widget, shared scheme, plists and entitlements.")
