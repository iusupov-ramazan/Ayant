import SwiftUI
import AyantDomain
import AyantFeatures

/// «Лояльность» — экран настройки лояльности заведения (SCREENS.md H6).
///
/// Здесь только то, что есть на самом деле: карта штампов и конфиг баллов
/// САН. Прежние «ROI-герой» с выдуманными «2,4×» и калькулятор, который ничего
/// не сохранял, убраны — цифры, за которыми не стоит данных, подрывают доверие
/// ко всему экрану.
///
/// Конфиг баллов теперь правит сам владелец: режим, награды и правила
/// собираются в черновик (`PointsDraft`), одна кнопка «Сохранить» отправляет
/// `HostIntent.savePointsConfig`, а серверные ограничения (кэшбэк ≤ 20 %,
/// пауза 0…1440 мин и т. д.) накладывает чистый `HostForms.applyPoints`.
/// Админ-панель правит те же поля Firestore — кто сохранил последним, тот и прав.
struct HostLoyaltyView: View {
    @EnvironmentObject private var host: HostStore

    @State private var selectedVenueID: String?
    /// Черновик текста награды карты штампов, пока пользователь печатает.
    /// Сохраняется по Return, по паузе в наборе (`rewardCommit`) и при смене заведения.
    @State private var rewardDraft: String?
    @State private var rewardCommit: Task<Void, Never>?

    /// Черновик конфига баллов и снимок, с которого он начат: «есть правки» —
    /// это `draft != baseline`, без отдельных флагов.
    @State private var draft = PointsDraft()
    @State private var baseline = PointsDraft()
    /// Заведение, на которое хотят переключиться при несохранённых правках.
    @State private var pendingSwitchID: String?
    @State private var savedFlash = false
    @State private var savedFlashTask: Task<Void, Never>?

    private var venue: HostVenueDTO? {
        host.state.venues.first { $0.id == selectedVenueID } ?? host.state.venues.first
    }

