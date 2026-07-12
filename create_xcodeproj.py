#!/usr/bin/env python3
import hashlib
import os
import shutil

def gen_id(seed):
    h = hashlib.md5(seed.encode('utf-8')).hexdigest()
    return h[:24].upper()

def main():
    print("=== Generating DeveloperChatbot Xcode Project ===")
    
    files = [
        "APIManager.swift",
        "App.swift",
        "AppNavigation.swift",
        "AppSidebarView.swift",
        "AudioPlayer.swift",
        "AudioRecorder.swift",
        "AudioStorage.swift",
        "ChatChromeViews.swift",
        "ChatShellView.swift",
        "ChatToolsMenu.swift",
        "ChatViewModel.swift",
        "ContentView.swift",
        "EndpointConfigViews.swift",
        "FlashcardsShellView.swift",
        "HomeHubView.swift",
        "DatabaseManager.swift",
        "SystemPromptModalView.swift",
        "EssentialVocabCatalog.swift",
        "EssentialVocabListView.swift",
        "EssentialVocabModels.swift",
        "EssentialVocabViewModel.swift",
        "LifePathCatalog.swift",
        "LifePathModels.swift",
        "LifePathViewModel.swift",
        "LifePathViews.swift",
        "Flashcard.swift",
        "FlashcardCreateSheet.swift",
        "FlashcardDeckView.swift",
        "FlashcardReviewView.swift",
        "FlashcardTranslator.swift",
        "FlashcardViewModel.swift",
        "FSRSManager.swift",
        "Localization.swift",
        "Platform+Colors.swift",
        "PracticeCardGenerator.swift",
        "PracticePack.swift",
        "PracticeScaffolding.swift",
        "PracticePreviewSheet.swift",
        "PracticeSessionView.swift",
        "SelectableMessageText.swift",
        "SpeakingPromptBuilder.swift",
        "SpeakingSession.swift",
        "SpeakingSessionDebugView.swift",
        "SpeakingSessionView.swift",
        "SpeakingSessionViewModel.swift",
        "SpeakingSetupSheet.swift",
        "SpeakingTargetTracker.swift",
        "SpeechCorrection.swift",
        "String+Pinyin.swift",
        "WebSocketManager.swift",
    ]

    resource_files = [
        "EssentialVocab/manifest.json",
        "EssentialVocab/essential_zh_v1.json",
        "EssentialVocab/essential_en_v1.json",
        "LifePath/life_path_manifest.json",
        "LifePath/life_path_zh_v1.json",
        "LifePath/life_path_en_v1.json",
    ]
    
    # Generate UUIDs
    main_group_id = gen_id("main_group")
    sources_group_id = gen_id("sources_group")
    products_group_id = gen_id("products_group")
    product_app_file_ref = gen_id("product_app_file_ref")
    project_id = gen_id("project")
    sources_build_phase = gen_id("sources_build_phase")
    frameworks_build_phase = gen_id("frameworks_build_phase")
    resources_build_phase = gen_id("resources_build_phase")
    target_id = gen_id("target")
    resources_group_id = gen_id("resources_group")
    essential_vocab_group_id = gen_id("essential_vocab_group")
    life_path_group_id = gen_id("life_path_group")
    
    project_config_list = gen_id("project_config_list")
    project_config_debug = gen_id("project_config_debug")
    project_config_release = gen_id("project_config_release")
    
    target_config_list = gen_id("target_config_list")
    target_config_debug = gen_id("target_config_debug")
    target_config_release = gen_id("target_config_release")

    package_ref_id = gen_id("package_swift_fsrs")
    fsrs_product_dep_id = gen_id("package_product_fsrs")
    fsrs_framework_build_id = gen_id("build_file_fsrs_framework")
    
    # Build sections
    build_files_content = []
    file_refs_content = []
    sources_phase_files = []
    
    for f in files:
        file_ref = gen_id(f"file_ref_{f}")
        build_file = gen_id(f"build_file_{f}")
        
        build_files_content.append(f"\t\t{build_file} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {f} */; }};")
        file_refs_content.append(f"\t\t{file_ref} /* {f} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; name = \"{f}\"; path = \"Sources/{f}\"; sourceTree = \"<group>\"; }};")
        sources_phase_files.append(f"\t\t\t\t{build_file} /* {f} in Sources */,")

    resources_phase_files = []
    essential_vocab_children = []
    life_path_children = []
    for rf in resource_files:
        name = os.path.basename(rf)
        file_ref = gen_id(f"file_ref_res_{rf}")
        build_file = gen_id(f"build_file_res_{rf}")
        if name.endswith(".json"):
            ftype = "text.json"
        elif name.endswith(".md"):
            ftype = "net.daringfireball.markdown"
        else:
            ftype = "text"
        build_files_content.append(f"\t\t{build_file} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};")
        file_refs_content.append(f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = {ftype}; name = \"{name}\"; path = \"Sources/{rf}\"; sourceTree = \"<group>\"; }};")
        resources_phase_files.append(f"\t\t\t\t{build_file} /* {name} in Resources */,")
        if rf.startswith("LifePath/"):
            life_path_children.append(f"\t\t\t\t{file_ref} /* {name} */,")
        else:
            essential_vocab_children.append(f"\t\t\t\t{file_ref} /* {name} */,")

    # Add the App Product File Reference
    file_refs_content.append(f"\t\t{product_app_file_ref} /* DeveloperChatbot.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DeveloperChatbot.app; sourceTree = BUILT_PRODUCTS_DIR; }};")

    build_files_content.append(
        f"\t\t{fsrs_framework_build_id} /* FSRS in Frameworks */ = {{isa = PBXBuildFile; productRef = {fsrs_product_dep_id} /* FSRS */; }};"
    )
    
    # Format list of sources children
    sources_children = []
    for f in files:
        file_ref = gen_id(f"file_ref_{f}")
        sources_children.append(f"\t\t\t\t{file_ref} /* {f} */,")
        
    # Join list contents outside of the f-string to avoid syntax error on backslashes in braces
    build_files_str = "\n".join(build_files_content)
    file_refs_str = "\n".join(file_refs_content)
    sources_phase_files_str = "\n".join(sources_phase_files)
    sources_children_str = "\n".join(sources_children)
    resources_phase_files_str = "\n".join(resources_phase_files)
    essential_vocab_children_str = "\n".join(essential_vocab_children)
    life_path_children_str = "\n".join(life_path_children)
        
    pbxproj_content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{build_files_str}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_refs_str}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{frameworks_build_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{fsrs_framework_build_id} /* FSRS in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{main_group_id} = {{
			isa = PBXGroup;
			children = (
				{sources_group_id} /* Sources */,
				{resources_group_id} /* Resources */,
				{products_group_id} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{sources_group_id} /* Sources */ = {{
			isa = PBXGroup;
			children = (
{sources_children_str}
			);
			name = Sources;
			sourceTree = "<group>";
		}};
		{resources_group_id} /* Resources */ = {{
			isa = PBXGroup;
			children = (
				{essential_vocab_group_id} /* EssentialVocab */,
				{life_path_group_id} /* LifePath */,
			);
			name = Resources;
			sourceTree = "<group>";
		}};
		{essential_vocab_group_id} /* EssentialVocab */ = {{
			isa = PBXGroup;
			children = (
{essential_vocab_children_str}
			);
			name = EssentialVocab;
			sourceTree = "<group>";
		}};
		{life_path_group_id} /* LifePath */ = {{
			isa = PBXGroup;
			children = (
{life_path_children_str}
			);
			name = LifePath;
			sourceTree = "<group>";
		}};
		{products_group_id} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{product_app_file_ref} /* DeveloperChatbot.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{target_id} /* DeveloperChatbot */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "DeveloperChatbot" */;
			buildPhases = (
				{sources_build_phase} /* Sources */,
				{frameworks_build_phase} /* Frameworks */,
				{resources_build_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = DeveloperChatbot;
			packageProductDependencies = (
				{fsrs_product_dep_id} /* FSRS */,
			);
			productName = DeveloperChatbot;
			productReference = {product_app_file_ref} /* DeveloperChatbot.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{target_id} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "DeveloperChatbot" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {main_group_id};
			packageReferences = (
				{package_ref_id} /* XCRemoteSwiftPackageReference "swift-fsrs" */,
			);
			productRefGroup = {products_group_id} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{target_id} /* DeveloperChatbot */,
			);
		}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		{sources_build_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_phase_files_str}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXResourcesBuildPhase section */
		{resources_build_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{resources_phase_files_str}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{project_config_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_PREPROCESSOR_DEFINITIONS = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{project_config_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_PREPROCESSOR_DEFINITIONS = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			}};
			name = Release;
		}};
		{target_config_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_ASSETS = "";
				DEVELOPMENT_TEAM = F6UY7NRNYA;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleVersion = 1;
				INFOPLIST_KEY_CFBundleShortVersionString = 1.0;
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app needs access to your microphone to transcribe your speech into text for the chatbot.";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.developer.DeveloperChatbot;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.9;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Debug;
		}};
		{target_config_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_ASSETS = "";
				DEVELOPMENT_TEAM = F6UY7NRNYA;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleVersion = 1;
				INFOPLIST_KEY_CFBundleShortVersionString = 1.0;
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app needs access to your microphone to transcribe your speech into text for the chatbot.";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.developer.DeveloperChatbot;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.9;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCRemoteSwiftPackageReference section */
		{package_ref_id} /* XCRemoteSwiftPackageReference "swift-fsrs" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/open-spaced-repetition/swift-fsrs.git";
			requirement = {{
				kind = branch;
				branch = main;
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{fsrs_product_dep_id} /* FSRS */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {package_ref_id} /* XCRemoteSwiftPackageReference "swift-fsrs" */;
			productName = FSRS;
		}};
