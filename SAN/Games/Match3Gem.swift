import SwiftUI
import AyantDomain

/// Самоцвет на поле «Трёх в ряд».
///
/// Камни лежат картинками в `Assets.xcassets` (`gem_ruby`, `gem_amethyst`, …):
/// у каждого вида своя форма И свой цвет, поэтому совпадение видно даже боковым
/// зрением, а игрок, плохо различающий цвета, читает поле по форме.
///
/// Если картинки в каталоге нет, вью рисует огранку кодом — `FacetedGem` ниже.
/// Это не заготовка «на потом», а страховка: пропавший ассет даёт блёклый, но
/// живой камень вместо пустой клетки. Каталог опрашивается один раз на вид.
struct GemView: View {
    let kind: Match3.Kind
    let power: Match3.Power
    /// Насыщенность подсветки: 0 — обычный камень, 1 — вспышка перед сгоранием.
    var flare: Double = 0

    var body: some View {
        ZStack {
            if let art = GemArt.image(for: kind) {
                art.resizable().scaledToFit().padding(2)
            } else {
                FacetedGem(palette: GemPalette.of(kind))
            }
            powerMark
        }
        .saturation(1 + flare * 0.6)
        .brightness(flare * 0.45)
        .shadow(color: GemPalette.of(kind).glow.opacity(0.55 * flare),
                radius: 12 * flare)
    }

    /// Метка спецфишки: полоска показывает, вдоль чего ударит, бомба — что
    /// накроет квадрат. Без метки игрок не понимает, что именно получил.
    @ViewBuilder private var powerMark: some View {
        switch power {
        case .none:
            EmptyView()
        case .line(let horizontal):
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.2), .white, .white.opacity(0.2)],
                                         startPoint: horizontal ? .leading : .top,
                                         endPoint: horizontal ? .trailing : .bottom))
                    .frame(width: horizontal ? side * 0.92 : side * 0.14,
                           height: horizontal ? side * 0.14 : side * 0.92)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .blendMode(.plusLighter)
            }
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        case .bomb:
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: side * 0.07)
                    Circle().strokeBorder(.white.opacity(0.45), lineWidth: side * 0.03)
                        .padding(side * 0.12)
                }
                .frame(width: side * 0.78, height: side * 0.78)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .blendMode(.plusLighter)
            }
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
    }
}

// MARK: - Палитра

/// Цвета камня. Домен о них не знает — там `Kind` это только личность фишки
/// (как и с `Venue.gradient`, где цвет хранится числом).
struct GemPalette {
    let light: Color
    let mid: Color
    let dark: Color
    /// Цвет свечения при вспышке — он же тянется в искры.
    let glow: Color

    static func of(_ kind: Match3.Kind) -> GemPalette {
        switch kind {
        case .ruby:     return GemPalette(light: Color(hex: 0xEDAFAF), mid: Color(hex: 0xCC1C1C), dark: Color(hex: 0x5B0C0C), glow: Color(hex: 0xFF2323))
        case .amethyst: return GemPalette(light: Color(hex: 0xE7C1F6), mid: Color(hex: 0xBB4EE7), dark: Color(hex: 0x542368), glow: Color(hex: 0xB565FF))
        case .rose:     return GemPalette(light: Color(hex: 0xF1BFF0), mid: Color(hex: 0xD749D4), dark: Color(hex: 0x61205F), glow: Color(hex: 0xFF5BC8))
        case .gold:     return GemPalette(light: Color(hex: 0xFDE9B4), mid: Color(hex: 0xFBC22A), dark: Color(hex: 0x715712), glow: Color(hex: 0xFFF334))
        case .emerald:  return GemPalette(light: Color(hex: 0xCCF2B9), mid: Color(hex: 0x6FDB38), dark: Color(hex: 0x326219), glow: Color(hex: 0x8AFF46))
        case .sapphire: return GemPalette(light: Color(hex: 0xC0EAFA), mid: Color(hex: 0x4BC5F2), dark: Color(hex: 0x22586D), glow: Color(hex: 0x5EF6FF))
        }
    }
}

// MARK: - Векторная огранка

/// Круглая огранка кодом — запасной камень, когда картинки в каталоге нет.
///
/// Корона из восьми граней вокруг площадки и звезда внутри неё.
///
/// Свет падает сверху слева — яркость каждой грани считается по углу к нему,
/// поэтому камень читается объёмным, а не как плоская наклейка.
private struct FacetedGem: View {
    let palette: GemPalette

