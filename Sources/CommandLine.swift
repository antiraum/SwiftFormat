//
//  CommandLine.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 10/01/2017.
//  Copyright 2017 Nick Lockwood
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SwiftFormat
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

import Foundation

// MARK: Internal APIs used by CLI - included in framework for testing purposes

enum OutputType {
    case info
    case success
    case error
    case warning
    case output
}

struct CLI {
    static var print: (String, OutputType) -> Void = { _ in
        fatalError("No print hook set")
    }

    static var readLine: () -> String? = {
        fatalError("No readLine hook set")
    }
}

private func print(_ message: String, as type: OutputType = .info) {
    CLI.print(message, type)
}

func printWarnings(_ errors: [Error]) {
    for error in errors {
        print("warning: \(error)", as: .warning)
    }
}

func printHelp() {
    print("")
    print("swiftformat, version \(version)")
    print("copyright (c) 2016 Nick Lockwood")
    print("")
    print("usage: swiftformat [<file> <file> ...] [--inferoptions] [--output path] [...]")
    print("")
    print("<file> <file> ...  swift file or directory path(s) to be formatted")
    print("")
    print("--inferoptions     instead of formatting the input, infer format options from it")
    print("--output           output path for formatted file(s) (defaults to input path)")
    print("--symlinks         how symlinks are handled. \"follow\" or \"ignore\" (default)")
    print("--fragment         input is part of a larger file. \"true\" or \"false\" (default)")
    print("--cache            path to cache file, or \"clear\" or \"ignore\" the default cache")
    print("--verbose          display detailed formatting output")
    print("")
    print("--disable          a list of format rules to be disabled (comma-delimited)")
    print("--enable           a list of disabled rules to be re-enabled (comma-delimited)")
    print("--rules            the list of rules to apply (pass nothing to print rules)")
    print("")
    print("--allman           use allman indentation style \"true\" or \"false\" (default)")
    print("--binarygrouping   binary grouping,threshold or \"none\", \"ignore\". default: 4,8")
    print("--commas           commas in collection literals. \"always\" (default) or \"inline\"")
    print("--comments         indenting of comment bodies. \"indent\" (default) or \"ignore\"")
    print("--decimalgrouping  decimal grouping,threshold or \"none\", \"ignore\". default: 3,6")
    print("--empty            how empty values are represented. \"void\" (default) or \"tuple\"")
    print("--experimental     experimental rules. \"enabled\" or \"disabled\" (default)")
    print("--exponentcase     case of 'e' in numbers. \"lowercase\" or \"uppercase\" (default)")
    print("--header           header comments. \"strip\", \"ignore\", or the text you wish use")
    print("--hexgrouping      hex grouping,threshold or \"none\", \"ignore\". default: 4,8")
    print("--hexliteralcase   casing for hex literals. \"uppercase\" (default) or \"lowercase\"")
    print("--ifdef            #if indenting. \"indent\" (default), \"noindent\" or \"outdent\"")
    print("--indent           number of spaces to indent, or \"tab\" to use tabs")
    print("--insertlines      insert blank line after {. \"enabled\" (default) or \"disabled\"")
    print("--linebreaks       linebreak character to use. \"cr\", \"crlf\" or \"lf\" (default)")
    print("--octalgrouping    octal grouping,threshold or \"none\", \"ignore\". default: 4,8")
    print("--patternlet       let/var placement in patterns. \"hoist\" (default) or \"inline\"")
    print("--ranges           spacing for ranges. \"spaced\" (default) or \"nospace\"")
    print("--removelines      remove blank line before }. \"enabled\" (default) or \"disabled\"")
    print("--semicolons       allow semicolons. \"never\" or \"inline\" (default)")
    print("--stripunusedargs  \"closure-only\", \"unnamed-only\" or \"always\" (default)")
    print("--trimwhitespace   trim trailing space. \"always\" (default) or \"nonblank-lines\"")
    print("--wraparguments    wrap function args. \"beforefirst\", \"afterfirst\", \"disabled\"")
    print("--wrapelements     wrap array/dict. \"beforefirst\", \"afterfirst\", \"disabled\"")
    print("")
    print("--help             print this help page")
    print("--version          print version")
    print("")
}

func expandPath(_ path: String) -> URL {
    let path = NSString(string: path).expandingTildeInPath
    let directoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return URL(fileURLWithPath: path, relativeTo: directoryURL)
}

