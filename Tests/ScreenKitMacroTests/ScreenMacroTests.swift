import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ScreenKitMacros

final class ScreenMacroTests: XCTestCase {
    private let invalidArgumentsMessage = "#screen requires an items/state expression and a renderer argument."

    private var macros: [String: Macro.Type] {
        ["screen": ScreenMacro.self]
    }

    private func assertInvalidMacroExpansion(
        _ source: String,
        line: Int = 1,
        column: Int = 1
    ) {
        assertMacroExpansion(
            source,
            expandedSource: source,
            diagnostics: [
                .init(
                    message: invalidArgumentsMessage,
                    line: line,
                    column: column,
                    severity: .error
                )
            ],
            macros: macros
        )
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

    func testForwardsStateAndRendererToScreenInitializer() {
        assertMacroExpansion(
            "#screen(state, renderer: renderer)",
            expandedSource: "ScreenKit.Screen(state, renderer: renderer)",
            macros: macros
        )
    }

    func testDiagnosesMissingItemsOrStateExpression() {
        assertInvalidMacroExpansion("#screen(renderer: renderer)")
    }

    func testDiagnosesMissingRendererArgument() {
        assertInvalidMacroExpansion("#screen(items)")
    }

    func testDiagnosesUnknownRendererLabel() {
        assertInvalidMacroExpansion("#screen(items, render: renderer)")
    }

    func testDiagnosesAdditionalArguments() {
        assertInvalidMacroExpansion("#screen(items, renderer: renderer, extra: true)")
    }

    func testDiagnosesRendererProvidedBothAsArgumentAndTrailingClosure() {
        assertInvalidMacroExpansion(
            "#screen(items, renderer: renderer) { item in makeRenderer(for: item) }"
        )
    }

    func testDiagnosticPointsToMacroInvocation() {
        assertInvalidMacroExpansion(
            "let screen = #screen(items)",
            column: 14
        )
    }
}
