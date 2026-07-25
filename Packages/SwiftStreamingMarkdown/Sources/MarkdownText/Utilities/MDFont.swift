//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import UIKit
/// Cross-platform font type. Resolves to `UIFont` on UIKit platforms and `NSFont` on AppKit platforms.
public typealias MDFont = UIFont
#elseif canImport(AppKit)
import AppKit
/// Cross-platform font type. Resolves to `UIFont` on UIKit platforms and `NSFont` on AppKit platforms.
public typealias MDFont = NSFont

// NSFont instances are immutable value objects. AppKit has not yet annotated
// the class as Sendable, so provide the missing platform conformance locally.
extension NSFont: @retroactive @unchecked Sendable {}
#endif
