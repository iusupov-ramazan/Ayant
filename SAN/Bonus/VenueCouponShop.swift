import SwiftUI
import AyantDomain
import AyantFeatures

// MARK: - Магазин купонов за бонусы
//
// Одна витрина в двух местах:
// • вкладка «Бонусы» — «Магазин купонов»: сеткой, как в магазине, ВСЕ купоны —
//   и купоны заведений (`couponOffers`), и награды каталога (`config/globalRewards`);
// • страница заведения — «Купоны за бонусы» этого заведения, списком.
//
// Плитка/строка — цена; нажатие — лист с подробностями (что это, где гасить,
// сколько осталось, до какого числа) и кнопкой обмена. Покупка — через сервер
// (`CouponStore.buy` / `redeem` / `gift` → `buyCoupon`).

/// Товар витрины: купон заведения или награда каталога. Для гостя это одно и
/// то же — «купон за бонусы», поэтому и показываются они одинаково.
enum StoreItem: Identifiable, Equatable {
    case offer(CouponOffer)
    case reward(Reward)

    var id: String {
        switch self {
        case .offer(let o): return "offer:\(o.id)"
        case .reward(let r): return "reward:\(r.id)"
        }
    }
    var title: String {
        switch self { case .offer(let o): return o.title; case .reward(let r): return r.title }
    }
    var details: String {
        switch self { case .offer(let o): return o.details; case .reward: return "" }
    }
    var emoji: String {
        switch self { case .offer(let o): return o.emoji; case .reward(let r): return r.emoji }
    }
    var imageURL: String {
        switch self { case .offer(let o): return o.imageURL; case .reward: return "" }
    }
    var venueName: String {
        switch self { case .offer(let o): return o.venueName; case .reward(let r): return r.venueName }
    }
    var cost: Int {
        switch self { case .offer(let o): return o.cost; case .reward(let r): return r.cost }
    }
    /// Подарить можно только награду каталога: купон заведения привязан к
    /// покупателю (так решил сервер — `gift_not_allowed`).
    var canGift: Bool {
        if case .reward = self { return true } else { return false }
    }
    var stockText: String {
        switch self {
        case .offer(let o):
            guard let stock = o.stock, let remaining = o.remaining else { return LS("Без ограничения") }
            return LF("%lld из %lld", remaining, stock)
        case .reward: return LS("Без ограничения")
        }
    }
    var expiryText: String {
        switch self {
        case .offer(let o):
            guard let date = o.expiresAt else { return LS("Бессрочно") }
            return LF("до %@", date.formatted(.dateTime.day().month(.wide)))
        case .reward: return LS("Бессрочно")
        }
    }
    /// «осталось 7» — только когда остаток ограничен.
    var remainingShort: String? {
        if case .offer(let o) = self, let remaining = o.remaining { return LF("осталось %lld", remaining) }
        return nil
    }
}

/// Витрина с покупкой. Всё состояние покупки — здесь, чтобы магазин во
/// вкладке «Бонусы» и витрина на странице заведения вели себя одинаково.
struct CouponStoreView: View {
    enum Layout { case grid, list, row }

    let items: [StoreItem]
    var layout: Layout = .list
    /// Название заведения на карточке — в общем магазине; на странице
    /// заведения оно и так в заголовке экрана.
    var showsVenue = false
    /// Перечитать витрину после покупки: остаток изменился или купон разобрали.
    var reload: () async -> Void = {}

    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: AppStore
    @State private var detail: StoreItem?
    @State private var pending: StoreItem?
    @State private var pendingGift: StoreItem?
    @State private var justBought: Coupon?
    @State private var giftShare: ShareURL?
    @State private var showGuestAlert = false
    @State private var purchaseError: String?
    /// Пока сервер отвечает — кнопка не жмётся второй раз.
    @State private var busy = false