    private var isDirty: Bool { draft != baseline }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stampCardSection
                    if venue != nil {
                        pointsMasterSection
                        if draft.enabled {
                            modesSection
                            rewardsSection
                            rulesSection
                            guestPreview
                        }
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .sanScreenEnter()
            }
            .safeAreaInset(edge: .bottom) {
                if venue != nil { saveFooter }
            }
            .sanScreenBackground()
            .sanStatusBarCap()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if selectedVenueID == nil { selectedVenueID = host.state.venues.first?.id }
                loadDraft()
            }
            .onChange(of: venue?.id) { _, _ in loadDraft() }
            // Синк с сервера обновил заведение, пока правок нет — подхватываем,
            // но недописанный черновик не затираем.
            .onChange(of: host.state.venues) { _, _ in if !isDirty { loadDraft() } }
            .onDisappear { flushRewardDraft() }
            .confirmationDialog("Несохранённые изменения",
                                isPresented: Binding(get: { pendingSwitchID != nil },
                                                     set: { if !$0 { pendingSwitchID = nil } }),
                                titleVisibility: .visible) {
                Button("Перейти без сохранения", role: .destructive) {
                    if let id = pendingSwitchID { switchVenue(to: id) }
                    pendingSwitchID = nil
                }
                Button("Остаться", role: .cancel) { pendingSwitchID = nil }
            } message: {
                Text("Настройки баллов этого заведения не сохранены. Перейти к другому заведению?")
            }
        }
    }

    // MARK: Черновик баллов

    private func loadDraft() {
        let d = venue.map { PointsDraft($0) } ?? PointsDraft()
        draft = d
        baseline = d
    }

    private func switchVenue(to id: String) {
        SanHaptics.selection()
        // Черновик награды карты штампов принадлежит прошлому заведению:
        // дописываем его туда и начинаем с чистого поля.
        flushRewardDraft()
        selectedVenueID = id
        rewardDraft = nil
    }

    private func savePoints() {
        guard let v = venue else { return }
        SanHaptics.save()
        host.send(.savePointsConfig(venueID: v.id, fields: draft.fields))
        // Стор уже применил ограничения — показываем то, что реально сохранилось.
        loadDraft()
        savedFlashTask?.cancel()
        withAnimation(.sanStandard) { savedFlash = true }
        savedFlashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.sanStandard) { savedFlash = false }
        }
    }

    // MARK: Карта штампов

    private var stampCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Карта штампов")
            if let v = venue, draft.enabled {
                // Механика одна на заведение: пока включены баллы САН, штампы не
                // начисляются (сервер отвечает `loyalty_is_points`). Показываем
                // это здесь, а не даём щёлкать тумблером впустую.
                SanNoteCard(text: v.pointsEnabled
                    ? "У заведения включены баллы САН — карта штампов не начисляется. Механика лояльности одна: либо баллы, либо штампы."
                    : "После сохранения баллов САН карта штампов перестанет начисляться. Механика лояльности одна: либо баллы, либо штампы.")
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
                        guard !isOn else { return }
                        // Несохранённые правки баллов не переносим молча на
                        // другое заведение — спрашиваем.
                        if isDirty { pendingSwitchID = v.id } else { switchVenue(to: v.id) }
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

    // MARK: Баллы САН — главный тумблер

    private var pointsMasterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Баллы САН")
            VStack(spacing: 0) {
                SanGradientToggle(title: "Начислять баллы САН",
                                  subtitle: "Гость копит баллы у вас и тратит их на ваши награды",
                                  isOn: $draft.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .sanGroupCard(radius: SanRadius.card)
            Text("Механика лояльности одна на заведение: пока включены баллы, штампы не начисляются.")
                .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Как начисляем

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Как начисляем")
            SanSegmented(items: HostForms.PointsLimits.modes,
                         title: Self.modeTitle, selection: $draft.mode)
            Text(Self.modeHint(draft.mode))
                .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            SanFieldCard {
                switch draft.mode {
                case "cashback":
                    SanFieldRow(label: "Кэшбэк, %", hint: "До 20% от суммы чека возвращается баллами") {
                        SanFieldInput(placeholder: "5", text: $draft.cashback, keyboard: .decimalPad)
                    }
                case "bands":
                    bandsEditor
                default:
                    SanFieldRow(label: "Баллов за визит", hint: "Одинаково за любой чек, до 10 000") {
                        SanFieldInput(placeholder: "50", text: $draft.flat, keyboard: .numberPad)
                    }
                }
            }
        }
    }

    private static func modeTitle(_ mode: String) -> String {
        switch mode {
        case "bands": return "Диапазоны"
        case "cashback": return "Кэшбэк"
        default: return "Фикс"
        }
    }

    private static func modeHint(_ mode: String) -> LocalizedStringKey {
        switch mode {
        case "bands": return "Баллы зависят от суммы чека: сотрудник выбирает диапазон при скане."
        case "cashback": return "Процент от чека возвращается баллами: сотрудник вводит сумму при скане."
        default: return "Одинаковое число баллов за любой визит — сумму чека вводить не нужно."
        }
    }

    // MARK: Диапазоны

    @ViewBuilder private var bandsEditor: some View {
        ForEach($draft.bands) { $band in
            bandRow($band)
            SanHairline(leading: 16)
        }
        if draft.bands.isEmpty {
            Text("Пока ни одного диапазона — гость ничего не получит.")
                .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                .padding(.horizontal, 16).padding(.top, 13)
        }
        addRowButton("Добавить диапазон") {
            draft.bands.append(.init(id: Self.newID("pb"), maxAmount: "", points: ""))
        }
        Text("Диапазоны идут по возрастанию суммы; чек больше последней границы попадает в последний диапазон.")
            .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.bottom, 13)
    }

    private func bandRow(_ band: Binding<PointsDraft.BandRow>) -> some View {
        HStack(spacing: 8) {
            caption("до")
            SanFieldInput(placeholder: "500", text: band.maxAmount, keyboard: .numberPad)
                .frame(width: 72)
            caption("сом →")
            SanFieldInput(placeholder: "10", text: band.points, keyboard: .numberPad)
                .frame(width: 64)
            caption("баллов")
            Spacer(minLength: 4)
            removeButton { draft.bands.removeAll { $0.id == band.wrappedValue.id } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Награды

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Награды")
            if draft.rewards.isEmpty {
                Text("Добавьте хотя бы одну награду — иначе гостю не на что тратить баллы.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .sanCard(padding: 0, radius: SanRadius.card)
            }
            ForEach($draft.rewards) { $reward in
                rewardCard($reward)
            }
            Button {
                SanHaptics.selection()
                withAnimation(.sanStandard) {
                    draft.rewards.append(.init(id: Self.newID("rw"), title: "", type: "item",
                                               cost: "", ratio: "1", active: true))
                }
            } label: {
                Label("Добавить награду", systemImage: "plus")
            }
            .buttonStyle(SanPillButton(accent: true))
        }
    }

    private func rewardCard(_ reward: Binding<PointsDraft.RewardRow>) -> some View {
        let isMoney = reward.wrappedValue.type == "money"
        return SanFieldCard {
            SanFieldRow(label: "Название") {
                SanFieldInput(placeholder: "Капучино в подарок", text: reward.title)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Тип",
                        hint: isMoney ? "Гость списывает баллы как скидку с чека"
                                      : "Конкретный товар или услуга за фиксированную цену в баллах") {
                SanSegmented(items: ["item", "money"],
                             title: { $0 == "money" ? "Скидка сомами" : "Товар" },
                             selection: reward.type)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: isMoney ? "Минимум баллов к списанию" : "Стоимость, баллов") {
                SanFieldInput(placeholder: "100", text: reward.cost, keyboard: .numberPad)
            }
            if isMoney {
                SanHairline(leading: 16)
                SanFieldRow(label: "Курс", hint: "Не меньше 1 сома за балл") {
                    HStack(spacing: 8) {
                        caption("1 балл =")
                        SanFieldInput(placeholder: "1", text: reward.ratio, keyboard: .decimalPad)
                            .frame(width: 64)
                        caption("сом")
                        Spacer(minLength: 0)
                    }
                }
            }
            SanHairline(leading: 16)
            SanGradientToggle(title: "Активна",
                              subtitle: "Выключенная награда не видна гостю",
                              isOn: reward.active)
                .padding(.horizontal, 16).padding(.vertical, 13)
            SanHairline(leading: 16)
            Button(role: .destructive) {
                SanHaptics.selection()
                withAnimation(.sanStandard) {
                    draft.rewards.removeAll { $0.id == reward.wrappedValue.id }
                }
            } label: {
                Label("Удалить награду", systemImage: "trash")
                    .font(.golos(14, .semibold))
                    .foregroundStyle(Color(hex: 0xE8556B))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Правила

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Правила")
            SanFieldCard {
                SanFieldRow(label: "Пауза между начислениями, мин",
                            hint: "Защита от повторного скана одного чека. 0 — без паузы, начислять на каждом скане; максимум 1440.") {
                    SanFieldInput(placeholder: "60", text: $draft.cooldownMinutes, keyboard: .numberPad)
                }
                SanHairline(leading: 16)
                SanFieldRow(label: "Срок сгорания, мес",
                            hint: "С последней активности гостя, от 1 до 24") {
                    SanFieldInput(placeholder: "6", text: $draft.expiryMonths, keyboard: .numberPad)
                }
                SanHairline(leading: 16)
                SanGradientToggle(title: "Гость списывает сам в приложении",
                                  subtitle: "Выключено — награду сканирует сотрудник по QR гостя",
                                  isOn: Binding(
                                    get: { draft.redeemMode == "customerInitiated" },
                                    set: { draft.redeemMode = $0 ? "customerInitiated" : "staffScan" }))
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
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
            Text("Так карта выглядит у гостя — с учётом несохранённых правок")
                .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
        }
    }

    /// Доменное заведение для превью — черновик, уже приведённый к серверным
    /// ограничениям, чтобы гость видел то же, что сохранится.
    private var previewVenue: Venue? {
        guard let dto = venue else { return nil }
        var v = HostForms.applyPoints(to: dto, fields: draft.fields).asVenue
        v.pointsEnabled = true
        return v
    }

    // MARK: Подвал — сохранение

    private var saveFooter: some View {
        SanStickyFooter {
            Button("Сохранить") { savePoints() }
                .buttonStyle(SanPrimaryButton())
                .disabled(!isDirty)
                .opacity(isDirty ? 1 : 0.6)
            Group {
                if savedFlash {
                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.sanOpen)
                } else if isDirty {
                    Text("Новые правила применяются к следующим сканам сразу после сохранения.")
                        .foregroundStyle(Color(hex: 0x9A9188))
                } else {
                    Text("Изменений нет.")
                        .foregroundStyle(Color(hex: 0x9A9188))
                }
            }
            .font(.golos(11.5, .semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Мелочи

    private func eyebrow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .textCase(.uppercase)
            .sanEyebrowText()
            .foregroundStyle(Color.sanInkSoft)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.golos(13)).foregroundStyle(Color.sanInkSoft).fixedSize()
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { action() }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: 0xE8556B))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Удалить")
    }

    private func addRowButton(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { action() }
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .font(.golos(14, .semibold))
                .foregroundStyle(Color.sanAccentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private static func newID(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.prefix(8))"
    }
}

// MARK: - Черновик конфига баллов

/// Форма баллов в том виде, в каком её держат текстовые поля: числа — строками,
/// чтобы пустое поле и «в процессе набора» не превращались в 0 на каждом
/// символе. В `PointsFields` конвертируется один раз, при сохранении.
private struct PointsDraft: Equatable {
    struct BandRow: Identifiable, Equatable {
        let id: String
        var maxAmount: String
        var points: String
    }
    struct RewardRow: Identifiable, Equatable {
        let id: String
        var title: String
        var type: String      // "item" | "money"
        var cost: String
        var ratio: String
        var active: Bool
    }

    var enabled = false
    var mode = "flat"
    var flat = ""
    var cashback = ""
    var bands: [BandRow] = []
    var rewards: [RewardRow] = []
    var expiryMonths = ""
    var cooldownMinutes = ""
    var redeemMode = "staffScan"

    init() {}

    init(_ dto: HostVenueDTO) {
        let f = HostForms.pointsFields(from: dto)
        enabled = f.pointsEnabled
        mode = f.pointsMode
        flat = f.pointsFlat > 0 ? String(f.pointsFlat) : ""
        cashback = f.cashbackPercent > 0 ? f.cashbackPercent.sanPercentText : ""
        bands = f.pointsBands.enumerated().map { i, b in
            BandRow(id: "pb_\(i)", maxAmount: String(b.maxAmount), points: String(b.points))
        }
        rewards = f.pointsRewards.map { r in
            RewardRow(id: r.id, title: r.title, type: r.type, cost: String(r.cost),
                      ratio: r.ratio.sanPercentText, active: r.active)
        }
        expiryMonths = String(f.pointsExpiryMonths)
        cooldownMinutes = String(f.earnCooldownMinutes)
        redeemMode = f.redeemMode
    }

    /// Поля формы для стора. Пустое/нечитаемое число — 0 (или 1 для курса);
    /// дальше `HostForms.applyPoints` доводит до допустимых границ.
    var fields: HostForms.PointsFields {
        HostForms.PointsFields(
            pointsEnabled: enabled,
            pointsMode: mode,
            pointsFlat: Self.int(flat),
            pointsBands: bands.map { PointsBand(maxAmount: Self.int($0.maxAmount),
                                                points: Self.int($0.points)) },
            cashbackPercent: Self.double(cashback),
            pointsRewards: rewards.map { r in
                PointsReward(id: r.id, type: r.type, title: r.title,
                             cost: Self.int(r.cost),
                             ratio: Self.double(r.ratio, fallback: 1), active: r.active)
            },
            pointsExpiryMonths: Self.int(expiryMonths),
            redeemMode: redeemMode,
            earnCooldownMinutes: Self.int(cooldownMinutes))
    }

    private static func int(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Десятичная запятая — норма на русской клавиатуре.
    private static func double(_ s: String, fallback: Double = 0) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? fallback
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
