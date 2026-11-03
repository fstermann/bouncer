import AppKit

/// Claude's mark, from Simple Icons (CC0), drawn from its SVG path so no module needs an asset catalog.
public enum ClaudeMark {
    /// In a 24-unit box, y down.
    static let pathData = """
        m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971\
        -2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514\
        .0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714\
        -.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 \
        1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c\
        -.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 \
        1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589\
        .3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l\
        .2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657\
        -1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396\
        -.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482\
        .1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107\
        -1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486\
        -2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071\
        .2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286\
        .2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425\
        -.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 \
        2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608\
        -.7467.2307-.2429 1.9064-1.3114Z
        """

    static var path: CGPath { SVGPath.parse(pathData) }

    /// A template image `side` points square, which tints like an SF Symbol.
    public static func image(side: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / 24, y: rect.height / 24)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude"
        return image
    }
}

/// The subset of SVG path syntax the mark uses: moves, lines, cubic curves and closes, absolute or relative.
enum SVGPath {
    static func parse(_ data: String) -> CGPath {
        var reader = Reader(text: Substring(data))
        while reader.step() {}
        return reader.path
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private struct Reader {
        let path = CGMutablePath()
        var text: Substring
        var command: Character = "M"
        var point = CGPoint.zero
        var start = CGPoint.zero

        /// Takes one command letter or one segment; `false` at the end, or at syntax the mark does not use.
        mutating func step() -> Bool {
            switch next() {
            case .command(let letter):
                command = letter
                if letter == "Z" || letter == "z" {
                    path.closeSubpath()
                    point = start
                }
                return true
            case .number(let first):
                return draw(from: first)
            case nil:
                return false
            }
        }

        private mutating func draw(from first: CGFloat) -> Bool {
            let relative = command.isLowercase
            let origin = relative ? point : .zero
            switch command.uppercased() {
            case "M", "L":
                guard let second = numbers(1)?.first else { return false }
                let target = CGPoint(x: origin.x + first, y: origin.y + second)
                if command.uppercased() == "M" {
                    path.move(to: target)
                    start = target
                    // Further pairs after a move are lines.
                    command = relative ? "l" : "L"
                } else {
                    path.addLine(to: target)
                }
                point = target
            case "H":
                point.x = origin.x + first
                path.addLine(to: point)
            case "V":
                point.y = origin.y + first
                path.addLine(to: point)
            case "C":
                guard let rest = numbers(5) else { return false }
                let values = [first] + rest
                let points = stride(from: 0, to: 6, by: 2).map {
                    CGPoint(x: origin.x + values[$0], y: origin.y + values[$0 + 1])
                }
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
                point = points[2]
            default:
                return false
            }
            return true
        }

        private mutating func numbers(_ count: Int) -> [CGFloat]? {
            var values: [CGFloat] = []
            for _ in 0..<count {
                guard case .number(let value) = next() else { return nil }
                values.append(value)
            }
            return values
        }

        /// Numbers run together where a sign or a second decimal point starts the next, as in `.079-.2307`.
        private mutating func next() -> Token? {
            while let first = text.first, first == " " || first == "," || first.isNewline { text.removeFirst() }
            guard let first = text.first else { return nil }
            if first.isLetter {
                text.removeFirst()
                return .command(first)
            }
            var end = text.startIndex
            var hasPoint = false
            if text[end] == "-" || text[end] == "+" { end = text.index(after: end) }
            while end < text.endIndex {
                let character = text[end]
                if character == "." {
                    if hasPoint { break }
                    hasPoint = true
                } else if !character.isNumber {
                    break
                }
                end = text.index(after: end)
            }
            let number = CGFloat(Double(text[text.startIndex..<end]) ?? 0)
            text = text[end...]
            return .number(number)
        }
    }
}