    var body: some View {
        Group {
            switch layout {
            case .grid:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(items) { item in
                        Button { detail = item } label: { tile(item) }
                            .buttonStyle(.sanPress(0.97))
                    }
                }
            case .row:
                // Лента во всю ширину: следующая карточка выглядывает — видно,
                // что купонов больше, чем помещается.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            Button { detail = item } label: { tile(item).frame(width: 164) }
                                .buttonStyle(.sanPress(0.97))
                        }
                    }
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -SanMetrics.screenPadding)
            case .list:
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        Button { detail = item } label: { row(item) }
                            .buttonStyle(.sanPress(0.98))
                    }
                }
            }
        }
        .sheet(item: $detail) { item in
            StoreItemDetailSheet(item: item, canBuy: canBuy(item), buttonTitle: buttonTitle(item),
                                 onBuy: { detail = nil; request(item) },
                                 onGift: item.canGift ? { detail = nil; requestGift(item) } : nil)
                .presentationDetents([.medium, .large])
        }
        .guestAlert(isPresented: $showGuestAlert, message: GuestGate.bonuses)
        .alert("Обменять бонусы?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending) { item in
            Button("Обменять за \(item.cost)", role: .destructive) { buy(item) }
            Button("Отмена", role: .cancel) {}
        } message: { item in
            Text(item.venueName.isEmpty
                 ? "«\(item.title)» за \(item.cost) бонусов. Купон нельзя вернуть после обмена."
                 : "«\(item.title)» в «\(item.venueName)» за \(item.cost) бонусов. Купон нельзя вернуть после обмена.")
        }
        .alert("Подарить купон?", isPresented: Binding(
            get: { pendingGift != nil }, set: { if !$0 { pendingGift = nil } }),
            presenting: pendingGift) { item in
            Button("Подарить за \(item.cost)", role: .destructive) { gift(item) }
            Button("Отмена", role: .cancel) {}
        } message: { item in
            Text("Спишется \(item.cost) бонусов. Отправьте ссылку другу — он заберёт «\(item.title)».")
        }
        .alert("Купон получен 🎉", isPresented: Binding(
            get: { justBought != nil }, set: { if !$0 { justBought = nil } })) {
            Button("Отлично") {}
        } message: {
            Text(justBought?.venueName.isEmpty == false
                 ? "Найдите его в «Мои купоны» и покажите сотруднику «\(justBought?.venueName ?? "")»."
                 : "Найдите его в «Мои купоны» и покажите сотруднику заведения.")
        }
        .sheet(item: $giftShare) { GiftShareSheet(url: $0.url, title: $0.title) }
        .alert("Не получилось", isPresented: Binding(
            get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })) {
            Button("Понятно") {}
        } message: {
            Text(purchaseError ?? "")
        }
    }

    // MARK: Покупка

    private func canBuy(_ item: StoreItem) -> Bool {
        ReleaseFlags.couponShopPurchase && bonus.balance >= item.cost && !busy
    }

    private func buttonTitle(_ item: StoreItem) -> LocalizedStringKey {
        if !ReleaseFlags.couponShopPurchase { return "Скоро" }
        return bonus.balance >= item.cost ? "Обменять" : "Не хватает"
    }

    private func request(_ item: StoreItem) {
        if session.isGuest { showGuestAlert = true } else { pending = item }
    }

    private func requestGift(_ item: StoreItem) {
        if session.isGuest { showGuestAlert = true } else { pendingGift = item }
    }

    private func buy(_ item: StoreItem) {
        busy = true
        Task {
            let result: CouponStore.PurchaseResult
            switch item {
            case .offer(let o): result = await coupons.buy(o, bonus: bonus)
            case .reward(let r): result = await coupons.redeem(r, bonus: bonus)
            }
            busy = false
            switch result {
            case .coupon(let c):
                SanHaptics.save()
                justBought = c
            case .failed(let code):
                purchaseError = BonusPurchaseErrorText.message(code)
            case .gift: break
            }
            await reload()
        }
    }

    private func gift(_ item: StoreItem) {
        guard case .reward(let r) = item else { return }
        busy = true
        Task {
            // Серверный кошелёк — подарок покупает сервер; без него (мок-режим)
            // — прежний путь через AppStore.
            let result = await coupons.gift(r, fromName: store.currentUserName, bonus: bonus)
            busy = false
            switch result {
            case .gift(let code):
                giftShare = ShareURL(url: DeepLinks.giftURL(code), title: r.title)
            case .failed("local"):
                if let url = store.createGift(r, bonus: bonus) { giftShare = ShareURL(url: url, title: r.title) }
            case .failed(let code):
                purchaseError = BonusPurchaseErrorText.message(code)
            case .coupon: break
            }
        }
    }

    // MARK: Плитка (магазин)

    /// Карточка товара: картинка, название, заведение, ценник. Ценник — акцентом,
    /// если бонусов хватает, иначе приглушён: видно, что можно взять уже сейчас.
    private func tile(_ item: StoreItem) -> some View {
        let affordable = bonus.balance >= item.cost
        return VStack(alignment: .leading, spacing: 0) {
            StoreItemImage(item: item)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.25, contentMode: .fit)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if let left = item.remainingShort {
                        Text(left)
                            .font(.golos(10.5, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(7)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.title)
                    .font(.golos(14, .bold)).tracking(-0.2).foregroundStyle(Color.sanInk)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if showsVenue {
                    Text(verbatim: item.venueName.isEmpty ? " " : item.venueName)
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.circle.fill").font(.system(size: 13, weight: .semibold))
                    Text("\(item.cost)").font(.golos(14, .heavy)).monospacedDigit()
                }
                .foregroundStyle(affordable ? Color.white : Color.sanInkSoft)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(affordable ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                       : AnyShapeStyle(Color.sanSurfaceMuted), in: Capsule())
                .padding(.top, 4)
            }
            .padding(.horizontal, 11).padding(.top, 10).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.sanSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Строка (страница заведения)

    private func row(_ item: StoreItem) -> some View {
        let enabled = canBuy(item)
        return HStack(spacing: 14) {
            StoreItemImage(item: item)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.title)
                    .font(.golos(14.5, .bold)).tracking(-0.2).foregroundStyle(Color.sanInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(([LF("%lld бонусов", item.cost)] + [item.remainingShort].compactMap { $0 })
                        .joined(separator: " · "))
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { request(item) } label: {
                Text(buttonTitle(item))
                    .font(.golos(13, .bold))
                    .foregroundStyle(enabled ? Color.white : Color(hex: 0x9A9188))
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(enabled ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                        : AnyShapeStyle(Color.sanSurfaceMuted),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.sanPress(0.95))
            // Гость жмёт — и видит «войдите»; вошедшему без бонусов кнопка
            // просто неактивна.
            .disabled(!session.isGuest && !enabled)
        }
        .padding(15)
        .contentShape(Rectangle())
        .sanCard(padding: 0, radius: SanRadius.card)
    }
}

/// Картинка товара: фото купона, если заведение его загрузило, иначе эмодзи
/// на тёплой плашке.
struct StoreItemImage: View {
    let item: StoreItem

    var body: some View {
        if !item.imageURL.isEmpty {
            CoverImage(urlString: item.imageURL, gradient: [.sanAccent, .orange],
                       emoji: item.emoji, emojiSize: 40)
        } else {
            ZStack {
                LinearGradient(colors: [Color.sanAccent.opacity(0.16), Color.orange.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(item.emoji.isEmpty ? "🎁" : item.emoji)
                    .font(.system(size: 40))
                    .minimumScaleFactor(0.4)
            }
        }
    }
}

// MARK: - Подробности

/// Лист «что это за купон»: всё, что нужно решить до обмена, — где гасить,
/// сколько осталось, до какого числа, как воспользоваться.
struct StoreItemDetailSheet: View {
    let item: StoreItem
    let canBuy: Bool
    let buttonTitle: LocalizedStringKey
    let onBuy: () -> Void
    /// Есть — под кнопкой обмена «Подарить другу».
    var onGift: (() -> Void)? = nil
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StoreItemImage(item: item)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: item.title)
                            .font(.golos(22, .heavy)).tracking(-0.5)
                            .foregroundStyle(Color.sanInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.venueName.isEmpty {
                            Label { Text(verbatim: item.venueName) } icon: { Image(systemName: "storefront") }
                                .font(.golos(13.5, .semibold)).foregroundStyle(Color.sanInkSoft)
                        }
                    }

                    if !item.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: item.details)
                            .font(.golos(14.5)).foregroundStyle(Color.sanInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        infoRow("star.circle.fill", "Цена", LF("%lld бонусов", item.cost))
                        SanHairline(leading: 44)
                        infoRow("shippingbox.fill", "Осталось", item.stockText)
                        SanHairline(leading: 44)
                        infoRow("calendar", "Действует", item.expiryText)
                        if !session.isGuest {
                            SanHairline(leading: 44)
                            infoRow("wallet.bifold.fill", "У вас", LF("%lld бонусов", bonus.balance))
                        }
                    }
                    .sanCard(padding: 0, radius: SanRadius.card)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sanAccentText)
                        Text("После обмена купон появится в «Мои купоны». Покажите его сотруднику — он отсканирует код, и купон погасится.")
                            .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(SanMetrics.screenPadding)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: onBuy) {
                        Text(canBuy ? LocalizedStringKey("Обменять за \(item.cost) бонусов") : buttonTitle)
                            .font(.golos(16, .bold))
                            .foregroundStyle(canBuy || session.isGuest ? Color.white : Color(hex: 0x9A9188))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(canBuy || session.isGuest ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                                                  : AnyShapeStyle(Color.sanSurfaceMuted),
                                        in: RoundedRectangle(cornerRadius: SanRadius.button, style: .continuous))
                    }
                    .buttonStyle(.sanPress(0.97))
                    .disabled(!session.isGuest && !canBuy)
                    if let onGift {
                        Button(action: onGift) {
                            Label("Подарить другу", systemImage: "gift")
                                .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanAccentText)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.isGuest && !canBuy)
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.vertical, 12)
                .background(Color.sanCanvas)
            }
            .sanScreenBackground()
            .navigationTitle("Купон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private func infoRow(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sanAccentText)
                .frame(width: 20)
            Text(label).font(.golos(14)).foregroundStyle(Color.sanInkSoft)
            Spacer(minLength: 8)
            Text(verbatim: value).font(.golos(14, .semibold)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Витрины

/// «Купоны за бонусы» на странице заведения — купоны этого заведения.
struct VenueCouponShop: View {
    let venue: Venue
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var session: SessionStore

    private var items: [StoreItem] { coupons.offers(venueID: venue.id).map(StoreItem.offer) }

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Купоны за бонусы")
                            .font(.golos(18, .heavy)).tracking(-0.4)
                            .foregroundStyle(Color.sanInk)
                        Spacer(minLength: 8)
                        // Баланс рядом с ценами — иначе «хватит ли мне» считать в уме.
                        if !session.isGuest {
                            Label("\(bonus.balance)", systemImage: "star.circle.fill")
                                .font(.golos(13, .bold)).monospacedDigit()
                                .foregroundStyle(Color.sanAccentText)
                        }
                    }
                    CouponStoreView(items: items) { await coupons.loadOffers(venueID: venue.id) }
                }
                // Отступ — только когда магазин есть: пустой не должен
                // оставлять дыру на странице заведения.
                .padding(.top, 20)
            }
        }
        .task(id: venue.id) { await coupons.loadOffers(venueID: venue.id) }
    }
}

