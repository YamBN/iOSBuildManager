#!/usr/bin/env python3
"""Generates iOSBuildManager.xcodeproj/project.pbxproj deterministically.

Run:  python3 scripts/generate_pbxproj.py
Re-run any time Swift files are added/removed.
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ_DIR = os.path.join(ROOT, "iOSBuildManager", "iOSBuildManager.xcodeproj")
PBXPROJ = os.path.join(PROJ_DIR, "project.pbxproj")

SRC_ROOT = "iOSBuildManager"  # folder under the .xcodeproj's parent containing sources


def uid(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


# ---- Source tree -----------------------------------------------------------
# Each entry: (group_name, folder_name, [files], [subgroups])
VIEWS_SUB = [
    ("Components", ["GlassComponents.swift", "EmptyStateView.swift"]),
    ("Dashboard", ["DashboardView.swift"]),
    ("Builds", ["BuildsView.swift"]),
    ("Devices", ["DevicesView.swift"]),
    ("Profiles", ["ProfilesView.swift"]),
    ("Certificates", ["CertificatesView.swift"]),
    ("Settings", ["SettingsView.swift"]),
    ("Logs", ["LogsView.swift"]),
]

GROUPS = [
    ("App", ["AppModel.swift"], []),
    ("Models", ["AppVersion.swift", "BuildRecord.swift", "BuildSettings.swift",
                "BuildStatus.swift", "Project.swift", "SidebarSection.swift",
                "ProvisioningProfile.swift", "SigningIdentity.swift",
                "SigningHealth.swift"], []),
    ("Services", ["BuildEngine.swift", "BuildError.swift", "BuildHistoryStore.swift",
                  "DeviceService.swift", "FinderActions.swift", "IPAPackager.swift",
                  "Paths.swift", "ProcessStreaming.swift", "ProjectStore.swift",
                  "SchedulerService.swift", "ScriptGenerator.swift", "SettingsStore.swift",
                  "ShellRunner.swift", "XcodeBuildService.swift",
                  "ProvisioningProfileService.swift", "CertificateService.swift",
                  "NotificationService.swift"], []),
    ("Theme", ["Theme.swift"], []),
    ("Views", ["ContentView.swift", "Sidebar.swift"], VIEWS_SUB),
]

TOP_FILES = ["iOSBuildManagerApp.swift"]
RES_FILES = ["Assets.xcassets"]  # lives in Resources/

PRODUCT_NAME = "iOSBuildManager"
BUNDLE_ID = "com.rontop.iOSBuildManager"
ENTITLEMENTS = "iOSBuildManager/iOSBuildManager.entitlements"
INFOPLIST = "iOSBuildManager/Info.plist"

# Unit test target (hosted in the app so @testable import works).
TEST_TARGET_NAME = "iOSBuildManagerTests"
TEST_ROOT = "iOSBuildManagerTests"  # sibling folder of SRC_ROOT
TEST_FILES = ["ParsingTests.swift", "PackagingTests.swift"]
TEST_BUNDLE_ID = "com.rontop.iOSBuildManagerTests"


def collect(node, prefix, files_out, groups_out, is_views_root=False):
    """Recursively collect file fullpaths and group fullpaths."""
    name, files = node[0], node[1]
    subs = node[2] if len(node) > 2 else []
    gpath = f"{prefix}/{name}" if name else prefix
    groups_out.append(gpath)
    for f in files:
        files_out.append((f"{gpath}/{f}", f))
    for sub in subs:
        collect(sub, gpath, files_out, groups_out)


def main():
    main_group_uid = uid("group:main")
    src_group_uid = uid("group:src")
    products_group_uid = uid("group:products")
    resources_group_uid = uid("group:" + f"{SRC_ROOT}/Resources")
    app_ref_uid = uid("fileref:product.app")
    info_ref_uid = uid("fileref:Info.plist")
    ent_ref_uid = uid("fileref:entitlements")

    file_paths = []  # (fullpath, basename)
    group_paths = []  # full group paths
    # top source files live directly in src group
    for f in TOP_FILES:
        file_paths.append((f"{SRC_ROOT}/{f}", f))
    # resources group files
    for f in RES_FILES:
        file_paths.append((f"{SRC_ROOT}/Resources/{f}", f))
    # nested groups
    for g in GROUPS:
        collect(g, SRC_ROOT, file_paths, group_paths)
    # Also register the Resources group path and Views group path (already added by collect for Views)
    # ensure resources group is tracked
    group_paths.append(f"{SRC_ROOT}/Resources")

    # file refs and build files
    file_refs = {}  # fullpath -> uid
    build_files = {}  # fullpath -> uid
    for full, base in file_paths:
        file_refs[full] = uid("fileref:" + full)
        if full.endswith(".swift") or full.endswith(".xcassets"):
            build_files[full] = uid("buildfile:" + full)

    group_uids = {p: uid("group:" + p) for p in group_paths}

    # build phase UIDs
    sources_phase = uid("phase:sources")
    resources_phase = uid("phase:resources")
    frameworks_phase = uid("phase:frameworks")
    native_target = uid("target:native")
    project_uid = uid("project")
    project_cfglist = uid("cfglist:project")
    target_cfglist = uid("cfglist:target")
    cfg_project_debug = uid("cfg:project:debug")
    cfg_project_release = uid("cfg:project:release")
    cfg_target_debug = uid("cfg:target:debug")
    cfg_target_release = uid("cfg:target:release")

    # test target UIDs
    tests_group_uid = uid("group:tests")
    test_target = uid("target:tests")
    test_product_ref = uid("fileref:product.xctest")
    tests_sources_phase = uid("phase:tests:sources")
    tests_frameworks_phase = uid("phase:tests:frameworks")
    test_cfglist = uid("cfglist:tests")
    cfg_tests_debug = uid("cfg:tests:debug")
    cfg_tests_release = uid("cfg:tests:release")
    test_dependency = uid("dep:tests->app")
    test_container_proxy = uid("proxy:tests->app")

    test_file_refs = {f: uid(f"fileref:{TEST_ROOT}/{f}") for f in TEST_FILES}
    test_build_files = {f: uid(f"buildfile:{TEST_ROOT}/{f}") for f in TEST_FILES}

    # ---- PBXBuildFile section ----
    build_file_lines = []
    for full in build_files:
        build_file_lines.append(
            f"\t\t{build_files[full]} /* {full.split('/')[-1]} in {'Sources' if full.endswith('.swift') else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {file_refs[full]} /* {full.split('/')[-1]} */; }};")
    for f in TEST_FILES:
        build_file_lines.append(
            f"\t\t{test_build_files[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {test_file_refs[f]} /* {f} */; }};")
    # asset catalog build file
    asset_full = f"{SRC_ROOT}/Resources/Assets.xcassets"
    asset_build = build_files[asset_full]

    # ---- PBXFileReference section ----
    file_ref_lines = []
    for full, base in file_paths:
        if full.endswith(".swift"):
            ftype = "sourcecode.swift"
        elif full.endswith(".xcassets"):
            ftype = "folder.assetcatalog"
        elif full.endswith(".entitlements"):
            ftype = "text.plist.entitlements"
        elif full == f"{SRC_ROOT}/Info.plist" or base == "Info.plist":
            ftype = "text.plist.xml"
        else:
            ftype = "file"
        file_ref_lines.append(
            f"\t\t{file_refs[full]} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = \"{base}\"; sourceTree = \"<group>\"; }};")
    file_ref_lines.append(
        f"\t\t{app_ref_uid} /* {PRODUCT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PRODUCT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    file_ref_lines.append(
        f"\t\t{info_ref_uid} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    file_ref_lines.append(
        f"\t\t{ent_ref_uid} /* {PRODUCT_NAME}.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {PRODUCT_NAME}.entitlements; sourceTree = \"<group>\"; }};")
    for f in TEST_FILES:
        file_ref_lines.append(
            f"\t\t{test_file_refs[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{f}\"; sourceTree = \"<group>\"; }};")
    file_ref_lines.append(
        f"\t\t{test_product_ref} /* {TEST_TARGET_NAME}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_TARGET_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")

    # ---- Group children ----
    def group_children_for(gpath):
        children = []
        for full, base in file_paths:
            parent = "/".join(full.split("/")[:-1])
            if parent == gpath:
                children.append(file_refs[full])
        # subgroups
        for gp in group_paths:
            if gp == gpath:
                continue
            if "/".join(gp.split("/")[:-1]) == gpath:
                children.append(group_uids[gp])
        return children

    src_children = []
    for f in TOP_FILES:
        src_children.append(file_refs[f"{SRC_ROOT}/{f}"])
    src_children.append(info_ref_uid)
    src_children.append(ent_ref_uid)
    src_children.append(group_uids[f"{SRC_ROOT}/Resources"])
    for g in GROUPS:
        src_children.append(group_uids[f"{SRC_ROOT}/{g[0]}"])

    resources_children = [file_refs[f"{SRC_ROOT}/Resources/Assets.xcassets"]]

    def render_group(uid_, name, path, children, indent="\t\t"):
        path_line = f'path = "{path}"; ' if path else ""
        name_line = f'name = "{name}"; ' if name else ""
        lines = [f"{indent}{uid_} /* {name or path} */ = {{",
                 f"{indent}\tisa = PBXGroup;",
                 f"{indent}\tchildren = ("]
        for c in children:
            lines.append(f"{indent}\t\t{c},")
        lines.append(f"{indent}\t);")
        lines.append(f"{indent}\t{name_line}{path_line}sourceTree = \"<group>\";")
        lines.append(f"{indent}}};")
        return "\n".join(lines)

    group_lines = []
    # main group
    main_children = [src_group_uid, tests_group_uid, products_group_uid]
    group_lines.append(render_group(main_group_uid, PRODUCT_NAME, "", main_children))
    # tests group
    group_lines.append(render_group(tests_group_uid, TEST_ROOT, TEST_ROOT,
                                    [test_file_refs[f] for f in TEST_FILES]))
    # sources group
    group_lines.append(render_group(src_group_uid, SRC_ROOT, SRC_ROOT, src_children))
    # resources group
    group_lines.append(render_group(resources_group_uid, "Resources", "Resources", resources_children))
    # nested groups
    for gp in group_paths:
        if gp == f"{SRC_ROOT}/Resources":
            continue
        name = gp.split("/")[-1]
        children = group_children_for(gp)
        group_lines.append(render_group(group_uids[gp], name, name, children))
    # products group
    group_lines.append(render_group(products_group_uid, "Products", "", [app_ref_uid, test_product_ref]))

    # ---- Build phases ----
    sources_phase_lines = [
        f"\t\t{sources_phase} /* Sources */ = {{",
        "\t\t\tisa = PBXSourcesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
    ]
    for full, base in file_paths:
        if full.endswith(".swift"):
            sources_phase_lines.append(f"\t\t\t\t{build_files[full]} /* {base} in Sources */,")
    sources_phase_lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]

    resources_phase_lines = [
        f"\t\t{resources_phase} /* Resources */ = {{",
        "\t\t\tisa = PBXResourcesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        f"\t\t\t\t{asset_build} /* Assets.xcassets in Resources */,",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t};",
    ]

    frameworks_phase_lines = [
        f"\t\t{frameworks_phase} /* Frameworks */ = {{",
        "\t\t\tisa = PBXFrameworksBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t};",
        f"\t\t{tests_frameworks_phase} /* Frameworks */ = {{",
        "\t\t\tisa = PBXFrameworksBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t};",
    ]

    tests_sources_phase_lines = [
        f"\t\t{tests_sources_phase} /* Sources */ = {{",
        "\t\t\tisa = PBXSourcesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
    ]
    for f in TEST_FILES:
        tests_sources_phase_lines.append(f"\t\t\t\t{test_build_files[f]} /* {f} in Sources */,")
    tests_sources_phase_lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]

    # ---- Native target ----
    target_lines = [
        f"\t\t{native_target} /* {PRODUCT_NAME} */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {target_cfglist} /* Build configuration list for PBXNativeTarget */;",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{sources_phase} /* Sources */,",
        f"\t\t\t\t{frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        "\t\t\t);",
        f"\t\t\tname = {PRODUCT_NAME};",
        f"\t\t\tproductName = {PRODUCT_NAME};",
        f"\t\t\tproductReference = {app_ref_uid} /* {PRODUCT_NAME}.app */;",
        "\t\t\tproductType = \"com.apple.product-type.application\";",
        "\t\t};",
        f"\t\t{test_target} /* {TEST_TARGET_NAME} */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {test_cfglist} /* Build configuration list for PBXNativeTarget \"{TEST_TARGET_NAME}\" */;",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{tests_sources_phase} /* Sources */,",
        f"\t\t\t\t{tests_frameworks_phase} /* Frameworks */,",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        f"\t\t\t\t{test_dependency} /* PBXTargetDependency */,",
        "\t\t\t);",
        f"\t\t\tname = {TEST_TARGET_NAME};",
        f"\t\t\tproductName = {TEST_TARGET_NAME};",
        f"\t\t\tproductReference = {test_product_ref} /* {TEST_TARGET_NAME}.xctest */;",
        "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";",
        "\t\t};",
    ]

    # ---- Target dependency (tests -> app) ----
    container_proxy_lines = [
        f"\t\t{test_container_proxy} /* PBXContainerItemProxy */ = {{",
        "\t\t\tisa = PBXContainerItemProxy;",
        f"\t\t\tcontainerPortal = {project_uid} /* Project object */;",
        "\t\t\tproxyType = 1;",
        f"\t\t\tremoteGlobalIDString = {native_target};",
        f"\t\t\tremoteInfo = {PRODUCT_NAME};",
        "\t\t};",
    ]
    target_dependency_lines = [
        f"\t\t{test_dependency} /* PBXTargetDependency */ = {{",
        "\t\t\tisa = PBXTargetDependency;",
        f"\t\t\ttarget = {native_target} /* {PRODUCT_NAME} */;",
        f"\t\t\ttargetProxy = {test_container_proxy} /* PBXContainerItemProxy */;",
        "\t\t};",
    ]

    # ---- Build configurations ----
    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_C_LANGUAGE_STANDARD": "gnu17",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADERS": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEAD_CODE_STRIPPING": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "MTL_FAST_MATH": "YES",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "macosx",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_VERSION": "6.0",
    }

    project_debug = dict(common_project)
    project_release = dict(common_project)
    project_release["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    project_release["ENABLE_TESTABILITY"] = "NO"
    project_release["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
    project_release["ONLY_ACTIVE_ARCH"] = "NO"

    common_target = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": ENTITLEMENTS,
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Automatic",
        "COMBINE_HIDPI_IMAGES": "YES",
        "ENABLE_APP_SANDBOX": "NO",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": INFOPLIST,
        "INFOPLIST_KEY_LS_APPLICATION_CATEGORY_TYPE": "public.app-category.developer-tools",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "Local-only developer tool. No analytics, no tracking.",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "6.0",
        "CURRENT_PROJECT_VERSION": "1",
    }
    target_debug = dict(common_target)
    target_release = dict(common_target)
    target_debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
    target_debug["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
    target_debug["ONLY_ACTIVE_ARCH"] = "YES"
    target_debug["ENABLE_TESTABILITY"] = "YES"
    target_release["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
    target_release["ENABLE_TESTABILITY"] = "NO"
    target_release["DEBUG_INFORMATION_FORMAT"] = "dwarf"

    common_tests = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": TEST_BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_VERSION": "6.0",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{PRODUCT_NAME}.app/Contents/MacOS/{PRODUCT_NAME}",
    }
    tests_debug = dict(common_tests)
    tests_debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
    tests_debug["ONLY_ACTIVE_ARCH"] = "YES"
    tests_release = dict(common_tests)

    def quote_setting(value: str) -> str:
        # OpenStep plist barewords may only contain [A-Za-z0-9_./]; anything
        # else (including empty strings) must be quoted or Xcode fails to
        # parse the file ("damaged project" error).
        value = str(value)
        if value and re.fullmatch(r"[A-Za-z0-9_./]+", value):
            return value
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'

    def render_cfg(uid_, name, settings, comment):
        lines = [f"\t\t{uid_} /* {comment} */ = {{",
                 "\t\t\tisa = XCBuildConfiguration;",
                 f"\t\t\tbuildSettings = {{"]
        for k in settings:
            lines.append(f"\t\t\t\t{k} = {quote_setting(settings[k])};")
        lines.append("\t\t\t};")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t};")
        return "\n".join(lines)

    cfg_lines = [
        render_cfg(cfg_project_debug, "Debug", project_debug, "Project Debug"),
        render_cfg(cfg_project_release, "Release", project_release, "Project Release"),
        render_cfg(cfg_target_debug, "Debug", target_debug, "Target Debug"),
        render_cfg(cfg_target_release, "Release", target_release, "Target Release"),
        render_cfg(cfg_tests_debug, "Debug", tests_debug, "Tests Debug"),
        render_cfg(cfg_tests_release, "Release", tests_release, "Tests Release"),
    ]

    cfglist_lines = [
        f"\t\t{project_cfglist} /* Build configuration list for PBXProject */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{cfg_project_debug} /* Project Debug */,",
        f"\t\t\t\t{cfg_project_release} /* Project Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{target_cfglist} /* Build configuration list for PBXNativeTarget */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{cfg_target_debug} /* Target Debug */,",
        f"\t\t\t\t{cfg_target_release} /* Target Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{test_cfglist} /* Build configuration list for PBXNativeTarget \"{TEST_TARGET_NAME}\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{cfg_tests_debug} /* Tests Debug */,",
        f"\t\t\t\t{cfg_tests_release} /* Tests Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
    ]

    # ---- PBXProject ----
    project_lines = [
        f"\t\t{project_uid} /* Project object */ = {{",
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tLastUpgradeCheck = 1500;",
        "\t\t\t\tTargetAttributes = {",
        f"\t\t\t\t\t{native_target} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;",
        "\t\t\t\t\t};",
        f"\t\t\t\t\t{test_target} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;",
        f"\t\t\t\t\t\tTestTargetID = {native_target};",
        "\t\t\t\t\t};",
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {project_cfglist} /* Build configuration list for PBXProject */;",
        "\t\t\tcompatibilityVersion = \"Xcode 14.0\";",
        "\t\t\tdevelopmentRegion = en;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\tknownRegions = (",
        "\t\t\t\ten,",
        "\t\t\t\tBase,",
        "\t\t\t);",
        f"\t\t\tmainGroup = {main_group_uid} /* {PRODUCT_NAME} */;",
        f"\t\t\tproductRefGroup = {products_group_uid} /* Products */;",
        "\t\t\tprojectDirPath = \"\";",
        "\t\t\tprojectRoot = \"\";",
        "\t\t\ttargets = (",
        f"\t\t\t\t{native_target} /* {PRODUCT_NAME} */,",
        f"\t\t\t\t{test_target} /* {TEST_TARGET_NAME} */,",
        "\t\t\t);",
        "\t\t};",
    ]

    # ---- Assemble ----
    out = []
    out.append("// !$*UTF8*$!")
    out.append("{")
    out.append("\tarchiveVersion = 1;")
    out.append("\tclasses = {")
    out.append("\t};")
    out.append("\tobjectVersion = 60;")
    out.append("\tobjects = {")
    out.append("")
    out.append("/* Begin PBXBuildFile section */")
    out.extend(build_file_lines)
    out.append("/* End PBXBuildFile section */")
    out.append("")
    out.append("/* Begin PBXContainerItemProxy section */")
    out.extend(container_proxy_lines)
    out.append("/* End PBXContainerItemProxy section */")
    out.append("")
    out.append("/* Begin PBXFileReference section */")
    out.extend(file_ref_lines)
    out.append("/* End PBXFileReference section */")
    out.append("")
    out.append("/* Begin PBXFrameworksBuildPhase section */")
    out.extend(frameworks_phase_lines)
    out.append("/* End PBXFrameworksBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXResourcesBuildPhase section */")
    out.extend(resources_phase_lines)
    out.append("/* End PBXResourcesBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXSourcesBuildPhase section */")
    out.extend(sources_phase_lines)
    out.extend(tests_sources_phase_lines)
    out.append("/* End PBXSourcesBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXTargetDependency section */")
    out.extend(target_dependency_lines)
    out.append("/* End PBXTargetDependency section */")
    out.append("")
    out.append("/* Begin PBXNativeTarget section */")
    out.extend(target_lines)
    out.append("/* End PBXNativeTarget section */")
    out.append("")
    out.append("/* Begin PBXProject section */")
    out.extend(project_lines)
    out.append("/* End PBXProject section */")
    out.append("")
    out.append("/* Begin PBXGroup section */")
    out.extend(group_lines)
    out.append("/* End PBXGroup section */")
    out.append("")
    out.append("/* Begin XCBuildConfiguration section */")
    out.extend(cfg_lines)
    out.append("/* End XCBuildConfiguration section */")
    out.append("")
    out.append("/* Begin XCConfigurationList section */")
    out.extend(cfglist_lines)
    out.append("/* End XCConfigurationList section */")
    out.append("\t};")
    out.append("\trootObject = " + project_uid + " /* Project object */;")
    out.append("}")
    out.append("")

    os.makedirs(PROJ_DIR, exist_ok=True)
    with open(PBXPROJ, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"Wrote {PBXPROJ}")

    # ---- Shared scheme (build + test), so `xcodebuild test` works everywhere ----
    app_ref = (f'<BuildableReference BuildableIdentifier="primary" '
               f'BlueprintIdentifier="{native_target}" BuildableName="{PRODUCT_NAME}.app" '
               f'BlueprintName="{PRODUCT_NAME}" ReferencedContainer="container:{PRODUCT_NAME}.xcodeproj"/>')
    test_ref = (f'<BuildableReference BuildableIdentifier="primary" '
                f'BlueprintIdentifier="{test_target}" BuildableName="{TEST_TARGET_NAME}.xctest" '
                f'BlueprintName="{TEST_TARGET_NAME}" ReferencedContainer="container:{PRODUCT_NAME}.xcodeproj"/>')
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            {test_ref}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
"""
    schemes_dir = os.path.join(PROJ_DIR, "xcshareddata", "xcschemes")
    os.makedirs(schemes_dir, exist_ok=True)
    scheme_path = os.path.join(schemes_dir, f"{PRODUCT_NAME}.xcscheme")
    with open(scheme_path, "w", encoding="utf-8") as f:
        f.write(scheme)
    print(f"Wrote {scheme_path}")


if __name__ == "__main__":
    main()
