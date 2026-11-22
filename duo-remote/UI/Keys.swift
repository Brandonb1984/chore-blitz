import UIKit

/// X11 keysyms that macOS Screen Sharing understands.
enum Keysym {
    static let backspace: UInt32 = 0xff08
    static let tab: UInt32 = 0xff09
    static let ret: UInt32 = 0xff0d
    static let escape: UInt32 = 0xff1b
    static let forwardDelete: UInt32 = 0xffff
    static let home: UInt32 = 0xff50
    static let left: UInt32 = 0xff51
    static let up: UInt32 = 0xff52
    static let right: UInt32 = 0xff53
    static let down: UInt32 = 0xff54
    static let pageUp: UInt32 = 0xff55
    static let pageDown: UInt32 = 0xff56
    static let end: UInt32 = 0xff57
    static let f1: UInt32 = 0xffbe
    static let shift: UInt32 = 0xffe1
    static let control: UInt32 = 0xffe3
    static let capsLock: UInt32 = 0xffe5
    /// Command. macOS Screen Sharing maps Super_L (and Meta_L) to ⌘.
    static let command: UInt32 = 0xffeb
    static let option: UInt32 = 0xffe9
}

enum KeyKind: Equatable {
    case char(lower: String, upper: String)   // letters / symbols; sends the character
    case special(UInt32)                       // fixed keysym
    case modifier(Modifier)
    case fn
    case lockScreen
    case arrows                                // the inverted-T cluster, laid out specially
}

enum Modifier: CaseIterable {
    case shift, control, option, command
    var keysym: UInt32 {
        switch self {
        case .shift: return Keysym.shift
        case .control: return Keysym.control
        case .option: return Keysym.option
        case .command: return Keysym.command
        }
    }
}

struct KeyDef {
    var label: String
    var top: String = ""
    var units: CGFloat = 1
    var kind: KeyKind
    var small: Bool = false   // small corner label like a MacBook modifier key
}

/// MacBook US layout, row by row (each row is 14.5 units wide).
enum MacLayout {
    static func ch(_ lower: String, _ upper: String? = nil, top: String = "") -> KeyDef {
        let up = upper ?? lower.uppercased()
        return KeyDef(label: lower.count == 1 && lower.lowercased() != lower.uppercased() ? lower.uppercased() : lower,
                      top: top, kind: .char(lower: lower, upper: up))
    }

    static let rows: [[KeyDef]] = {
        var fnRow = [KeyDef(label: "esc", units: 1.5, kind: .special(Keysym.escape), small: true)]
        for i in 0..<12 { fnRow.append(KeyDef(label: "F\(i + 1)", kind: .special(Keysym.f1 + UInt32(i)), small: true)) }
        fnRow.append(KeyDef(label: "lock", kind: .lockScreen, small: true))

        let nums: [(String, String)] = [("`","~"),("1","!"),("2","@"),("3","#"),("4","$"),("5","%"),
                                        ("6","^"),("7","&"),("8","*"),("9","("),("0",")"),("-","_"),("=","+")]
        var r1 = nums.map { ch($0.0, $0.1, top: $0.1) }
        r1.append(KeyDef(label: "delete", units: 1.5, kind: .special(Keysym.backspace), small: true))

        var r2 = [KeyDef(label: "tab", units: 1.5, kind: .special(Keysym.tab), small: true)]
        r2 += "qwertyuiop".map { ch(String($0)) }
        r2 += [ch("[", "{", top: "{"), ch("]", "}", top: "}"), ch("\\", "|", top: "|")]

        var r3 = [KeyDef(label: "caps lock", units: 1.75, kind: .special(Keysym.capsLock), small: true)]
        r3 += "asdfghjkl".map { ch(String($0)) }
        r3 += [ch(";", ":", top: ":"), ch("'", "\"", top: "\""),
               KeyDef(label: "return", units: 1.75, kind: .special(Keysym.ret), small: true)]

        var r4 = [KeyDef(label: "shift", units: 2.25, kind: .modifier(.shift), small: true)]
        r4 += "zxcvbnm".map { ch(String($0)) }
        r4 += [ch(",", "<", top: "<"), ch(".", ">", top: ">"), ch("/", "?", top: "?"),
               KeyDef(label: "shift", units: 2.25, kind: .modifier(.shift), small: true)]

        let r5 = [KeyDef(label: "fn", kind: .fn, small: true),
                  KeyDef(label: "control", top: "⌃", kind: .modifier(.control), small: true),
                  KeyDef(label: "option", top: "⌥", kind: .modifier(.option), small: true),
                  KeyDef(label: "command", top: "⌘", units: 1.25, kind: .modifier(.command), small: true),
                  KeyDef(label: "", units: 5, kind: .char(lower: " ", upper: " ")),
                  KeyDef(label: "command", top: "⌘", units: 1.25, kind: .modifier(.command), small: true),
                  KeyDef(label: "option", top: "⌥", kind: .modifier(.option), small: true),
                  KeyDef(label: "", units: 3, kind: .arrows)]
        return [fnRow, r1, r2, r3, r4, r5]
    }()

    /// Keysym for a typed character (Latin-1 and ASCII map 1:1).
    static func keysym(for s: String) -> UInt32 {
        guard let scalar = s.unicodeScalars.first else { return 0 }
        let v = scalar.value
        if v < 0x100 { return v }
        return 0x01000000 | v
    }
}
