import SwiftUI
import AyantDomain
import AyantFeatures

/// «Лояльность» — экран настройки лояльности заведения (SCREENS.md H6).
///
/// Здесь только то, что есть на самом деле: карта штампов, которую владелец
/// правит сам, и конфиг баллов САН, который он видит. Прежние «ROI-герой» с
/// выдуманными «2,4×» и калькулятор, который ничего не сохранял, убраны —
/// цифры, за которыми не стоит данных, подрывают доверие ко всему экрану.
///
/// ВАЖНО: конфиг баллов на хост-стороне **только для чтения** — им владеет
/// админ-панель, и путь сохранения хоста его не пишет (см. CLAUDE.md).
/// Поэтому режимы/награды/правила здесь показываются, но не редактируются:
/// сделать их записываемыми — это изменение Firestore-правил и `HostForms`,
/// а не UI-решение.
struct HostLoyaltyView: View {
    @EnvironmentObject private var host: HostStore

    @State private var selectedVenueID: String?
    /// Черновик текста награды, пока пользователь печатает. Сохраняется по
    /// Return, по паузе в наборе (`rewardCommit`) и при смене заведения.
    @State private var rewardDraft: String?
    @State private var rewardCommit: Task<Void, Never>?

    private var venue: HostVenueDTO? {
        host.state.venues.first { $0.id == selectedVenueID } ?? host.state.venues.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stampCardSection
                    modesSection
                    rewardsSection
                    rulesSection
                    guestPreview
                    footer
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
            }
            .onDisappear { flushRewardDraft() }
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
                            ), in: 2...12) {
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
                                .onSubmit { flushRewardDraft() }
                                // Return нажимают не все: сохраняем и по паузе в наборе.
                                .onChange(of: rewardDraft) { _, _ in scheduleRewardCommit() }
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

    /// Дебаунс сохранения награды: пишем через 0,8 с после последнего символа,
    /// а не на каждую букву — иначе каждое нажатие уходило бы в Firestore.
    private func scheduleRewardCommit() {
        rewardCommit?.cancel()
        rewardCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            flushRewardDraft()
        }
    }

    /// Записывает черновик награды в ТЕКУЩЕЕ заведение, если он отличается.
    /// Вызывается по Return, по паузе, при уходе с экрана и перед сменой
    /// заведения — чтобы текст не утёк в соседнее.
    private func flushRewardDraft() {
        rewardCommit?.cancel()
        guard let v = venue, let draft = rewardDraft else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != v.loyaltyReward else { return }
        commit(v) { $0.loyaltyReward = trimmed }
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
                        // Черновик награды принадлежит прошлому заведению:
                        // дописываем его туда и начинаем с чистого поля.
                        flushRewardDraft()
                        selectedVenueID = v.id
                        rewardDraft = nil
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

    // MARK: Как начисляем

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

    private var cooldownMinutes: Int {
        PointsMath.effectiveCooldownMinutes(venue?.earnCooldownMinutes ?? PointsMath.defaultEarnCooldownMinutes)
    }

    // MARK: Награды

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

    // MARK: Правила

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

    // MARK: Что видит гость

    private var guestPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Что видит гость")
            // Баланс 0 — это макет, а не чей-то счёт: выдуманные «340 баллов»
            // здесь читались бы как реальные данные.
            WalletPointsCard(
                card: VenuePointsCard(venueID: venue?.id ?? "preview",
                                      venueName: venue?.name ?? "Ваше заведение",
                                      balance: 0),
                venue: previewVenue,
                isFront: true)
                .padding(6)
                .background(Color.sanSurfaceMuted,
                            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            Text("Так карта выглядит у гостя")
                .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
        }
    }

    /// Доменное заведение для превью — конфиг баллов текущего заведения как есть.
    private var previewVenue: Venue? {
        guard let dto = venue else { return nil }
        var v = Venue(id: dto.id, name: dto.name, category: .cafe, district: "",
                      address: "", phone: "", emoji: "⭐️",
                      gradient: Venue.defaultGradient)
        v.pointsEnabled = true
        v.pointsMode = dto.pointsMode
        v.pointsFlat = dto.pointsFlat
        v.cashbackPercent = dto.cashbackPercent
        v.pointsRewards = dto.pointsRewards
        return v
    }

    // MARK: Подвал

    private var footer: some View {
        Text("Настройки баллов меняются через менеджера Ayant")
            .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
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
