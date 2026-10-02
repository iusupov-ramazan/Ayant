import SwiftUI

/// Публичные ссылки приложения — одно место, чтобы адрес не расходился между
/// экранами (тот же URL стоит в подписи под кнопками входа в `AuthView`).
enum AyantLinks {
    static let privacyPolicy = URL(string: "https://ayant.kg/privacy.html")!
    /// Условия использования (EULA): нулевая терпимость к недопустимому
    /// контенту, правила бонусов и купонов. Хостинг — `web/terms.html`.
    static let terms = URL(string: "https://ayant.kg/terms.html")!
}

// MARK: - О приложении

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ayant")
                    .font(.largeTitle.weight(.heavy)).foregroundStyle(Color.sanAccent)

                Text("Ayant — это единая лента событий вашего города и платформа для получения скидок. Мы убрали весь информационный шум, оставив только то, что действительно важно для пользователя.")

                group("Что вы найдёте внутри") {
                    Text("Вся ключевая информация от заведений города собрана по системе **САН**:")
                    bullet("С — Скидки:", "актуальные снижения цен.")
                    bullet("А — Акции:", "специальные и ограниченные предложения.")
                    bullet("Н — Новинки:", "свежие поступления, новые меню и услуги.")
                    bullet("Важные объявления:", "изменения в графике работы и апдейты.")
                    Text("Также в профиле каждого заведения доступна вся справочная информация: точный адрес, контакты и ссылки на соцсети.")
                }

                group("Как копить и тратить бонусы") {
                    Text("В приложении есть внутренняя система бонусов, которые можно собирать без лишних усилий:")
                    bullet("В мини-играх:", "играйте прямо в приложении и получайте за это бонусы.")
                    // Рефералка скрыта флагом — не обещаем того, чего нет в сборке.
                    if ReleaseFlags.referrals {
                        bullet("За приглашение друзей:", "делитесь реферальной ссылкой и копите бонусы вместе.")
                    }
                    Text("**На что их потратить?** Бонусы обмениваются на купоны заведений-партнёров — кофе, десерт, скидку. Купон с QR-кодом появится в «Мои купоны»: покажите его сотруднику, он отсканирует код, и купон погасится.")
                }

                Text("Здесь нет спама и лишних кнопок. Только САН, заведения и ваша выгода. Всё самое нужное — в одном приложении. Пользуйтесь!")
                    .font(.subheadline).foregroundStyle(.secondary)

                Text("Бонусы не имеют денежной стоимости и не обмениваются на деньги. Apple не является спонсором игр и не участвует в программе бонусов.")
                    .font(.footnote).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Link("Политика конфиденциальности", destination: AyantLinks.privacyPolicy)
                    Link("Условия использования", destination: AyantLinks.terms)
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 4)
            }
            .padding(16)
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func bullet(_ bold: LocalizedStringKey, _ rest: LocalizedStringKey) -> some View {
        (Text("• ").bold() + Text(bold).bold() + Text(verbatim: " ") + Text(rest))
            .font(.subheadline)
    }
}

// MARK: - FAQ

struct FAQView: View {
    /// Вопрос про рефералку показываем, только когда она включена в сборке.
    private var items: [(String, String)] {
        ReleaseFlags.referrals ? allItems : allItems.filter { $0.0 != Self.referralQuestion }
    }

    private static let referralQuestion = "Как работает приглашение друзей (рефералка)?"

