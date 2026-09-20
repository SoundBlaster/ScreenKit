import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ScreenMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let items = node.arguments.first(where: { $0.label == nil }) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: InvalidScreenMacroArguments())
            ])
        }

        let rendererExpression: ExprSyntax
        if let renderer = node.arguments.first(where: { $0.label?.text == "renderer" }),
           node.arguments.count == 2 {
            rendererExpression = renderer.expression
        } else if let trailingClosure = node.trailingClosure,
                  node.arguments.count == 1 {
            rendererExpression = ExprSyntax(trailingClosure)
        } else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: InvalidScreenMacroArguments())
            ])
        }

        return "ScreenKit.Screen(\(items.expression), renderer: \(rendererExpression))"
    }
}

private struct InvalidScreenMacroArguments: DiagnosticMessage {
    var message: String { "#screen requires an item array and a renderer argument." }
    var diagnosticID: MessageID { MessageID(domain: "ScreenKitMacros", id: "invalid-arguments") }
    var severity: DiagnosticSeverity { .error }
}
