// swift-tools-version: 5.8

import Foundation
import PackageDescription

enum PkgConfig {
   static func hasLibrary(named libraryName: String) -> Bool {
      return hasBrewLibrary(named: libraryName) || hasNonBrewLibrary(named: libraryName)
   }

   private static func hasBrewLibrary(named libraryName: String) -> Bool {
      let executablePath = "/opt/homebrew/bin/pkg-config"
      guard FileManager.default.fileExists(atPath: executablePath) else {
         return false
      }

      let process = try! Process.run(URL(fileURLWithPath: executablePath, isDirectory: false), arguments: [
         libraryName
      ])
      process.waitUntilExit()

      return process.terminationStatus == EXIT_SUCCESS
   }

   private static func hasNonBrewLibrary(named libraryName: String) -> Bool {
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