func timeEvent(block: () throws -> Void) rethrows -> String {
    let start = CFAbsoluteTimeGetCurrent()
    try block()
    let time = round((CFAbsoluteTimeGetCurrent() - start) * 100) / 100 // round to nearest 10ms
    return String(format: "%gs", time)
}

func processArguments(_ args: [String]) {
    var errors = [Error]()
    do {
        // Get options
        let args = try preprocessArguments(args, commandLineArguments)
        let formatOptions = try formatOptionsFor(args)
        let fileOptions = try fileOptionsFor(args)

        // Show help if requested specifically or if no arguments are passed
        if args["help"] != nil {
            printHelp()
            return
        }

        // Version
        if args["version"] != nil {
            print("swiftformat, version \(version)")
            return
        }

        // Rules
        var rules = Set(FormatRules.byName.keys)
        var disabled = Set(FormatRules.disabledByDefault)
        if let names = args["enable"]?.components(separatedBy: ",") {
            for name in names {
                var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rules.contains(name) {
                    throw FormatError.options("unknown rule '\(name)'")
                }
                disabled.remove(name)
            }
        }
        if let names = args["disable"]?.components(separatedBy: ",") {
            for name in names {
                var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rules.contains(name) {
                    throw FormatError.options("unknown rule '\(name)'")
                }
                disabled.insert(name)
            }
        }
        if let names = args["rules"]?.components(separatedBy: ",") {
            if names.count == 1, names[0].isEmpty {
                print("")
                for name in Array(rules).sorted() {
                    let disabled = disabled.contains(name) ? " (disabled)" : ""
                    print(" \(name)\(disabled)")
                }
                print("")
                return
            }
            var whitelist = Set<String>()
            for name in names {
                var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if rules.contains(name) {
                    whitelist.insert(name)
                } else {
                    throw FormatError.options("unknown rule '\(name)'")
                }
            }
            rules = whitelist
        } else {
            for name: String in disabled {
                rules.remove(name)
            }
        }

        // Get input path(s)
        var inputURLs = [URL]()
        while let inputPath = args[String(inputURLs.count + 1)] {
            inputURLs.append(expandPath(inputPath))
        }

        // Verbose
        var verbose = false
        if let arg = args["verbose"] {
            verbose = true
            if !arg.isEmpty {
                // verbose doesn't take an argument, so treat argument as another input path
                inputURLs.append(expandPath(arg))
            }
            if inputURLs.isEmpty, args["output"] ?? "" != "" {
                throw FormatError.options("--verbose option has no effect unless an output file is specified")
            }
        }

        // Infer options
        if let arg = args["inferoptions"] {
            if !arg.isEmpty {
                // inferoptions doesn't take an argument, so treat argument as another input path
                inputURLs.append(expandPath(arg))
            }
            if inputURLs.count > 0 {
                print("inferring swiftformat options from source file(s)...")
                var filesParsed = 0, options = FormatOptions(), errors = [Error]()
                let time = timeEvent {
                    (filesParsed, options, errors) = inferOptions(from: inputURLs)
                }
                printWarnings(errors)
                if filesParsed == 0 {
                    throw FormatError.parsing("failed to to infer options")
                }
                var filesChecked = filesParsed
                for case let error as FormatError in errors {
                    switch error {
                    case .parsing, .reading:
                        filesChecked += 1
                    case .writing:
                        assertionFailure()
                    case .options:
                        break
                    }
                }
                print("options inferred from \(filesParsed)/\(filesChecked) files in \(time)")
                print("")
                print(commandLineArguments(for: options).map({ "--\($0) \($1)" }).joined(separator: " "))
                print("")
                return
            }
        }

        // Get output path
        let outputURL = args["output"].map { expandPath($0) }
        if outputURL != nil {
            if args["output"] == "" {
                throw FormatError.options("--output argument expects a value")
            } else if inputURLs.count > 1 {
                throw FormatError.options("--output argument is only valid for a single input file")
            }
        }

        // Get cache path
        var cacheURL: URL?
        let defaultCacheFileName = "swiftformat.cache"
        let manager = FileManager.default
        func setDefaultCacheURL() {
            if let cachePath =
                NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
                let cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("com.charcoaldesign.swiftformat")
                do {
                    try manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                    cacheURL = cacheDirectory.appendingPathComponent(defaultCacheFileName)
                } catch {
                    errors.append(FormatError.writing("failed to create cache directory at \(cacheDirectory.path)"))
                }
            } else {
                errors.append(FormatError.reading("failed to find cache directory at ~/Library/Caches"))
            }
        }
        if let cache = args["cache"] {
            switch cache {
            case "":
                throw FormatError.options("--cache option expects a value")
            case "ignore":
                break
            case "clear":
                setDefaultCacheURL()
                if let cacheURL = cacheURL, manager.fileExists(atPath: cacheURL.path) {
                    do {
                        try manager.removeItem(at: cacheURL)
                    } catch {
                        errors.append(FormatError.writing("failed to delete cache file at \(cacheURL.path)"))
                    }
                }
            default:
                cacheURL = expandPath(cache)
                guard cacheURL != nil else {
                    throw FormatError.options("unsupported --cache value `\(cache)`")
                }
                var isDirectory: ObjCBool = false
                if manager.fileExists(atPath: cacheURL!.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    cacheURL = cacheURL!.appendingPathComponent(defaultCacheFileName)
                }
            }
        } else {
            setDefaultCacheURL()
        }

        // If no input file, try stdin
        if inputURLs.count == 0 {
            var input: String?
            var finished = false
            var fatalError: Error?
            DispatchQueue.global(qos: .userInitiated).async {
                while let line = CLI.readLine() {
                    input = (input ?? "") + line
                }
                if let input = input {
                    do {
                        if args["inferoptions"] != nil {
                            let tokens = tokenize(input)
                            if let error = parsingError(for: tokens) {
                                throw error
                            }
                            let options = inferOptions(from: tokens)
                            print(commandLineArguments(for: options).map({ "--\($0) \($1)" }).joined(separator: " "))
                        } else if let outputURL = outputURL {
                            if verbose {
                                print("running swiftformat...")
                            }
                            let output = try format(
                                input,
                                ruleNames: Array(rules),
                                options: formatOptions,
                                verbose: verbose
                            )
                            do {
                                try output.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
                                print("swiftformat completed successfully", as: .success)
                            } catch {
                                throw FormatError.writing("failed to write file \(outputURL.path)")
                            }
                        } else {
                            // Write to stdout
                            let output = try format(
                                input,
                                ruleNames: Array(rules),
                                options: formatOptions,
                                verbose: false
                            )
                            print(output, as: .output)
                        }
                    } catch {
                        fatalError = error
                    }
                }
                finished = true
            }
            // Wait for input
            let start = NSDate()
            while start.timeIntervalSinceNow > -0.01 {}
            // If no input received by now, assume none is coming
            if input != nil {
                while !finished && start.timeIntervalSinceNow > -30 {}
                if let fatalError = fatalError {
                    throw fatalError
                }
            } else if args["inferoptions"] != nil {
                throw FormatError.options("--inferoptions requires one or more input files")
            } else {
                printHelp()
            }
            return
        }

        if !verbose {
            print("running swiftformat...")
        }

        // Format the code
        var filesWritten = 0, filesChecked = 0
        let time = timeEvent {
            var _errors = [Error]()
            (filesWritten, filesChecked, _errors) = processInput(
                inputURLs,
                andWriteToOutput: outputURL,
                withRules: Array(rules),
                formatOptions: formatOptions,
                fileOptions: fileOptions,
                verbose: verbose,
                cacheURL: cacheURL
            )
            errors += _errors
        }
        var filesFailed = 0
        for case let error as FormatError in errors {
            switch error {
            case .parsing, .reading, .writing:
                filesFailed += 1
            case .options:
                break
            }
        }
        if filesChecked == 0 {
            if filesFailed == 0 {
                if let error = errors.first {
                    errors.removeAll()
                    throw error
                }
                let inputPaths = inputURLs.map({ $0.path }).joined(separator: ", ")
                throw FormatError.options("no eligible files found at \(inputPaths)")
            } else {
                throw FormatError.options("failed to format any files")
            }
        }
        printWarnings(errors)
        print("swiftformat completed. \(filesWritten)/\(filesChecked) files updated in \(time)", as: .success)
    } catch {
        printWarnings(errors)
        // Fatal error
        print("error: \(error)", as: .error)
    }
}

