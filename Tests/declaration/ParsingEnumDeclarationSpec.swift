/*
   Copyright 2016 Ryuichi Saito, LLC

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

import Spectre

@testable import ast
@testable import parser

func specParsingEnumDeclaration() {
    let parser = Parser()

    describe("Parse empty enum decl") {
        $0.it("should have an empty decl with no cases") {
            let (astContext, errors) = parser.parse("enum foo {}")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.attributes.count) == 0
            try expect(node.accessLevel) == .Default
            try expect(node.cases.count) == 0
            try expect(node.elements.count) == 0
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:12]"
        }
    }

    describe("Parse empty enum decl with attributes") {
        $0.it("should have an empty decl with no cases, but has attributes") {
            let (astContext, errors) = parser.parse("@x @y @z enum foo {}")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.cases.count) == 0
            try expect(node.elements.count) == 0
            let attributes = node.attributes
            try expect(attributes.count) == 3
            try expect(attributes[0].name) == "x"
            try expect(attributes[1].name) == "y"
            try expect(attributes[2].name) == "z"
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:21]"
        }
    }

    describe("Parse empty enum decl with access level modifier") {
        $0.it("should have an empty decl with access level modifier") {
            let testPrefixes: [String: AccessLevel] = [
                "public": .Public,
                "internal": .Internal,
                "private  ": .Private,
                "@a   public": .Public,
                "@bar internal    ": .Internal,
                "@x private": .Private
            ]
            for (testPrefix, testModifierType) in testPrefixes {
                let (astContext, errors) = parser.parse("\(testPrefix) enum foo {}")
                try expect(errors.count) == 0
                let nodes = astContext.topLevelDeclaration.statements
                try expect(nodes.count) == 1
                guard let node = nodes[0] as? EnumDeclaration else {
                    throw failure("Node is not a EnumDeclaration.")
                }
                try expect(node.name) == "foo"
                try expect(node.accessLevel) == testModifierType
                try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:\(13 + testPrefix.characters.count)]"
            }
        }
    }

    describe("Parse enum decl with access level modifier for setters") {
        $0.it("should throw error that access level modifier cannot be applied to this declaration") {
            let testPrefixes = [
                "public ( set       )": "public",
                "internal(   set )": "internal",
                "private (  set )    ": "private",
                "@a public (set)": "public",
                "@bar internal (set)": "internal",
                "@x private (set)": "private"
            ]
            for (testPrefix, errorModifier) in testPrefixes {
                let (astContext, errors) = parser.parse("\(testPrefix) enum foo {}")
                try expect(errors.count) == 1
                try expect(errors[0]) == "'\(errorModifier)' modifier cannot be applied to this declaration."
                let nodes = astContext.topLevelDeclaration.statements
                try expect(nodes.count) == 1
                guard let node = nodes[0] as? EnumDeclaration else {
                    throw failure("Node is not a EnumDeclaration.")
                }
                try expect(node.name) == "foo"
                try expect(node.accessLevel) == .Default
                try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:\(13 + testPrefix.characters.count)]"
            }
        }
    }

    describe("Parse enum decl with one case that has one element") {
        $0.it("should have one enum decl with one case one element") {
            let (astContext, errors) = parser.parse("enum foo { case A }")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.attributes.count) == 0
            try expect(node.accessLevel) == .Default
            try expect(node.cases.count) == 1
            try expect(node.cases[0].elements.count) == 1
            try expect(node.cases[0].elements[0].name) == "A"
            try expect(node.elements.count) == 1
            try expect(node.elements[0].name) == "A"
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:20]"
        }
    }

    describe("Parse enum decl with two cases that each has one element") {
        $0.it("should have one enum decl with two cases that each has one element") {
            let (astContext, errors) = parser.parse("enum foo { case A\n case set }")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.attributes.count) == 0
            try expect(node.accessLevel) == .Default
            try expect(node.cases.count) == 2
            try expect(node.cases[0].elements.count) == 1
            try expect(node.cases[0].elements[0].name) == "A"
            try expect(node.cases[1].elements.count) == 1
            try expect(node.cases[1].elements[0].name) == "set"
            try expect(node.elements.count) == 2
            try expect(node.elements[0].name) == "A"
            try expect(node.elements[1].name) == "set"
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-2:12]"
        }
    }

    describe("Parse enum decl with one case that has two elements") {
        $0.it("should have one enum decl with one case two elements") {
            let (astContext, errors) = parser.parse("enum foo { case A, B }")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.attributes.count) == 0
            try expect(node.accessLevel) == .Default
            try expect(node.cases.count) == 1
            try expect(node.cases[0].elements.count) == 2
            try expect(node.cases[0].elements[0].name) == "A"
            try expect(node.cases[0].elements[1].name) == "B"
            try expect(node.elements.count) == 2
            try expect(node.elements[0].name) == "A"
            try expect(node.elements[1].name) == "B"
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-1:23]"
        }
    }

    describe("Parse enum decl with two cases that each has three elements and one element respectively") {
        $0.it("should have one enum decl with two cases that each has three elements and one element respectively") {
            let (astContext, errors) = parser.parse("enum foo { case A, B, C\n case set }")
            try expect(errors.count) == 0
            let nodes = astContext.topLevelDeclaration.statements
            try expect(nodes.count) == 1
            guard let node = nodes[0] as? EnumDeclaration else {
                throw failure("Node is not a EnumDeclaration.")
            }
            try expect(node.name) == "foo"
            try expect(node.attributes.count) == 0
            try expect(node.accessLevel) == .Default
            try expect(node.cases.count) == 2
            try expect(node.cases[0].elements.count) == 3
            try expect(node.cases[0].elements[0].name) == "A"
            try expect(node.cases[0].elements[1].name) == "B"
            try expect(node.cases[0].elements[2].name) == "C"
            try expect(node.cases[1].elements.count) == 1
            try expect(node.cases[1].elements[0].name) == "set"
            try expect(node.elements.count) == 4
            try expect(node.elements[0].name) == "A"
            try expect(node.elements[1].name) == "B"
            try expect(node.elements[2].name) == "C"
            try expect(node.elements[3].name) == "set"
            try expect(node.testSourceRangeDescription) == "test/parser[1:1-2:12]"
        }
    }


}
