// swift-tools-version: 5.8

import Foundation
import PackageDescription

enum PkgConfig {
   static func hasLibrary(named libraryName: String) -> Bool {
      #if os(macOS)
      if hasMacOSBrewLibrary(named: libraryName) {
         return true
      }
      #endif

      return isPkgConfigInPATHAndHasLibrary(named: libraryName)
   }

   #if os(macOS)
   private static func hasMacOSBrewLibrary(named libraryName: String) -> Bool {
      // Hack: We need to hard-code these paths when the manifest is evaluated via Xcode
      // because Xcode does not properly set up the `PATH` environment variable.
      let executablePaths = [
         "/opt/homebrew/bin/pkg-config",
         "/usr/local/bin/pkg-config"
      ]
      for executablePath in executablePaths {
         guard FileManager.default.fileExists(atPath: executablePath) else {
            continue
         }

         let process = try! Process.run(URL(fileURLWithPath: executablePath, isDirectory: false), arguments: [
            libraryName
         ])
         process.waitUntilExit()

         return process.terminationStatus == EXIT_SUCCESS
      }

      return false
   }
   #endif

   private static func isPkgConfigInPATHAndHasLibrary(named libraryName: String) -> Bool {
      let process = try! Process.run(URL(fileURLWithPath: "/usr/bin/env", isDirectory: false), arguments: [
         "pkg-config", libraryName
      ])
      process.waitUntilExit()

      return process.terminationStatus == EXIT_SUCCESS
   }
}

extension PackageDescription.Target {
   static let cMsgpackSystemLibrary: PackageDescription.Target = {
      let pkgConfigName: String
      let subdirectory: String
      if PkgConfig.hasLibrary(named: "msgpack-c") {
         pkgConfigName = "msgpack-c"
         subdirectory = "Modern"
      } else {
         pkgConfigName = "msgpack"
         subdirectory = "Legacy"
      }

      return .systemLibrary(
         name: "Cmsgpack",
         path: "Sources/Cmsgpack/\(subdirectory)",
         pkgConfig: pkgConfigName,
         providers: [
            .apt(["libmsgpack-dev"]),
            .brew(["msgpack"]),
            .yum(["msgpack-devel"]),
         ]
      )
   }()
}

let package = Package(
   name: "MessagePackReferenceImplementation",
   products: [
      .library(
         name: "MessagePackReferenceImplementation",
         targets: [
            "MessagePackReferenceImplementation"
         ]
      ),
   ],
   targets: [
      .target(
         name: "MessagePackReferenceImplementation",
         dependencies: [
            "Cmsgpack",
         ]
      ),
      .cMsgpackSystemLibrary,
   ]
)
