import SwiftUI

// MARK: - О приложении

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ayant")
                    .font(.largeTitle.weight(.heavy)).foregroundStyle(Color.sanAccent)

                Text("Ayant — это единая лента событий твоего города и платформа для получения скидок. Мы убрали весь информационный шум, оставив только то, что действительно важно для пользователя.")

                group("Что ты найдёшь внутри") {
                    Text("Вся ключевая информация от заведений города собрана по системе **САН**:")
                    bullet("С — Скидки:", "актуальные снижения цен.")
                    bullet("А — Акции:", "специальные и ограниченные предложения.")
                    bullet("Н — Новинки:", "свежие поступления, новые меню и услуги.")
                    bullet("Важные объявления:", "изменения в графике работы и апдейты.")
                    Text("Также в профиле каждого заведения доступна вся справочная информация: точный адрес, контакты и ссылки на соцсети.")
                }

                group("Как копить и тратить бонусы") {
                    Text("В приложении есть внутренняя система бонусов, которые можно собирать без лишних усилий:")
                    bullet("В мини-игры:", "играй прямо в приложении и получай за это бонусы.")
                    bullet("За приглашение друзей:", "делись реферальной ссылкой и копи бонусы вместе.")
                    Text("**На что их потратить?** Накопленные бонусы обмениваются на купоны, которые дают эксклюзивные скидки в заведениях-партнёрах.")
                }

                Text("Здесь нет спама, рекламы и лишних кнопок. Только САН, заведения и твоя выгода. Всё самое нужное — в одном приложении. Пользуйся!")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func bullet(_ bold: String, _ rest: String) -> some View {
        (Text("• ").bold() + Text(bold).bold() + Text(" \(rest)"))
            .font(.subheadline)
    }
}

// MARK: - FAQ

struct FAQView: View {
    private let items: [(String, String)] = [
        ("Что такое САН?",
         "Это основа нашего приложения. САН — это лента, где заведения публикуют только три типа новостей: Скидки, Акции и Новинки. Никакого спама, только самое главное."),
        ("Зачем нужны игры в приложении?",
         "Это простой способ заработать бонусы. Вы играете в короткие мини-игры прямо внутри приложения, а мы начисляем за это бонусные баллы на ваш баланс."),
        ("Как работает приглашение друзей (рефералка)?",
         "В своём профиле скопируйте уникальную ссылку и отправьте её другу. Как только он зарегистрируется, и вы, и ваш друг получите приветственные бонусы."),
        ("На что я могу потратить накопленные бонусы?",
         "Бонусы можно обменять внутри приложения на купоны. Эти купоны дают скидки в заведениях-партнёрах."),
        ("Как воспользоваться купоном в заведении?",
         "Выберите нужный купон, обменяйте на него свои бонусы и покажите экран смартфона с купоном сотруднику заведения (официанту, кассиру, администратору) перед оплатой заказа."),
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
                        telegramIcon
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
        }
        .navigationTitle("Поддержка")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Логотип из ассетов со скруглёнными углами.
    private func assetIcon(_ name: String) -> some View {
        Image(name).resizable().scaledToFill()
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// Иконка Telegram (нет отдельного ассета) — фирменный синий скруглённый квадрат.
    private var telegramIcon: some View {
        Image(systemName: "paperplane.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color(hex: 0x29A9EB),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