    private let allItems: [(String, String)] = [
        ("Что такое САН?",
         "Это основа нашего приложения. САН — это лента, где заведения публикуют только три типа новостей: Скидки, Акции и Новинки. Никакого спама, только самое главное."),
        ("Зачем нужны игры в приложении?",
         "Это простой способ заработать бонусы. Вы играете в короткие мини-игры прямо внутри приложения, а мы начисляем за это бонусы на ваш баланс."),
        ("Чем бонусы отличаются от баллов?",
         "Бонусы — общий кошелёк приложения: их приносят игры и время в Ayant, а тратятся они на купоны. Баллы САН у каждого заведения свои: их начисляет само заведение за покупки, и потратить их можно только там же — на его награды."),
        ("Как получить баллы или штамп в заведении?",
         "Покажите на кассе «Мой QR» — центральная кнопка внизу экрана. Код один для всех заведений: где-то за визит начислятся баллы, где-то — штамп на карту. Заполненная карта штампов превращается в купон на награду."),
        (Self.referralQuestion,
         "В своём профиле скопируйте уникальную ссылку и отправьте её другу. Как только он зарегистрируется, и вы, и ваш друг получите приветственные бонусы."),
        ("На что я могу потратить накопленные бонусы?",
         "В «Бонусах» есть магазин купонов: заведения-партнёры продают за бонусы кофе, десерт, скидку. Купон — это товар: обменяли бонусы, и он ваш, в «Мои купоны»."),
        ("Как воспользоваться купоном в заведении?",
         "Откройте купон в «Мои купоны» и покажите его QR-код сотруднику заведения — он отсканирует код, и купон погасится. Купон одноразовый."),
        ("Сколько действует купон?",
         "Срок указан на купоне. После него купон уже не погасить — он переходит в «Неактивные», и бонусы за него не возвращаются. Используйте купон до этой даты."),
        ("Почему у Diamond лимит в день?",
         "Партия в Diamond бесконечная, поэтому бонусы за неё начисляются только до дневного лимита — сколько осталось на сегодня, видно в самой игре. Играть можно и дальше, бонусы снова начнут копиться завтра."),
        ("Сколько бонусов можно заработать за день?",
         "У бонусов есть общий дневной лимит — он защищает магазин купонов от накруток. Обычной игрой до него дойти трудно; если лимит достигнут, приложение покажет это, а бонусы снова начнут копиться завтра."),
        ("Что значит «отправляются»?",
         "Бонусы хранит сервер. Если вы играли без интернета, заработанное видно как «+N отправляются»: оно уже ваше, но потратить его можно, когда бонусы дойдут до сервера. Включите интернет — отправка повторится сама, или нажмите на надпись."),
        ("Приложение бесплатное?",
         "Да, приложение полностью бесплатное для пользователей. Здесь нет скрытых подписок или платных функций."),
        ("Что делать, если заведение отказывается принимать купон или информация в САН не совпадает с реальностью?",
         "Мы следим за актуальностью данных, но если вы столкнулись с такой проблемой — напишите нам в раздел «Поддержка», указав название заведения. Мы быстро во всём разберёмся."),
    ]

    var body: some View {
        List {
            ForEach(items, id: \.0) { item in
                DisclosureGroup {
                    // LocalizedStringKey(String) — иначе Text(String) не проходит через
                    // каталог локализации и текст остаётся на языке источника.
                    Text(LocalizedStringKey(item.1)).font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } label: {
                    // Нельзя интерполировать LocalizedStringKey в строковый литерал —
                    // тогда SwiftUI печатает «LocalizedStringKey(...)». Склеиваем через Text +.
                    (Text(verbatim: "❓ ") + Text(LocalizedStringKey(item.0)))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .navigationTitle("Вопросы и ответы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Поддержка

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    private let telegramApp = URL(string: "tg://resolve?domain=bonus_kg_bot")!
    private let telegramWeb = URL(string: "https://t.me/bonus_kg_bot")!
    private let instagram = URL(string: "https://www.instagram.com/ayant_kg")!
    private let whatsapp = URL(string: "https://wa.me/996707266556")!
    private let email = URL(string: "mailto:ostepp1@gmail.com")!

    var body: some View {
        List {
            Section {
                Text("Не нашли ответ в FAQ? Напишите нам — поможем быстро.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Связаться с нами") {
                // Сначала пробуем открыть приложение Telegram (tg://), затем веб как фолбэк.
                Button {
                    openURL(telegramApp) { accepted in
                        if !accepted { openURL(telegramWeb) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        assetIcon("telegram")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Telegram-бот").foregroundStyle(.primary)
                            Text("ИИ-помощник — отвечает 24/7")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Link(destination: instagram) {
                    Label { Text("Instagram") } icon: { assetIcon("instagram") }
                }
                Link(destination: whatsapp) {
                    Label { Text("WhatsApp") } icon: { assetIcon("whatsapp") }
                }
                Link(destination: email) { Label("Email", systemImage: "envelope.fill") }
            }
            Section("Документы") {
                Link(destination: AyantLinks.privacyPolicy) {
                    Label("Политика конфиденциальности", systemImage: "hand.raised.fill")
                }
                Link(destination: AyantLinks.terms) {
                    Label("Условия использования", systemImage: "doc.text.fill")
                }
            }
        }
        .navigationTitle("Поддержка")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Круглый логотип соцсети из ассетов.
    /// `scaledToFit` — картинка вписывается целиком, без растяжения по осям.
    private func assetIcon(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
            .frame(width: 26, height: 26)
            .clipShape(Circle())
    }
}