func inferOptions(from inputURLs: [URL]) -> (Int, FormatOptions, [Error]) {
    var tokens = [Token]()
    var errors = [Error]()
    var filesParsed = 0
    for inputURL in inputURLs {
        errors += enumerateFiles(withInputURL: inputURL) { inputURL, _ in
            guard let input = try? String(contentsOf: inputURL) else {
                throw FormatError.reading("failed to read file \(inputURL.path)")
            }
            let _tokens = tokenize(input)
            if let error = parsingError(for: _tokens), case let .parsing(string) = error {
                throw FormatError.parsing("\(string) in \(inputURL.path)")
            }
            return {
                filesParsed += 1
                tokens += _tokens
            }
        }
    }
    return (filesParsed, inferOptions(from: tokens), errors)
}

public func format(_ source: String,
                   ruleNames: [String],
                   options: FormatOptions,
                   verbose: Bool) throws -> String {
    // Parse
    var tokens = tokenize(source)
    if !options.fragment, let error = parsingError(for: tokens) {
        throw error
    }

    // Recursively apply rules until no changes are detected
    var options = options
    let formatter = Formatter(tokens, options: options)
    let rulesByName = FormatRules.byName
    var rulesApplied = Set<String>()
    repeat {
        tokens = formatter.tokens
        if verbose {
            for ruleName in ruleNames {
                let before = formatter.tokens
                rulesByName[ruleName]!(formatter)
                if formatter.tokens != before {
                    rulesApplied.insert(ruleName)
                }
            }
        } else {
            for ruleName in ruleNames {
                rulesByName[ruleName]!(formatter)
            }
        }
        options.fileHeader = nil // Prevents infinite recursion
    } while tokens != formatter.tokens

    // Info
    if verbose {
        if rulesApplied.isEmpty {
            print(" -- no changes", as: .success)
        } else {
            let sortedNames = Array(rulesApplied).sorted().joined(separator: ", ")
            print(" -- rules applied: \(sortedNames)", as: .success)
        }
    }

    // Output
    return sourceCode(for: tokens)
}

