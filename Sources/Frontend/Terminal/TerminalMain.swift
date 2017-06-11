/*
   Copyright 2015-2017 Ryuichi Saito, LLC and the Yanagiba project contributors

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

import AST
import Parser
import Source
import Diagnostic

public enum TTYType {
  case astDump
  case astPrint
  case astText
  case diagnosticsOnly
}

public func terminalMain(
  filePaths: [String],
  ttyType: TTYType = .astText,
  isForGitHubIssue: Bool = false
) -> Int32 {
  if isForGitHubIssue {
    return runGitHubIssueGen(for: filePaths)
  }

  for filePath in filePaths {
    printHeader(for: filePath)

    guard let sourceFile = try? SourceReader.read(at: filePath) else {
      print("Can't read file, please double check the file path is correct.")
      printGitHubIssueInstructions(for: filePath)
      return -1
    }
    let diagnosticConsumer = TerminalDiagnosticConsumer()
    let parser = Parser(source: sourceFile)
    guard let topLevelDecl = try? parser.parse() else {
      DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
      printGitHubIssueInstructions(for: filePath)
      return -2
    }
    DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
    switch ttyType {
    case .astDump:
      print(topLevelDecl.ttyDump)
    case .astPrint:
      print(topLevelDecl.ttyPrint)
    case .astText:
      print(topLevelDecl.textDescription)
    case .diagnosticsOnly:
      print()
    }
  }

  return 0
}

private func printGitHubIssueInstructions(for filePath: String) {
  let command = "swift-ast -github-issue \(filePath)".colored(with: .yellow)
  print("""

  If you think this is a bug, please run
  \(command)
  and file a GitHub issue.
  """)
}

private func printHeader(for filePath: String) {
  let toolVersion = Version.current
  let toolVersionDescription = "Generated by yanagiba/swift-ast " +
    "\(toolVersion.library) with Swift \(toolVersion.swift) support"
  let toolVersCharCount = toolVersionDescription.count
  var pathCharCount = filePath.count
  if toolVersCharCount > pathCharCount {
    pathCharCount = toolVersCharCount
  }
  let separator = String(repeating: "=", count: pathCharCount)
  print(separator.colored(with: .red))
  print(filePath)
  print(toolVersionDescription)
  print("http://yanagiba.org/swift-ast")
  print(separator.colored(with: .blue))
}