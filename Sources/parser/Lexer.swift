/*
   Copyright 2015 Ryuichi Saito, LLC

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

import Foundation

import util
import source

class Lexer {
  init() {}

  private let _punctuatorMapping: [String: PunctuatorType] = [
    "(": .LeftParen,
    ")": .RightParen,
    "{": .LeftBrace,
    "}": .RightBrace,
    "[": .LeftSquare,
    "]": .RightSquare,
    ".": .Period,
    ",": .Comma,
    ":": .Colon,
    ";": .Semi,
    "=": .Equal,
    "@": .At,
    "#": .Pound,
    "&": .Amp,
    "->": .Arrow,
    "`": .Backtick,
    "!": .Exclaim,
    "?": .Question
  ]

  private var _keywordsMapping: [String: KeywordType] {
    let declKeywords = [
      "class",
      "deinit",
      "enum",
      "extension",
      "func",
      "import",
      "init",
      "inout",
      "internal",
      "let",
      "operator",
      "private",
      "protocol",
      "public",
      "static",
      "struct",
      "subscript",
      "typealias",
      "var"
    ]

    let stmtKeywords = [
      "break",
      "case",
      "continue",
      "default",
      "defer",
      "do",
      "else",
      "fallthrough",
      "for",
      "guard",
      "if",
      "in",
      "repeat",
      "return",
      "switch",
      "where",
      "while"
    ]

    let exprKeywords = [
      "as",
      "catch",
      "dynamicType",
      // "false", FalseBooleanLiteral
      "is",
      // "nil", NilLiteral
      "rethrows",
      "super",
      "self",
      "Self",
      "throw",
      "throws",
      // "true", TrueBooleanLiteral
      "try",
      "__COLUMN__",
      "__FILE__",
      "__FUNCTION__",
      "__LINE__"
    ]

    let contextualKeywords: [String: ContextualKeywordType] = [
      "associativity": .InfixOperatorDeclaration,
      "left": .InfixOperatorDeclaration,
      "none": .InfixOperatorDeclaration,
      "precedence": .InfixOperatorDeclaration,
      "right": .InfixOperatorDeclaration,
      "get": .ComputedVariable,
      "set": .ComputedVariable,
      "didSet": .VariableObserver,
      "willSet": .VariableObserver,
      "Protocol": .Metatype,
      "Type": .Metatype,
      "convenience": .DeclarationModifier,
      "dynamic": .DeclarationModifier,
      "final": .DeclarationModifier,
      "infix": .DeclarationModifier,
      "indirect": .DeclarationModifier,
      "lazy": .DeclarationModifier,
      "mutating": .DeclarationModifier,
      "nonmutating": .DeclarationModifier,
      "optional": .DeclarationModifier,
      "override": .DeclarationModifier,
      "postfix": .DeclarationModifier,
      "prefix": .DeclarationModifier,
      "required": .DeclarationModifier,
      "unowned": .DeclarationModifier,
      "weak": .DeclarationModifier
    ]

    var mapping = [String: KeywordType]()
    for stmtKeyword in stmtKeywords {
      mapping[stmtKeyword] = .Statement
    }
    for declKeyword in declKeywords {
      mapping[declKeyword] = .Declaration
    }
    for exprKeyword in exprKeywords {
      mapping[exprKeyword] = .Expression
    }
    mapping["_"] = .Pattern
    for (contextualKeyword, contextualKeywordType) in contextualKeywords {
      mapping[contextualKeyword] = .Contextual(contextualKeywordType)
    }
    return mapping
  }

  private var keywordRegex: String {
    return _keywordsMapping.keys.map { $0 }.joinWithSeparator("|")
  }

  private func _lexNestedComment(text: String) -> String {
    var comment = ""

    var advanced = 0
    var input = text
    var next = true

    while (!input.isEmpty && next) {
      input

      .match(/"^/\\*") { _ in
        let nestedComment = self._lexNestedComment(input[input.startIndex.advancedBy(2)..<input.endIndex])
        comment +=  "/*\(nestedComment)"
        advanced = 2 + nestedComment.utf16.count
      }?
      .match(/"^\\*/") {
        let endingComment = $0[0]
        comment += endingComment
        advanced = endingComment.utf16.count
        next = false
      }?
      .match(/"^(?s:.)?") {
        let commentChar = $0[0]
        comment += commentChar
        advanced = commentChar.utf16.count
      }

      input = input[input.startIndex.advancedBy(advanced)..<input.endIndex]
      advanced = 0
    }

    return comment
  }

  private func _lexInterpolatedStringLiteral(text: String) -> String {
    var result = ""

    var insideInterpolated = false
    var nestedLevel = 0
    var holdingEscape = false

    for char in text.characters {
      switch char {
      case "\\":
        result.append(char)
        holdingEscape = true
      case "(":
        if insideInterpolated {
          nestedLevel += 1
        }
        else if holdingEscape {
          nestedLevel = 0
          insideInterpolated = true
        }
        result.append(char)
        holdingEscape = false
      case ")":
        if insideInterpolated {
          if nestedLevel == 0 {
            insideInterpolated = false
          }
          else {
            nestedLevel -= 1
          }
        }
        result.append(char)
        holdingEscape = false
      case "\"":
        if !insideInterpolated && !holdingEscape {
          return result
        }
        result.append(char)
        holdingEscape = false
      default:
        result.append(char)
        holdingEscape = false
      }
    }

    return result
  }

  private var _sourceFilePath: String!
  private func _getSourceRange(startLine: Int, _ startColumn: Int, _ endLine: Int, _ endColumn: Int) -> SourceRange {
    let startSourceLocation = SourceLocation(path: _sourceFilePath, line: startLine, column: startColumn)
    let endSourceLocation = SourceLocation(path: _sourceFilePath, line: endLine, column: endColumn)
    return SourceRange(start: startSourceLocation, end: endSourceLocation)
  }

  func lex(source: SourceFile) -> LexicalContext {
    _sourceFilePath = source.path

    let lexicalContext = LexicalContext()

    let decimalLiteralRegex = "[0-9][0-9_]*"
    let identifierRegex = "([a-zA-Z_][a-zA-Z0-9_]*)"
    let operatorCharRegex = "/=\\-\\+!\\*%<>\\&\\|\\^~\\?"

    var currentLine = 1
    var currentColumn = 1
    var currentToken: Token? = nil
    var advanced = 0
    var input = source.content

    while !input.isEmpty {
      let startLine = currentLine
      let startColumn = currentColumn

      if advanced == 0 && _isPotentialStringLiteral(input) {
        input

        /// string literals
        .match(/"^\"((?:(\\\\\\(.*\\))|[^\\\\\"]|\\\\.)*)\"") {
          let stringLiteral = $0[1]
          if $0[2].isEmpty {
            currentToken = .StaticStringLiteral(stringLiteral)
            advanced = stringLiteral.utf16.count + 2
          }
          else {
            let interpolatedStringLiteral = self._lexInterpolatedStringLiteral(stringLiteral)
            currentToken = .InterpolatedStringLiteral(interpolatedStringLiteral)
            advanced = interpolatedStringLiteral.utf16.count + 2
          }
          currentColumn += advanced
        }
      }

      if advanced == 0 && _isPotentialNumericLiteral(input) {
        input

        // literals

        /// numberic literals

        .match(/"^-?0b[01][01_]*") {
          let binaryLiteralString = $0[0]
          currentToken = .BinaryIntegerLiteral(binaryLiteralString)
          advanced = binaryLiteralString.utf16.count
          currentColumn += advanced
        }?
        .match(/"^-?0o[0-7][0-7_]*") {
          let octalLiteralString = $0[0]
          currentToken = .OctalIntegerLiteral(octalLiteralString)
          advanced = octalLiteralString.utf16.count
          currentColumn += advanced
        }?
        .match(/"^-?0x[0-9a-fA-F][0-9a-fA-F_]*(\\.[0-9a-fA-F][0-9a-fA-F_]*)?[pP][\\+\\-]?\(decimalLiteralRegex)") {
          //    -_0 0x hexDigit   hexChars_o  (  . hexDigit   hexChars)_o   p|P  +|-_o    decimalLiteral
          let hexadecimalLiteralString = $0[0]
          currentToken = .HexadecimalFloatingPointLiteral(hexadecimalLiteralString)
          advanced = hexadecimalLiteralString.utf16.count
          currentColumn += advanced
        }?
        .match(/"^-?0x[0-9a-fA-F][0-9a-fA-F_]*") {
          let hexadecimalLiteralString = $0[0]
          currentToken = .HexadecimalIntegerLiteral(hexadecimalLiteralString)
          advanced = hexadecimalLiteralString.utf16.count
          currentColumn += advanced
        }?
        .match(/"^-?\(decimalLiteralRegex)(\\.\(decimalLiteralRegex))?([eE][\\+\\-]?\(decimalLiteralRegex))?") {
          let decimalLiteralString = $0[0]
          if $0[1].isEmpty && $0[2].isEmpty {
            currentToken = .DecimalIntegerLiteral(decimalLiteralString)
          }
          else {
            currentToken = .DecimalFloatingPointLiteral(decimalLiteralString)
          }
          advanced = decimalLiteralString.utf16.count
          currentColumn += advanced
        }
      }

      if advanced == 0 && _isPotentialIdentifierOrKeywords(input) {
        input

        /// boolean literals
        .match(/"^true(?!\(identifierRegex))") { _ in
          currentToken = .TrueBooleanLiteral
          advanced = 4
          currentColumn += advanced
        }?
        .match(/"^false(?!\(identifierRegex))") { _ in
          currentToken = .FalseBooleanLiteral
          advanced = 5
          currentColumn += advanced
        }?

        /// nil literal
        .match(/"^nil(?!\(identifierRegex))") { _ in
          currentToken = .NilLiteral
          advanced = 3
          currentColumn += advanced
        }?

        // keywords
        .match(/"^(\(keywordRegex))(?!\(identifierRegex))") {
          let keyword = $0[1]
          let keywordType = self._keywordsMapping[keyword]!
          currentToken = .Keyword(keyword, keywordType)
          advanced = keyword.utf16.count
          currentColumn += advanced
        }?

        // Matches identifier
        .match(/"^\(identifierRegex)") {
          let identifier = $0[1]
          currentToken = .Identifier(identifier)
          advanced = identifier.utf16.count
          currentColumn += advanced
        }
      }

      if advanced == 0 && _isPotentialComment(input) {
        input

        // comments
        .match(/"^//.*\\R") {
          let comment = $0[0]
          currentToken = .Comment(comment)
          advanced = comment.utf16.count
          currentLine += 1
          currentColumn = 1
        }?
        .match(/"^/\\*") { _ in
          let nestedComment = self._lexNestedComment(input[input.startIndex.advancedBy(2)..<input.endIndex])
          let comment =  "/*\(nestedComment)"
          let lines = comment.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
          currentLine += lines.count - 1
          currentColumn = 1 + (lines.last?.utf16.count ?? 0)
          currentToken = .Comment(comment)
          advanced = comment.utf16.count
        }
      }

      if advanced == 0 && _isPotentialPunctuation(input) {
        input

        // Matches backtick identifier
        .match(/"^`\(identifierRegex)`") {
          let identifier = $0[1]
          currentToken = .BacktickIdentifier(identifier)
          advanced = identifier.utf16.count + 2
          currentColumn += advanced
        }?

        // Punctuators and Operators

        /// Matches first subset of punctuators
        .match(/"^[(){}\\[\\],:;@#`]") {
          let punctuator = $0[0]
          let punctuatorType = self._punctuatorMapping[punctuator]!
          currentToken = .Punctuator(punctuatorType)
          advanced = punctuator.utf16.count
          currentColumn += advanced
        }?

        /// Matches Arrow
        .match(/"^->") { _ in
          currentToken = .Punctuator(.Arrow)
          advanced = 2
          currentColumn += advanced
        }?

        /// Matches regular operators and filter out some single punctuators
        .match(/"^[\(operatorCharRegex)]+") {
          let op = $0[0]
          switch op {
          case "=":
            currentToken = .Punctuator(.Equal)
            advanced = 1
          case "!":
            currentToken = .Punctuator(.Exclaim)
            advanced = 1
          case "&":
            currentToken = .Punctuator(.Amp)
            advanced = 1
          case "?":
            currentToken = .Punctuator(.Question)
            advanced = 1
          default:
            currentToken = .Operator(op)
            advanced = op.utf16.count
          }
          currentColumn += advanced
        }?

        /// Matches dot operators
        .match(/"^\\.\\.[\\.\(operatorCharRegex)]*") {
          let op = $0[0]
          currentToken = .Operator(op)
          advanced = op.utf16.count
          currentColumn += advanced
        }?

        /// Matches the Period
        .match(/"^\\.") { _ in
          currentToken = .Punctuator(.Period)
          advanced = 1
          currentColumn += advanced
        }
      }

      if advanced == 0 /* everything else */ {
        switch _getFirstCharacter(input) {
        case "\n":
          currentToken = .LineFeed
          advanced = 1
          currentLine += 1
          currentColumn = 1
        case "\r":
          currentToken = .CarriageReturn
          advanced = 1
          currentLine += 1
          currentColumn = 1
        case "\r\n":
          currentLine += 1
          currentColumn = 1
          lexicalContext.append(.CarriageReturn, _getSourceRange(startLine, startColumn, currentLine, currentColumn))
          lexicalContext.append(.LineFeed, _getSourceRange(startLine, startColumn, currentLine, currentColumn))
          advanced = 1
        case "\t":
          currentToken = .HorizontalTab
          advanced = 1
          currentColumn += advanced
        default:
          input

          /// Matches form feed
          .match(/"^\\u000C") { _ in
            currentToken = .FormFeed
            advanced = 1
            currentColumn += advanced
          }?

          /// Matches null
          .match(/"^\\u0000") { _ in
            currentToken = .Null
            advanced = 1
            currentColumn += advanced
          }?

          /// Matches any other whitespace
          .match(/"^\\s") { _ in
            currentToken = .Space
            advanced = 1
            currentColumn += advanced
          }?

          // Error

          /// Matches anything else and emit invalid token
          .match(/"^.?") {
            currentToken = .Invalid(invalidTokenString: $0[0])
            advanced = $0[0].utf16.count
            currentColumn += advanced
          }
        }
      }

      if let currentToken = currentToken {
        lexicalContext.append(currentToken, _getSourceRange(startLine, startColumn, currentLine, currentColumn))
      }

      if advanced == 0 {
        return lexicalContext
      }

      input = input[input.startIndex.advancedBy(advanced)..<input.endIndex]
      currentToken = nil
      advanced = 0
    }

    return lexicalContext
  }

  private func _isPotentialStringLiteral(text: String) -> Bool {
    return _getFirstCharacter(text) == "\""
  }

  private func _isPotentialNumericLiteral(text: String, first: Bool = true) -> Bool {
    switch _getFirstCharacter(text) {
    case "-":
      if first && text.utf16.count > 1 {
        return _isPotentialNumericLiteral(text[text.startIndex.advancedBy(1)..<text.endIndex], first: false)
      }
      else {
        return false
      }
    case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
      return true
    default:
      return false
    }
  }

  private func _isPotentialIdentifierOrKeywords(text: String) -> Bool {
    switch _getFirstCharacter(text) {
    case "A", "B", "C", "D", "E", "F", "G",
         "H", "I", "J", "K", "L", "M", "N",
         "O", "P", "Q", "R", "S", "T", "U",
         "V", "W", "X", "Y", "Z",
         "a", "b", "c", "d", "e", "f", "g",
         "h", "i", "j", "k", "l", "m", "n",
         "o", "p", "q", "r", "s", "t", "u",
         "v", "w", "x", "y", "z",
         "_":
      return true
    default:
      return false
    }
  }

  private func _isPotentialComment(text: String) -> Bool {
    return _getFirstCharacter(text) == "/"
  }

  private func _isPotentialPunctuation(text: String) -> Bool {
    switch _getFirstCharacter(text) {
    case "(", ")", "{", "}", "[", "]", "<", ">",
         ".", ",", ":", ";", "=", "@", "#", "&", "`",
         "!", "?", "/", "-", "+", "*", "%", "|", "^", "~":
      return true
    default:
      return false
    }
  }

  private func _getFirstCharacter(text: String) -> Character {
    return text[text.startIndex]
  }
}

prefix operator / {}

prefix func /(regex: String) -> NSRegularExpression {
    return try! NSRegularExpression(pattern: regex, options: NSRegularExpressionOptions(rawValue: 0))
}