func processInput(_ inputURLs: [URL],
                  andWriteToOutput outputURL: URL?,
                  withRules enabled: [String],
                  formatOptions: FormatOptions,
                  fileOptions: FileOptions,
                  verbose: Bool,
                  cacheURL: URL?) -> (Int, Int, [Error]) {

    // Filter rules
    var disabled = [String]()
    for name: String in FormatRules.byName.keys {
        if !enabled.contains(name) {
            disabled.append(name)
        }
    }
    let ruleNames = enabled.count <= disabled.count ?
        (enabled.count == 0 ? "" : "rules:\(enabled.joined(separator: ","));") :
        (disabled.count == 0 ? "" : "disabled:\(disabled.joined(separator: ","));")
    // Load cache
    let cachePrefix = "\(version);\(formatOptions)\(ruleNames)"
    let cacheDirectory = cacheURL?.deletingLastPathComponent().absoluteURL
    var cache: [String: String]?
    if let cacheURL = cacheURL {
        cache = NSDictionary(contentsOf: cacheURL) as? [String: String] ?? [:]
    }
    // Format files
    var errors = [Error]()
    var filesChecked = 0, filesWritten = 0
    for inputURL in inputURLs {
        errors += enumerateFiles(withInputURL: inputURL,
                                 outputURL: outputURL,
                                 options: fileOptions,
                                 concurrent: !verbose) { inputURL, outputURL in

            guard let input = try? String(contentsOf: inputURL) else {
                throw FormatError.reading("failed to read file \(inputURL.path)")
            }
            let cacheKey: String = {
                var path = inputURL.absoluteURL.path
                if let cacheDirectory = cacheDirectory {
                    let commonPrefix = path.commonPrefix(with: cacheDirectory.path)
                    path = path.substring(from: commonPrefix.endIndex)
                }
                return path
            }()
            do {
                if verbose {
                    print("formatting \(inputURL.path)")
                }
                let output: String
                if cache?[cacheKey] == cachePrefix + String(input.characters.count) {
                    output = input
                    if verbose {
                        print("-- no changes", as: .success)
                    }
                } else {
                    output = try format(input, ruleNames: enabled, options: formatOptions, verbose: verbose)
                }
                if outputURL != inputURL, (try? String(contentsOf: outputURL)) != output {
                    do {
                        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                                withIntermediateDirectories: true,
                                                                attributes: nil)
                    } catch {
                        throw FormatError.writing("failed to create directory at \(outputURL.path), \(error)")
                    }
                } else if output == input {
                    // No changes needed
                    return {
                        filesChecked += 1
                        cache?[cacheKey] = cachePrefix + String(output.characters.count)
                    }
                }
                do {
                    try output.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
                    return {
                        filesChecked += 1
                        filesWritten += 1
                        cache?[cacheKey] = cachePrefix + String(output.characters.count)
                    }
                } catch {
                    throw FormatError.writing("failed to write file \(outputURL.path), \(error)")
                }
            } catch let FormatError.parsing(string) {
                throw FormatError.parsing("\(string) in \(inputURL.path)")
            } catch {
                throw error
            }
        }
    }
    if filesChecked > 0 {
        // Save cache
        if let cache = cache, let cacheURL = cacheURL, let cacheDirectory = cacheDirectory {
            if !(cache as NSDictionary).write(to: cacheURL, atomically: true) {
                if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                    errors.append(FormatError.writing("failed to write cache file at \(cacheURL.path)"))
                } else {
                    errors.append(FormatError.reading("specified cache file directory does not exist: \(cacheDirectory.path)"))
                }
            }
        }
    }
    return (filesWritten, filesChecked, errors)
}