    /// Один `Canvas` вместо двух десятков `Shape`.
    ///
    /// Огранка — это корпус, восемь граней короны, площадка, восемь лучей
    /// звезды, блик и ободок. Отдельными вью это двадцать узлов на камень и
    /// под тысячу на поле, которые SwiftUI пересобирает на каждом кадре
    /// падения. В `Canvas` то же самое рисуется одним проходом.
    var body: some View {
        Canvas { context, size in
            let cut = GemCut(size: min(size.width, size.height),
                             center: CGPoint(x: size.width / 2, y: size.height / 2))

            context.fill(path(cut.outer),
                         with: .linearGradient(Gradient(colors: [palette.mid, palette.dark]),
                                               startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: size.height)))

            // Корона: восемь трапеций между ободом и площадкой.
            for i in 0..<GemCut.sides {
                let facet = path([cut.outer[i], cut.outer[cut.next(i)],
                                  cut.table[cut.next(i)], cut.table[i]])
                context.fill(facet, with: .color(cut.shade(at: i, phase: 0.5)))
            }

            context.fill(path(cut.table),
                         with: .linearGradient(Gradient(colors: [palette.light, palette.mid]),
                                               startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: size.height)))

            // Звезда внутри площадки — та самая «искра» настоящей огранки.
            for i in 0..<GemCut.sides {
                let ray = path([cut.table[i], cut.table[cut.next(i)], cut.center])
                context.fill(ray, with: .color(cut.shade(at: i, phase: 0, strength: 0.55)))
            }

            // Блик: маленькое яркое пятно там, откуда светит.
            let spot = CGPoint(x: cut.center.x - cut.size * 0.17,
                               y: cut.center.y - cut.size * 0.19)
            context.fill(
                Path(ellipseIn: CGRect(x: spot.x - cut.size * 0.17, y: spot.y - cut.size * 0.12,
                                       width: cut.size * 0.34, height: cut.size * 0.24)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .white.opacity(0)]),
                                      center: spot, startRadius: 0, endRadius: cut.size * 0.16))

            context.stroke(path(cut.outer), with: .color(.white.opacity(0.5)),
                           lineWidth: max(1, cut.size * 0.035))
        }
    }

    private func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// Геометрия огранки: два восьмиугольника и яркость граней.
///
/// Свет падает сверху слева — яркость каждой грани считается по углу к нему,
/// поэтому камень читается объёмным, а не как плоская наклейка.
private struct GemCut {
    static let sides = 8
    /// Направление света в экранных координатах (ось Y вниз): сверху слева.
    private static let lightAngle = -2.36

    let size: CGFloat
    let center: CGPoint
    let outer: [CGPoint]
    let table: [CGPoint]

    init(size: CGFloat, center: CGPoint) {
        self.size = size
        self.center = center
        self.outer = Self.polygon(radius: size * 0.48, center: center)
        self.table = Self.polygon(radius: size * 0.26, center: center)
    }

    func next(_ i: Int) -> Int { (i + 1) % Self.sides }

    private static func polygon(radius: CGFloat, center: CGPoint) -> [CGPoint] {
        // Типы расписаны вручную: смесь Double и CGFloat в одном выражении
        // компилятор выводит неприлично долго.
        (0..<sides).map { (i: Int) -> CGPoint in
            let turn: Double = Double(i) / Double(sides)
            let angle: Double = turn * 2 * Double.pi - Double.pi / 2 + Double.pi / Double(sides)
            let x: CGFloat = center.x + radius * CGFloat(cos(angle))
            let y: CGFloat = center.y + radius * CGFloat(sin(angle))
            return CGPoint(x: x, y: y)
        }
    }

    /// Белый или чёрный налёт на грань — в зависимости от того, как она
    /// повёрнута к свету.
    func shade(at index: Int, phase: Double, strength: Double = 1) -> Color {
        let turn: Double = (Double(index) + 0.5 + phase) / Double(Self.sides)
        let angle: Double = turn * 2 * Double.pi - Double.pi / 2
        let lit: Double = cos(angle - Self.lightAngle)      // −1…1
        return lit > 0
            ? Color.white.opacity(0.42 * lit * strength)
            : Color.black.opacity(0.32 * -lit * strength)
    }
}

// MARK: - Картинки из каталога

/// Картинка камня из каталога.
///
/// Каталог опрашивается один раз на вид: `UIImage(named:)` лезет на диск, а
/// на поле сорок девять камней и перерисовываются они каждый кадр анимации.
enum GemArt {
    private static var cache: [Match3.Kind: Image?] = [:]

    static func image(for kind: Match3.Kind) -> Image? {
        if let cached = cache[kind] { return cached }
        let found = UIImage(named: assetName(kind)).map { Image(uiImage: $0) }
        cache[kind] = found
        return found
    }

    /// Имя картинки в каталоге: `gem_ruby`, `gem_amethyst`, …
    static func assetName(_ kind: Match3.Kind) -> String {
        switch kind {
        case .ruby:     return "gem_ruby"
        case .amethyst: return "gem_amethyst"
        case .rose:     return "gem_rose"
        case .gold:     return "gem_gold"
        case .emerald:  return "gem_emerald"
        case .sapphire: return "gem_sapphire"
        }
    }
}
