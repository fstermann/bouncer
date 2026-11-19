import BouncerFoundation
import Carbon.HIToolbox

/// The notch pages' ⌘⇧ combinations.
enum PageHotKey: UInt32 {
    case todos = 1
    case notes = 2
    case previousPage = 3
    case nextPage = 4
    case claude = 5

    var shortcut: HotKey.Shortcut {
        let code = switch self {
        case .todos: kVK_ANSI_B
        case .notes: kVK_ANSI_N
        case .previousPage: kVK_LeftArrow
        case .nextPage: kVK_RightArrow
        case .claude: kVK_ANSI_C
        }
        return HotKey.Shortcut(keyCode: code, modifiers: HotKey.Shortcut.commandShift)
    }
}

extension HotKey {
    convenience init?(_ key: PageHotKey, action: @MainActor @escaping () -> Void) {
        self.init(key.shortcut, id: key.rawValue, action: action)
    }
}
