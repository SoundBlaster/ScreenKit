import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ScreenKitMacros: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ScreenMacro.self]
}