/* End XCSwiftPackageProductDependency section */

/* Begin XCConfigurationList section */
		{project_config_list} /* Build configuration list for PBXProject "DeveloperChatbot" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{project_config_debug} /* Debug */,
				{project_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{target_config_list} /* Build configuration list for PBXNativeTarget "DeveloperChatbot" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{target_config_debug} /* Debug */,
				{target_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""
    
    # Create directories
    os.makedirs("DeveloperChatbot.xcodeproj", exist_ok=True)
    os.makedirs("DeveloperChatbot.xcodeproj/project.xcworkspace", exist_ok=True)
    os.makedirs("DeveloperChatbot.xcodeproj/xcshareddata/xcschemes", exist_ok=True)
    swiftpm_dir = "DeveloperChatbot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
    os.makedirs(swiftpm_dir, exist_ok=True)
    if os.path.exists("Package.resolved"):
        shutil.copy("Package.resolved", os.path.join(swiftpm_dir, "Package.resolved"))
    
    # Write pbxproj
    with open("DeveloperChatbot.xcodeproj/project.pbxproj", "w") as f:
        f.write(pbxproj_content)
    
    # Write workspace contents
    workspace_content = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    with open("DeveloperChatbot.xcodeproj/project.xcworkspace/contents.xcworkspacedata", "w") as f:
        f.write(workspace_content)
        
    # Write scheme
    scheme_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "DeveloperChatbot.app"
               BlueprintName = "DeveloperChatbot"
               ReferencedContainer = "container:DeveloperChatbot.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useLaunchSchemeArgsEnv = "YES"
      askForAppToLaunch = "NO"
      runOnlyForDeploymentPostprocessing = "NO"
      targetInfo = "0">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "DeveloperChatbot.app"
            BlueprintName = "DeveloperChatbot"
            ReferencedContainer = "container:DeveloperChatbot.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useLaunchSchemeArgsEnv = "YES"
      runOnlyForDeploymentPostprocessing = "NO">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "DeveloperChatbot.app"
            BlueprintName = "DeveloperChatbot"
            ReferencedContainer = "container:DeveloperChatbot.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    with open("DeveloperChatbot.xcodeproj/xcshareddata/xcschemes/DeveloperChatbot.xcscheme", "w") as f:
        f.write(scheme_content)
        
    print("=== Xcode Project & Shared Scheme Generated Successfully ===")

if __name__ == "__main__":
    main()