func preprocessArguments(_ args: [String], _ names: [String]) throws -> [String: String] {
    var anonymousArgs = 0
    var namedArgs: [String: String] = [:]
    var name = ""
    for arg in args {
        if arg.hasPrefix("--") {
            // Long argument names
            let key = arg.substring(from: arg.characters.index(arg.startIndex, offsetBy: 2))
            if !names.contains(key) {
                throw FormatError.options("unknown argument: \(arg)")
            }
            name = key
            namedArgs[name] = ""
            continue
        } else if arg.hasPrefix("-") {
            // Short argument names
            let flag = arg.substring(from: arg.characters.index(arg.startIndex, offsetBy: 1))
            let matches = names.filter { $0.hasPrefix(flag) }
            if matches.count > 1 {
                throw FormatError.options("ambiguous argument: \(arg)")
            } else if matches.count == 0 {
                throw FormatError.options("unknown argument: \(arg)")
            } else {
                name = matches[0]
                namedArgs[name] = ""
            }
            continue
        }
        if name == "" {
            // Argument is anonymous
            name = String(anonymousArgs)
            anonymousArgs += 1
        }
        namedArgs[name] = arg
        name = ""
    }
    return namedArgs
}

func commandLineArguments(for options: FormatOptions) -> [String: String] {
    var args = [String: String]()
    for child in Mirror(reflecting: options).children {
        if let label = child.label {
            switch label {
            case "indent":
                if options.indent == "\t" {
                    args["indent"] = "tabs"
                } else {
                    args["indent"] = String(options.indent.characters.count)
                }
            case "linebreak":
                switch options.linebreak {
                case "\r":
                    args["linebreaks"] = "cr"
                case "\n":
                    args["linebreaks"] = "lf"
                case "\r\n":
                    args["linebreaks"] = "crlf"
                default:
                    break
                }
            case "allowInlineSemicolons":
                args["semicolons"] = options.allowInlineSemicolons ? "inline" : "never"
            case "spaceAroundRangeOperators":
                args["ranges"] = options.spaceAroundRangeOperators ? "spaced" : "nospace"
            case "useVoid":
                args["empty"] = options.useVoid ? "void" : "tuples"
            case "trailingCommas":
                args["commas"] = options.trailingCommas ? "always" : "inline"
            case "indentComments":
                args["comments"] = options.indentComments ? "indent" : "ignore"
            case "truncateBlankLines":
                args["trimwhitespace"] = options.truncateBlankLines ? "always" : "nonblank-lines"
            case "insertBlankLines":
                args["insertlines"] = options.insertBlankLines ? "enabled" : "disabled"
            case "removeBlankLines":
                args["removelines"] = options.removeBlankLines ? "enabled" : "disabled"
            case "allmanBraces":
                args["allman"] = options.allmanBraces ? "true" : "false"
            case "fileHeader":
                args["header"] = options.fileHeader.map { $0.isEmpty ? "strip" : $0 } ?? "ignore"
            case "ifdefIndent":
                args["ifdef"] = options.ifdefIndent.rawValue
            case "wrapArguments":
                args["wraparguments"] = options.wrapArguments.rawValue
            case "wrapElements":
                args["wrapelements"] = options.wrapElements.rawValue
            case "uppercaseHex":
                args["hexliteralcase"] = options.uppercaseHex ? "uppercase" : "lowercase"
            case "uppercaseExponent":
                args["exponentcase"] = options.uppercaseExponent ? "uppercase" : "lowercase"
            case "decimalGrouping":
                args["decimalgrouping"] = options.decimalGrouping.rawValue
            case "binaryGrouping":
                args["binarygrouping"] = options.binaryGrouping.rawValue
            case "octalGrouping":
                args["octalgrouping"] = options.octalGrouping.rawValue
            case "hexGrouping":
                args["hexgrouping"] = options.hexGrouping.rawValue
            case "hoistPatternLet":
                args["patternlet"] = options.hoistPatternLet ? "hoist" : "inline"
            case "stripUnusedArguments":
                args["stripunusedargs"] = options.stripUnusedArguments.rawValue
            case "experimentalRules":
                args["experimental"] = options.experimentalRules ? "enabled" : nil
            case "fragment":
                args["fragment"] = options.fragment ? "true" : nil
            default:
                assertionFailure("Unknown option: \(label)")
            }
        }
    }
    return args
}