extension CouponStore {
    /// Весь магазин: купоны заведений и награды каталога, от дешёвого к дорогому.
    var storeItems: [StoreItem] {
        (shopOffers.map(StoreItem.offer) + rewards.map(StoreItem.reward))
            .sorted { ($0.cost, $0.title) < ($1.cost, $1.title) }
    }
}

/// «Магазин купонов» во вкладке «Бонусы»: ВСЕ купоны горизонтальной лентой,
/// «Все · N» — тот же магазин сеткой на отдельном экране. Пустой магазин не
/// прячется: гость должен знать, что бонусы здесь тратятся.
struct BonusStoreSection: View {
    @EnvironmentObject private var coupons: CouponStore

    private var items: [StoreItem] { coupons.storeItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // «Мои купоны» — на карте баланса выше; второй ссылки здесь не нужно.
            HStack(alignment: .firstTextBaseline) {
                Text("Магазин купонов")
                    .font(.golos(20, .heavy)).tracking(-0.5)
                    .foregroundStyle(Color.sanInk)
                Spacer(minLength: 8)
                if !items.isEmpty {
                    NavigationLink { CouponStoreScreen() } label: {
                        Text("Все · \(items.count)")
                            .font(.golos(13, .bold))
                            .foregroundStyle(Color.sanAccentText)
                    }
                    .buttonStyle(.sanPress(0.94))
                }
            }
            if items.isEmpty {
                Text("Здесь появятся купоны, которые заведения продают за бонусы: кофе, десерт, скидка. Копите бонусы в играх — обменять будет на что.")
                    .font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            } else {
                CouponStoreView(items: items, layout: .row, showsVenue: true) {
                    await coupons.loadShopOffers()
                }
            }
        }
        .task {
            await coupons.loadShopOffers()
            await coupons.loadRewards()
        }
    }
}

