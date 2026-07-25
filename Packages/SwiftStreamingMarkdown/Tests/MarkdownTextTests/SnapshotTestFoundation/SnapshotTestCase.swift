//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

//  SnapshotTestCase is a utility class extending XCTestCase.
//
//  You can toggle recording behavior with SnapshotTesting's configuration APIs.
//
import SnapshotTesting
import SwiftUI
import XCTest
@testable import SwiftStreamingMarkdown

@MainActor
open class SnapshotTestCase: XCTestCase {
  #if canImport(UIKit)
  /* Function to perform snapshot tests. Embeds all views in a ViewController for.
   - Parameters:
   - view: View to be tested
   - variants: Device variants to be tested. Defaults to the standard collection of device variants
   - testName: The name of the test in which failure occurred. Defaults to the function name of the test case in which this function was called.
   - file: The file in which failure occurred. Defaults to the file name of the test case in which this function was called.
   - line: The line number on which failure occurred. Defaults to the line number on which this function was called.
   */

  public func assert<V: View>(
    _ view: V,
    variants: [IOSVariant] = .standard(precision: 0.99, perceptualPrecision: 1.00),
    testName: String = #function,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    ParagraphViewCache.shared.clearCache()
    variants.forEach { variant in
      let viewController = view.environment(\.colorScheme, variant.colorScheme).asViewController
      assertSnapshot(
        of: viewController,
        as: variant.snapshot,
        named: variant.name,
        file: file,
        testName: testName,
        line: line
      )
    }
  }
  #elseif canImport(AppKit)
  /// Perform snapshot tests on macOS using window-size-based variants.
  public func assert<V: View>(
    _ view: V,
    variants: [MacVariant] = .standard(precision: 0.99, perceptualPrecision: 1.00),
    testName: String = #function,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    ParagraphViewCache.shared.clearCache()
    variants.forEach { variant in
      let viewController = view.environment(\.colorScheme, variant.colorScheme).asViewController
      assertSnapshot(
        of: viewController,
        as: variant.snapshot,
        named: variant.name,
        file: file,
        testName: testName,
        line: line
      )
    }
  }
  #endif
}

#if canImport(UIKit)
import UIKit

private extension View {
  var asViewController: UIViewController {
    let vc = UIHostingController(rootView: self)
    vc.view.backgroundColor = .clear
    return vc
  }
}
#elseif canImport(AppKit)
import AppKit

private extension View {
  var asViewController: NSViewController {
    let vc = NSHostingController(rootView: self)
    vc.view.wantsLayer = true
    vc.view.layer?.backgroundColor = NSColor.clear.cgColor
    return vc
  }
}
#endif