private func processOption(_ key: String, in args: [String: String],
                           from: inout Set<String>, handler: (String) throws -> Void) throws {
    precondition(commandLineArguments.contains(key))
    var arguments = from
    arguments.remove(key)
    from = arguments
    guard let value = args[key] else {
        return
    }
    guard !value.isEmpty else {
        throw FormatError.options("--\(key) option expects a value")
    }
    do {
        try handler(value)
    } catch {
        throw FormatError.options("unsupported --\(key) value: \(value)")
    }
}

func fileOptionsFor(_ args: [String: String]) throws -> FileOptions {
    var options = FileOptions()
    var arguments = Set(fileArguments)
    try processOption("symlinks", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "follow":
            options.followSymlinks = true
        case "ignore":
            options.followSymlinks = false
        default:
            throw FormatError.options("")
        }
    }
    assert(arguments.isEmpty, "\(arguments.joined(separator: ","))")
    return options
}

func formatOptionsFor(_ args: [String: String]) throws -> FormatOptions {
    var options = FormatOptions()
    var arguments = Set(formatArguments)
    try processOption("indent", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "tab", "tabs", "tabbed":
            options.indent = "\t"
        default:
            if let spaces = Int($0) {
                options.indent = String(repeating: " ", count: spaces)
                break
            }
            throw FormatError.options("")
        }
    }
    try processOption("allman", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "true", "enabled":
            options.allmanBraces = true
        case "false", "disabled":
            options.allmanBraces = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("semicolons", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "inline":
            options.allowInlineSemicolons = true
        case "never", "false":
            options.allowInlineSemicolons = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("commas", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "always", "true":
            options.trailingCommas = true
        case "inline", "false":
            options.trailingCommas = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("comments", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "indent", "indented":
            options.indentComments = true
        case "ignore":
            options.indentComments = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("linebreaks", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "cr":
            options.linebreak = "\r"
        case "lf":
            options.linebreak = "\n"
        case "crlf":
            options.linebreak = "\r\n"
        default:
            throw FormatError.options("")
        }
    }
    try processOption("ranges", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "space", "spaced", "spaces":
            options.spaceAroundRangeOperators = true
        case "nospace":
            options.spaceAroundRangeOperators = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("empty", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "void":
            options.useVoid = true
        case "tuple", "tuples":
            options.useVoid = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("trimwhitespace", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "always":
            options.truncateBlankLines = true
        case "nonblank-lines", "nonblank", "non-blank-lines", "non-blank",
             "nonempty-lines", "nonempty", "non-empty-lines", "non-empty":
            options.truncateBlankLines = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("insertlines", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "enabled", "true":
            options.insertBlankLines = true
        case "disabled", "false":
            options.insertBlankLines = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("removelines", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "enabled", "true":
            options.removeBlankLines = true
        case "disabled", "false":
            options.removeBlankLines = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("header", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "strip":
            options.fileHeader = ""
        case "ignore":
            options.fileHeader = nil
        default:
            // Normalize the header
            let header = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            let isMultiline = header.hasPrefix("/*")
            var lines = header.components(separatedBy: "\\n")
            lines = lines.flatMap {
                var line = $0
                if !isMultiline, !line.hasPrefix("//") {
                    line = "//" + line
                }
                if let range = line.range(of: "{year}") {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy"
                    line.replaceSubrange(range, with: formatter.string(from: Date()))
                }
                return line
            }
            while lines.last?.isEmpty == true {
                lines.removeLast()
            }
            options.fileHeader = lines.joined(separator: "\n")
        }
    }
    try processOption("ifdef", in: args, from: &arguments) {
        if let mode = IndentMode(rawValue: $0.lowercased()) {
            options.ifdefIndent = mode
        } else {
            throw FormatError.options("")
        }
    }
    try processOption("wraparguments", in: args, from: &arguments) {
        if let mode = WrapMode(rawValue: $0.lowercased()) {
            options.wrapArguments = mode
        } else {
            throw FormatError.options("")
        }
    }
    try processOption("wrapelements", in: args, from: &arguments) {
        if let mode = WrapMode(rawValue: $0.lowercased()) {
            options.wrapElements = mode
        } else {
            throw FormatError.options("")
        }
    }
    try processOption("hexliteralcase", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "uppercase", "upper":
            options.uppercaseHex = true
        case "lowercase", "lower":
            options.uppercaseHex = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("exponentcase", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "uppercase", "upper":
            options.uppercaseExponent = true
        case "lowercase", "lower":
            options.uppercaseExponent = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("decimalgrouping", in: args, from: &arguments) {
        guard let grouping = Grouping(rawValue: $0.lowercased()) else {
            throw FormatError.options("")
        }
        options.decimalGrouping = grouping
    }
    try processOption("binarygrouping", in: args, from: &arguments) {
        guard let grouping = Grouping(rawValue: $0.lowercased()) else {
            throw FormatError.options("")
        }
        options.binaryGrouping = grouping
    }
    try processOption("octalgrouping", in: args, from: &arguments) {
        guard let grouping = Grouping(rawValue: $0.lowercased()) else {
            throw FormatError.options("")
        }
        options.octalGrouping = grouping
    }
    try processOption("hexgrouping", in: args, from: &arguments) {
        guard let grouping = Grouping(rawValue: $0.lowercased()) else {
            throw FormatError.options("")
        }
        options.hexGrouping = grouping
    }
    try processOption("patternlet", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "hoist":
            options.hoistPatternLet = true
        case "inline":
            options.hoistPatternLet = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("fragment", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "true", "enabled":
            options.fragment = true
        case "false", "disabled":
            options.fragment = false
        default:
            throw FormatError.options("")
        }
    }
    try processOption("stripunusedargs", in: args, from: &arguments) {
        guard let type = ArgumentType(rawValue: $0.lowercased()) else {
            throw FormatError.options("")
        }
        options.stripUnusedArguments = type
    }
    try processOption("experimental", in: args, from: &arguments) {
        switch $0.lowercased() {
        case "enabled", "true":
            options.experimentalRules = true
        case "disabled", "false":
            options.experimentalRules = false
        default:
            throw FormatError.options("")
        }
    }
    // Deprecated
    try processOption("hexliterals", in: args, from: &arguments) {
        print("`--hexliterals` option is deprecated. Use `--hexliteralcase` instead", as: .warning)
        switch $0.lowercased() {
        case "uppercase", "upper":
            options.uppercaseHex = true
        case "lowercase", "lower":
            options.uppercaseHex = false
        default:
            throw FormatError.options("")
        }
    }
    assert(arguments.isEmpty, "\(arguments.joined(separator: ","))")
    return options
}

let fileArguments = [
    // File options
    "symlinks",
]

let formatArguments = [
    // Format options
    "allman",
    "binarygrouping",
    "commas",
    "comments",
    "decimalgrouping",
    "empty",
    "exponentcase",
    "header",
    "hexgrouping",
    "hexliteralcase",
    "ifdef",
    "indent",
    "insertlines",
    "linebreaks",
    "octalgrouping",
    "ranges",
    "removelines",
    "semicolons",
    "stripunusedargs",
    "trimwhitespace",
    "wraparguments",
    "wrapelements",
    "patternlet",
]

let deprecatedArguments = [
    "hexliterals",
]

let commandLineArguments = [
    // File options
    "inferoptions",
    "output",
    "fragment",
    "cache",
    "verbose",
    // Rules
    "disable",
    "enable",
    "rules",
    // Misc
    "help",
    "version",
    // Format options
    "experimental",
] + deprecatedArguments + fileArguments + formatArguments