/// «Все» купоны магазина — сеткой, на своём экране.
struct CouponStoreScreen: View {
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var bonus: BonusEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Баланс рядом с ценами — «хватит ли мне» видно сразу.
                Label("У вас \(bonus.balance) бонусов", systemImage: "star.circle.fill")
                    .font(.golos(14, .bold)).foregroundStyle(Color.sanAccentText)
                CouponStoreView(items: coupons.storeItems, layout: .grid, showsVenue: true) {
                    await coupons.loadShopOffers()
                }
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 8).padding(.bottom, 28)
        }
        .sanScreenBackground()
        .navigationTitle("Магазин купонов")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await coupons.loadShopOffers()
            await coupons.loadRewards()
        }
    }
}

// MARK: - Отказы покупки

/// Коды сервера (`buyCoupon`) — человеческим языком. Общие для всех витрин.
enum BonusPurchaseErrorText {
    static func message(_ code: String) -> String {
        switch code {
        case "insufficient": return LS("Не хватает бонусов. Играйте в «Бонусах», чтобы накопить.")
        case "sold_out": return LS("Эти купоны уже разобрали.")
        case "unavailable", "not_found": return LS("Этот купон сейчас недоступен.")
        case "network": return LS("Нет связи. Попробуйте ещё раз — бонусы дважды не спишутся.")
        case "no_wallet": return LS("Кошелёк ещё настраивается. Попробуйте через минуту.")
        case "anonymous_not_allowed": return LS("Войдите в аккаунт, чтобы обменивать бонусы.")
        default: return LS("Не удалось обменять бонусы. Попробуйте позже.")
        }
    }
}
