import SwiftUI
import AyantDomain
import AyantFeatures

/// «Лояльность» — флагманский экран хоста (SCREENS.md H6).
///
/// Одновременно питч, который выигрывает заведение, и поверхность настройки.
/// Порядок разделов намеренный: сначала ценность, потом органы управления.
///
/// ВАЖНО: конфиг баллов на хост-стороне сейчас **только для чтения** — им
/// владеет админ-панель, и путь сохранения хоста его не пишет (см. CLAUDE.md).
/// Поэтому режимы/награды/правила здесь показываются, но не редактируются:
/// сделать их записываемыми — это изменение Firestore-правил и `HostForms`,
/// а не UI-решение. Калькулятор считает предпросмотр через `PointsMath`.
struct HostLoyaltyView: View {
    @EnvironmentObject private var host: HostStore

    @State private var selectedVenueID: String?
    /// Процент кэшбэка в калькуляторе — локальный «а что если», не запись.
    @State private var calcPercent: Double = 5
    /// Черновик текста награды, пока пользователь печатает.
    @State private var rewardDraft: String?
    private static let calcBill = 1_200

    private var venue: HostVenueDTO? {
        host.state.venues.first { $0.id == selectedVenueID } ?? host.state.venues.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    roiHero
                    modesSection
                    calculator
                    stampCardSection
                    rewardsSection
                    rulesSection
                    guestPreview
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .sanScreenEnter()
            }
            .sanScreenBackground()
            .sanStatusBarCap()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if selectedVenueID == nil { selectedVenueID = host.state.venues.first?.id }
                if let v = venue, v.cashbackPercent > 0 { calcPercent = v.cashbackPercent }
            }
        }
    }

    // MARK: Карта штампов — ЕДИНСТВЕННОЕ, что владелец правит сам
    //
    // Конфиг баллов САН принадлежит админ-панели, поэтому выше всё только
    // показывается. А карта штампов (`loyaltyEnabled/Goal/Reward`) — поля
    // самого заведения, их пишет обычное сохранение заведения. Раньше их можно
    // было тронуть лишь через форму заведения, и вкладка «Лояльность» выходила
    // экраном-читалкой.

    private var stampCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Карта штампов")
            if let v = venue, v.pointsEnabled {
                // Механика одна на заведение: пока включены баллы САН, штампы не
                // начисляются (сервер отвечает `loyalty_is_points`). Показываем
                // это здесь, а не даём щёлкать тумблером впустую.
                SanNoteCard(text: "У заведения включены баллы САН — карта штампов не начисляется. Механика лояльности одна: либо баллы, либо штампы.")
            } else if let v = venue {
                VStack(spacing: 0) {
                    SanGradientToggle(title: "Программа лояльности",
                                      subtitle: "Штамп за каждый использованный купон",
                                      isOn: Binding(
                                        get: { v.loyaltyEnabled },
                                        set: { on in commit(v) { $0.loyaltyEnabled = on } }))
                        .padding(.horizontal, 16).padding(.vertical, 13)

                    if v.loyaltyEnabled {
                        SanHairline(leading: 16)
                        SanFieldRow(label: "Штампов до награды") {
                            Stepper(value: Binding(
                                get: { v.loyaltyGoal },
                                set: { newValue in commit(v) { $0.loyaltyGoal = max(2, newValue) } }
                            ), in: 2...20) {
                                Text("\(v.loyaltyGoal)")
                                    .font(.golos(15.5, .semibold))
                                    .foregroundStyle(Color.sanInk)
                            }
                        }
                        SanHairline(leading: 16)
                        SanFieldRow(label: "Награда") {
                            SanFieldInput(placeholder: "Награда (напр. Бесплатный кофе)",
                                          text: Binding(
                                            get: { rewardDraft ?? v.loyaltyReward },
                                            set: { rewardDraft = $0 }))
                                .onSubmit { commit(v) { $0.loyaltyReward = rewardDraft ?? $0.loyaltyReward } }
                        }
                    }
                }
                .sanGroupCard(radius: SanRadius.card)

                if v.loyaltyEnabled {
                    Text("Гость получает штамп за каждое погашение купона у вас. На \(v.loyaltyGoal)-м штампе — «\(rewardDraft ?? v.loyaltyReward)» купоном.")
                        .font(.golos(12.5))
                        .foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SanNoteCard(text: "Добавьте заведение, чтобы включить карту штампов.")
            }
        }
    }

    /// Сохраняет ОДНО поле, перенося остальные из DTO: `saveVenue` принимает
    /// форму целиком, и собирать её по кусочкам — верный способ затереть чужое.
    private func commit(_ dto: HostVenueDTO, _ change: (inout HostForms.VenueFields) -> Void) {
        var fields = HostForms.fields(from: dto)
        change(&fields)
        host.send(.saveVenue(existing: dto, fields: fields))
    }

    // MARK: Заголовок

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Баллы САН")
                .sanEditorialTitle(42)
                .foregroundStyle(Color.sanInk)
            Text("Баллы копятся у вас и тратятся у вас. Это единственный механизм, который возвращает гостя именно к вам.")
                .sanText(14, .regular, lineHeight: 1.45)
                .foregroundStyle(Color.sanInkSoft)
                .frame(maxWidth: 290, alignment: .leading)
                .padding(.top, 9)

            if host.state.venues.count > 1 {
                venuePicker.padding(.top, 14)
            }
        }
    }

    private var venuePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(host.state.venues) { v in
                    let isOn = v.id == venue?.id
                    Button {
                        SanHaptics.selection()
                        selectedVenueID = v.id
                        if v.cashbackPercent > 0 { calcPercent = v.cashbackPercent }
                    } label: {
                        Text(v.name)
                            .font(.golos(13, .bold))
                            .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background {
                                if isOn { Capsule().fill(LinearGradient.sanAccentGradient) }
                                else { Capsule().fill(Color.sanSurface) }
                            }
                    }
                    .buttonStyle(.sanPress(0.93))
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    // MARK: 2. ROI-герой

    private var roiHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Гости с баллами возвращаются в 2,4 раза чаще")
                .sanText(27, .heavy, tracking: -1.3, lineHeight: 1.1)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 18) {
                roiStat("2,4×", "повторные визиты")
                roiStat("+18%", "средний чек")
                roiStat("412", "активных карт")
            }
            .padding(.top, 18)

            Text("Баллы финансирует заведение. Платформа не берёт комиссию с начислений и списаний.")
                .font(.golos(12.5, .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.top, 18)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.sanAccentGradient,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sanShadow(.hero)
    }

    private func roiStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.golos(26, .heavy)).foregroundStyle(.white)
            Text(label)
                .font(.golos(11)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 3. Как начисляем

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Как начисляем")
            HStack(spacing: 8) {
                modeCard("Фикс", "Столько же за любой визит", mode: "flat")
                modeCard("Диапазоны", "По сумме чека", mode: "bands")
                modeCard("Кэшбэк", "% от чека баллами", mode: "cashback")
            }
            Text("Режим задаётся в админ-панели — здесь он только показан.")
                .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
        }
    }

    private func modeCard(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, mode: String) -> some View {
        let isOn = (venue?.pointsMode ?? "flat") == mode
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.golos(13.5, .heavy))
                .foregroundStyle(isOn ? Color.white : Color.sanInk)
            Text(sub)
                .font(.golos(11))
                .foregroundStyle(isOn ? Color.white.opacity(0.88) : Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if isOn {
                shape.fill(LinearGradient.sanAccentGradient)
                    .shadow(color: Color.sanAccent.opacity(0.28), radius: 12, y: 10)
            } else {
                shape.fill(Color.sanSurface)
                    .overlay(shape.strokeBorder(Color.sanHairline, lineWidth: 0.5))
            }
        }
    }

    // MARK: 4. Калькулятор
    //
    // Арифметика — только `PointsMath` (округление half-up, как на сервере).
    // Своей формулы здесь нет и быть не должно.

    private var calculator: some View {
        // Считает домен: `PointsMath.award` — то же округление half-up, что на
        // сервере. Своей формулы здесь нет и быть не должно.
        let config = PointsConfig(pointsEnabled: true, pointsMode: "cashback",
                                  cashbackPercent: calcPercent)
        let award = (try? PointsMath.award(config: config, billAmount: Self.calcBill,
                                           bandIndex: nil).get()) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("Калькулятор")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color.sanEyebrow)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Чек").font(.golos(11.5, .bold)).foregroundStyle(Color.sanSandInk)
                    Text(Self.calcBill.sanThousands)
                        .font(.golos(26, .heavy)).foregroundStyle(Color.sanInk)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC97A3A))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Гость получит").font(.golos(11.5, .bold)).foregroundStyle(Color.sanSandInk)
                    Text("+\(award)")
                        .font(.golos(26, .heavy)).foregroundStyle(Color(hex: 0xE04206))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: award)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            HStack(spacing: 8) {
                ForEach([3.0, 5.0, 8.0, 10.0], id: \.self) { p in
                    Button {
                        SanHaptics.selection()
                        calcPercent = p
                    } label: {
                        Text("\(p.sanPercentText)%")
                            .font(.golos(13, .bold))
                            .foregroundStyle(calcPercent == p ? Color.white : Color.sanSandInk)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background {
                                if calcPercent == p { Capsule().fill(LinearGradient.sanAccentGradient) }
                                else { Capsule().fill(Color.white.opacity(0.8)) }
                            }
                    }
                    .buttonStyle(.sanPress(0.93))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            Text("Максимум \(Int(PointsMath.maxCashbackPercent))%. Пауза между начислениями — \(cooldownMinutes) минут.")
                .font(.golos(11.5)).foregroundStyle(Color.sanSandInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanSandPanel(radius: SanRadius.hero)
    }

    private var cooldownMinutes: Int {
        PointsMath.effectiveCooldownMinutes(venue?.earnCooldownMinutes ?? PointsMath.defaultEarnCooldownMinutes)
    }

    // MARK: 5. Награды

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Награды")
            let rewards = venue?.pointsRewards ?? []
            if rewards.isEmpty {
                Text("Награды пока не заведены — их настраивает админ-панель.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .sanCard(padding: 0, radius: SanRadius.card)
            } else {
                ForEach(Array(rewards.enumerated()), id: \.element.id) { index, r in
                    rewardRow(r).sanRise(index, stagger: 0.07, duration: 0.5)
                }
            }
        }
    }

    private func rewardRow(_ r: PointsReward) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                Text("\(r.cost) баллов · \(r.type == "money" ? "скидка" : "товар")")
                    .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 8)
            // Состояние награды — read-only: писать его может только админ-панель.
            Text(r.active ? "Активна" : "Выключена")
                .font(.golos(12, .bold))
                .foregroundStyle(r.active ? Color.sanOpen : Color.sanInkSoft)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background((r.active ? Color.sanOpen : Color.sanInkSoft).opacity(0.12), in: Capsule())
        }
        .padding(15)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    // MARK: 6. Правила

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Правила")
            VStack(spacing: 0) {
                ruleRow("Пауза между начислениями", "защищает от повторного скана одного чека",
                        "\(cooldownMinutes) мин")
                SanHairline(leading: 16)
                ruleRow("Срок сгорания", "с последней активности гостя",
                        "\(expiryMonths) мес")
                SanHairline(leading: 16)
                ruleRow("Кто списывает", "сотрудник сканирует QR награды",
                        (venue?.redeemMode ?? "staffScan") == "staffScan" ? "Сотрудник" : "Гость")
            }
            .sanGroupCard(radius: SanRadius.card)
        }
    }

    private var expiryMonths: Int {
        // 0 здесь не значение, а «не настроено» — пол в 1 месяц (см. CLAUDE.md).
        let raw = venue?.pointsExpiryMonths ?? 0
        return raw > 0 ? raw : 6
    }

    private func ruleRow(_ title: LocalizedStringKey, _ hint: LocalizedStringKey,
                         _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                Text(hint)
                    .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.golos(14.5, .heavy))
                .foregroundStyle(Color.sanAccentTextStrong)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: 7. Что видит гость

    private var guestPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Что видит гость")
            // Живая связь: карточка перерисовывается, пока хост крутит калькулятор.
            WalletPointsCard(
                card: VenuePointsCard(venueID: venue?.id ?? "preview",
                                      venueName: venue?.name ?? "Ваше заведение",
                                      balance: 340),
                venue: previewVenue,
                isFront: true)
                .padding(6)
                .background(Color.sanSurfaceMuted,
                            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    /// Доменное заведение для превью — берём конфиг текущего и подставляем
    /// процент из калькулятора, чтобы связь «настройка → карта гостя» была видна.
    private var previewVenue: Venue? {
        guard let dto = venue else { return nil }
        var v = Venue(id: dto.id, name: dto.name, category: .cafe, district: "",
                      address: "", phone: "", emoji: "⭐️",
                      gradient: Venue.defaultGradient)
        v.pointsEnabled = true
        v.pointsMode = dto.pointsMode
        v.pointsFlat = dto.pointsFlat
        v.cashbackPercent = calcPercent      // связь «настройка → карта гостя»
        v.pointsRewards = dto.pointsRewards
        return v
    }

    private func eyebrow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .textCase(.uppercase)
            .sanEyebrowText()
            .foregroundStyle(Color.sanInkSoft)
    }
}

extension Int {
    /// Русские тысячи тонким пробелом: «1 200».
    var sanThousands: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.groupingSeparator = "\u{2009}"   // тонкий пробел, как в русской типографике
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
