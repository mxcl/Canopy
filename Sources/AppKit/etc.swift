import AppKit

#if !swift(>=4.2)
extension NSStoryboardSegue.Identifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
    public init(unicodeScalarLiteral value: String) {
        self.init(value)
    }
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }
}
#endif

enum Satisfaction {
    case all
    case some
    case none
}

extension Collection {
    func satisfaction(_ predicate: (Element) -> Bool) -> Satisfaction {
        if isEmpty {
            return .none
        }
        var seenTrue = false
        var seenFalse = false
        for ee in self {
            if predicate(ee) {
                if seenFalse {
                    return .some
                }
                seenTrue = true
            } else if seenTrue {
                return .some
            } else {
                seenFalse = true
            }
        }
        if seenTrue, !seenFalse {
            return .all
        } else {
            return .none
        }
    }

    func satisfaction(_ keyPath: KeyPath<Element, Bool>) ->Satisfaction {
        return satisfaction {
            $0[keyPath: keyPath]
        }
    }
}

class ViewWithBackgroundColor: NSView {
    @IBInspectable var backgroundColor: NSColor? {
        get {
            guard let layer = layer, let backgroundColor = layer.backgroundColor else { return nil }
            return NSColor(cgColor: backgroundColor)
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }
}
