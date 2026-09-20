import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ScreenKitMacros

final class ScreenMacroTests: XCTestCase {
    private var macros: [String: Macro.Type] {
        ["screen": ScreenMacro.self]
    }

    func testForwardsItemsAndRendererToScreenInitializer() {
        assertMacroExpansion(
            "#screen(items, renderer: renderer)",
            expandedSource: "ScreenKit.Screen(items, renderer: renderer)",
            macros: macros
        )
    }

    func testPreservesExpressionsWithoutDuplicatingThem() {
        assertMacroExpansion(
            "#screen(loadItems(), renderer: makeRenderer())",
            expandedSource: "ScreenKit.Screen(loadItems(), renderer: makeRenderer())",
            macros: macros
        )
    }

    func testAcceptsRendererAsTrailingClosure() {
        assertMacroExpansion(
            "#screen(items) { item in makeRenderer(for: item) }",
            expandedSource: """
            ScreenKit.Screen(items, renderer: { item in
                    makeRenderer(for: item)
                })
            """,
            macros: macros
        )
    }
}
