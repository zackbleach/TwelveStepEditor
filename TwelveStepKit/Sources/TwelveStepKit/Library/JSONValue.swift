import Foundation

/// A JSON value that round-trips the desktop editor's files without losing unknown keys.
///
/// Integers and non-integral numbers are kept apart so that writing a file back does not turn
/// `5` into `5.0`.
public enum JSONValue: Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    /// Mirrors `QVariant::toInt()` for the value kinds found in the editor's files:
    /// numbers convert, numeric strings parse, anything else (including a missing key) is 0.
    public var intValue: Int {
        switch self {
        case .int(let value): value
        case .double(let value): Int(value.rounded())
        case .bool(let value): value ? 1 : 0
        case .string(let value): Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
        default: 0
        }
    }

    /// Mirrors `QVariant::toDouble()`.
    public var doubleValue: Double {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        case .bool(let value): value ? 1 : 0
        case .string(let value): Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
        default: 0
        }
    }

    /// Mirrors `QVariant::toString()` for strings and numbers; other kinds give "".
    public var stringValue: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        default: ""
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    /// Serialises like Qt's `QJsonDocument::toJson()` (indented): 4-space indent, keys sorted,
    /// `"key": value`, and a trailing newline. Files written this way are byte-identical to the
    /// desktop editor's own saves, so saving from the phone doesn't churn the files.
    public func qtIndentedJSON() -> String {
        var out = ""
        write(to: &out, indent: 0)
        out += "\n"
        return out
    }

    private func write(to out: inout String, indent: Int) {
        let pad = String(repeating: " ", count: (indent + 1) * 4)
        let closePad = String(repeating: " ", count: indent * 4)
        switch self {
        case .object(let object):
            guard !object.isEmpty else { out += "{\n\(closePad)}"; return }
            out += "{\n"
            let keys = object.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            for (index, key) in keys.enumerated() {
                out += pad + Self.quoted(key) + ": "
                object[key]!.write(to: &out, indent: indent + 1)
                out += index < keys.count - 1 ? ",\n" : "\n"
            }
            out += closePad + "}"
        case .array(let array):
            guard !array.isEmpty else { out += "[\n\(closePad)]"; return }
            out += "[\n"
            for (index, element) in array.enumerated() {
                out += pad
                element.write(to: &out, indent: indent + 1)
                out += index < array.count - 1 ? ",\n" : "\n"
            }
            out += closePad + "]"
        case .string(let value): out += Self.quoted(value)
        case .int(let value): out += String(value)
        case .double(let value):
            out += value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : "\(value)"
        case .bool(let value): out += value ? "true" : "false"
        case .null: out += "null"
        }
    }

    private static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
