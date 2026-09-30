import SwiftUI
import AyantDomain
import AyantFeatures

// MARK: - Магазин купонов заведения

/// «Купоны за бонусы» на странице заведения: что заведение отдаёт за бонусы
/// приложения и сколько это стоит.
///
/// Устроен как каталог наград в «Бонусах» (`BonusHubView.rewardRow`): та же
/// строка с ценой и кнопкой «Обменять», тот же «Обменять бонусы?» перед
/// списанием, тот же «Купон получен» после. Гость уже знает этот магазин —
/// здесь он просто открыт на одном заведении.
///
/// Покупку включает `ReleaseFlags.couponShopPurchase` (см. там, почему она
/// выключена). Без неё магазин всё равно показывается: гость видит, на что
/// копить, а заведение — что его купоны на витрине.
struct VenueCouponShop: View {
    let venue: Venue
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var session: SessionStore
    @State private var pending: CouponOffer?
    @State private var justBought: Coupon?
    @State private var showGuestAlert = false
    @State private var purchaseError: String?
    /// Пока сервер отвечает — кнопка не жмётся второй раз.
    @State private var buying: String?

    private var offers: [CouponOffer] { coupons.offers(venueID: venue.id) }

    var body: some View {
        Group {
            if !offers.isEmpty {
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
                    ForEach(offers) { offerRow($0) }
                    if !ReleaseFlags.couponShopPurchase {
                        Text("Обмен бонусов на купоны заведений скоро заработает. Копите бонусы в играх — цены уже известны.")
                            .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Отступ — только когда магазин есть: пустой не должен
                // оставлять дыру на странице заведения.
                .padding(.top, 20)
            }
        }
        .task(id: venue.id) { await coupons.loadOffers(venueID: venue.id) }
        .guestAlert(isPresented: $showGuestAlert, message: GuestGate.bonuses)
        .alert("Обменять бонусы?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending) { offer in
            Button("Обменять за \(offer.cost)", role: .destructive) {
                buying = offer.id
                Task {
                    let result = await coupons.buy(offer, bonus: bonus)
                    buying = nil
                    switch result {
                    case .coupon(let c):
                        SanHaptics.save()
                        justBought = c
                    case .failed(let code):
                        purchaseError = BonusPurchaseErrorText.message(code)
                    case .gift: break
                    }
                    // Остаток изменился (или купон разобрали) — перечитываем витрину.
                    await coupons.loadOffers(venueID: venue.id)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { offer in
            Text("«\(offer.title)» в «\(venue.name)» за \(offer.cost) бонусов. Купон нельзя вернуть после обмена.")
        }
        .alert("Купон получен 🎉", isPresented: Binding(
            get: { justBought != nil }, set: { if !$0 { justBought = nil } })) {
            Button("Отлично") {}
        } message: {
            Text("Найдите его в «Мои купоны» и покажите сотруднику «\(venue.name)».")
        }
        .alert("Не получилось", isPresented: Binding(
            get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })) {
            Button("Понятно") {}
        } message: {
            Text(purchaseError ?? "")
        }
    }

    private func offerRow(_ offer: CouponOffer) -> some View {
        let affordable = bonus.balance >= offer.cost
        let canBuy = ReleaseFlags.couponShopPurchase && affordable && buying == nil
        return HStack(spacing: 14) {
            Text(offer.emoji).font(.system(size: 24))
                .frame(width: 46, height: 46)
                .background(Color.sanAccent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: offer.title)
                    .font(.golos(14.5, .bold)).tracking(-0.2).foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(offer))
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                if session.isGuest { showGuestAlert = true } else { pending = offer }
            } label: {
                Text(!ReleaseFlags.couponShopPurchase ? "Скоро" : (affordable ? "Обменять" : "Не хватает"))
                    .font(.golos(13, .bold))
                    .foregroundStyle(canBuy ? Color.white : Color(hex: 0x9A9188))
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(canBuy ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                       : AnyShapeStyle(Color.sanSurfaceMuted),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.sanPress(0.95))
            // Гость без аккаунта жмёт — и видит «войдите»; вошедшему без
            // бонусов или до включения покупки кнопка просто неактивна.
            .disabled(!session.isGuest && !canBuy)
        }
        .padding(15)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    /// «120 бонусов · осталось 7» — цена главное, остаток уточняет.
    private func subtitle(_ offer: CouponOffer) -> String {
        var parts = [LF("%lld бонусов", offer.cost)]
        if let remaining = offer.remaining { parts.append(LF("осталось %lld", remaining)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Отказы покупки

/// Коды сервера (`buyCoupon`) — человеческим языком. Общие для магазина
/// купонов заведения и каталога наград в «Бонусах».
enum BonusPurchaseErrorText {
    static func message(_ code: String) -> String {
        switch code {
        case "insufficient": return LS("Не хватает бонусов. Играйте в «Бонусах», чтобы накопить.")
        case "sold_out": return LS("Эти купоны уже разобрали.")
        case "unavailable", "not_found": return LS("Этот купон сейчас недоступен.")
        case "network": return LS("Нет связи. Попробуйте ещё раз — бонусы дважды не спишутся.")
        case "no_wallet": return LS("Кошелёк ещё настраивается. Попробуйте через минуту.")
        default: return LS("Не удалось обменять бонусы. Попробуйте позже.")
        }
    }
}
