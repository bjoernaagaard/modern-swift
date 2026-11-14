# Macros (digest)

Read the digest when you write or test a macro. Write a macro only for code the compiler
could derive from a declaration and that a function, a generic, or a protocol extension
cannot produce. A macro adds a build dependency on `swift-syntax`, which slows a clean
build.

## Kinds of macro

| Kind | Written | Produces |
|---|---|---|
| Freestanding expression | `#stringify(a + b)` | a value |
| Freestanding declaration | `#makeCases("a", "b")` | new declarations |
| Attached peer | `@AddAsync` on a function | a declaration next to the one it is attached to |
| Attached member | `@CaseDetection` on an enum | new members inside the type |
| Attached accessor | `@Stored` on a property | `get` and `set` for the property |
| Attached member attribute | `@MainActorMembers` on a type | attributes on each member |
| Attached extension | `@AutoEquatable` on a type | an extension with a conformance |

One macro can have several roles. For example, `@Observable` adds members, adds an
attribute to each stored property, and adds a conformance.

## Layout of a macro package

```text
MyMacros/
├── Package.swift
├── Sources/
│   ├── MyMacros/             # the declarations callers import
│   │   └── Stringify.swift   # @freestanding(expression) public macro stringify...
│   └── MyMacrosPlugin/       # a .macro target that depends on swift-syntax
│       └── StringifyMacro.swift   # the @main CompilerPlugin and the macro type
└── Tests/
    └── MyMacrosTests/        # tests the expansion as text
```

## The declaration and the implementation

The compiler checks the arguments against the declaration before it expands the macro,
so a wrong argument type is reported at the call site.

```swift package
// Sources/MyMacros/Stringify.swift
/// Returns the value together with the source text that produced it.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) =
  #externalMacro(module: "MyMacrosPlugin", type: "StringifyMacro")

// Sources/MyMacrosPlugin/StringifyMacro.swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct MyMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [StringifyMacro.self]
}

struct StringifyMacro: ExpressionMacro {
  static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    guard let argument = node.arguments.first?.expression else {
      throw MacroError.missingArgument
    }
    return "(\(argument), \(literal: argument.description))"
  }
}

enum MacroError: Error, CustomStringConvertible {
  case missingArgument
  var description: String { "#stringify needs one argument" }
}
```

## Rules

- When the macro is used on a declaration it does not support, throw an error or call
  `context.diagnose` with a message and a fix. Never produce code that fails to compile
  with an error inside the expansion.
- Create names for helper declarations with `context.makeUniqueName`, so they cannot
  collide with the caller's names.
- A macro sees only the syntax it is attached to. It cannot read other files or types.
- Test the expansion as text with `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`.
  The check needs no compiled client code, so it runs quickly.
- To read the generated code in Xcode, choose "Expand Macro" on the call. You can set a
  breakpoint inside the expansion.
