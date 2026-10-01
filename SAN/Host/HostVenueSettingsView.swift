import SwiftUI
import AyantDomain
import AyantFeatures

// MARK: - Данные заведения
//
// Всё, что относится к самому заведению и меняется редко, — на отдельной
// странице, а не на первой вкладке. Первая вкладка — для ежедневной работы
// (акции, меню, купоны); сюда ведёт карточка заведения с подписью
// «Данные заведения».
//
// Страница устроена как «Настройки» iOS: строка = одна часть данных, справа —
// текущее значение. Хозяин видит, что заполнено, не открывая формы, а нажатие
// открывает короткую форму только этой части (`HostVenueFormView(part:)`).
// Сохранение у всех частей общее — `HostForms.VenueFields` собирается из всех
// полей, поэтому правка часов не затирает адреса и наоборот.

/// Маршрут к странице «Данные заведения».
struct HostVenueSettingsTarget: Hashable { let venueID: String }

struct HostVenueSettingsView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @State private var editing: HostVenueFormPart?
    @State private var showDeleteConfirm = false

    private var dto: HostVenueDTO? { host.state.venue(id: venueID) }

    var body: some View {
        ScrollView {
            if let v = dto {
                VStack(alignment: .leading, spacing: 22) {
                    summary(v)
                    visibilityGroup(v)
                    detailsGroup(v)
                    if ReleaseFlags.promote { promoteGroup(v) }
                    deleteButton
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8).padding(.bottom, 32)
            }
        }
        .sanScreenBackground()
        .navigationTitle("Данные заведения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { part in
            if let v = dto { HostVenueFormView(existing: v, part: part) }
        }
        .alert("Удалить заведение?", isPresented: $showDeleteConfirm) {
            // После удаления вкладка сама сбросит стек (`HostVenuesView`
            // следит за текущим заведением) и покажет следующее.
            Button("Удалить", role: .destructive) { host.send(.deleteVenue(id: venueID)) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«\(dto?.name ?? "")» и все его предложения будут удалены без возможности восстановления.")
        }
    }

    // MARK: Шапка

    private func summary(_ v: HostVenueDTO) -> some View {
        HStack(spacing: 14) {
            VenuePhoto(urlString: v.imageURL.isEmpty ? nil : v.imageURL,
                       gradient: v.asVenue.gradientColors)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(v.name)
                    .font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                    .lineLimit(2)
                Text(LS(v.category.rawValue))
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 8)
            HostModerationChip(status: v.moderation)
        }
        .padding(.top, 8)
    }

    // MARK: Видимость

    /// Модерация и «Показывать гостям» — вместе: оба отвечают на вопрос
    /// «увидит ли гость заведение сейчас».
    private func visibilityGroup(_ v: HostVenueDTO) -> some View {
        let state = HostVenueVisibility(v)
        return VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Видимость")
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { !v.isPaused },
                    set: { _ in host.send(.togglePause(venueID: v.id)) }
                )) {
                    HStack(spacing: 12) {
                        SanIconTile(systemName: state.icon, tint: state.color, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Показывать гостям")
                                .font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                            Text(state.text)
                                .font(.golos(12.5)).foregroundStyle(state.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(Color.sanOpen)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .sanGroupCard()
            Text("Выключите на ремонт или отпуск — данные, акции и меню сохранятся.")
                .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                .padding(.horizontal, 4)
        }
    }

    // MARK: О заведении

    private func detailsGroup(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("О заведении")
            VStack(spacing: 0) {
                ForEach(Array(HostVenueFormPart.allCases.enumerated()), id: \.element) { index, part in
                    if index > 0 { SanHairline(leading: 60) }
                    Button { editing = part } label: {
                        settingsRow(icon: part.icon, title: part.title, value: value(part, v),
                                    missing: isMissing(part, v))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sanGroupCard()
        }
    }

    /// Текущее значение части — справа в строке, чтобы было видно, что
    /// заполнено, не открывая формы.
    private func value(_ part: HostVenueFormPart, _ v: HostVenueDTO) -> String {
        switch part {
        case .basics:
            return [LS(v.category.rawValue), v.district].filter { !$0.isEmpty }.joined(separator: " · ")
        case .addresses:
            let places = v.locations.filter { !$0.address.isEmpty }
            if places.isEmpty { return LS("Не указан") }
            if places.count == 1 { return places[0].address }
            return "\(places.count) \(Plural.ru(places.count, "адрес", "адреса", "адресов"))"
        case .hours:
            // Часы сегодняшнего дня: «Сегодня …» не помещалось в строку.
            return v.asVenue.todayHours.label
        case .contacts:
            let parts = [v.phone,
                         v.whatsapp.isEmpty ? "" : "WhatsApp",
                         v.instagram.isEmpty ? "" : "Instagram",
                         v.telegram.isEmpty ? "" : "Telegram"].filter { !$0.isEmpty }
            return parts.isEmpty ? LS("Не указаны") : parts.joined(separator: " · ")
        case .priceList:
            return v.pdfMenuURL.isEmpty ? LS("Не загружен") : LS("Загружен")
        }
    }

    /// Пустое, что гостю важно, — подсвечиваем: без адреса и телефона
    /// заведение не найти и не набрать.
    private func isMissing(_ part: HostVenueFormPart, _ v: HostVenueDTO) -> Bool {
        switch part {
        case .addresses: return v.locations.allSatisfy { $0.address.isEmpty }
        case .contacts: return v.phone.isEmpty && v.whatsapp.isEmpty && v.instagram.isEmpty && v.telegram.isEmpty
        default: return false
        }
    }

    // MARK: Продвижение

    private func promoteGroup(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Продвижение")
            VStack(spacing: 0) {
                NavigationLink(value: HostPromoteTarget(venueID: v.id)) {
                    settingsRow(icon: "megaphone.fill", title: "Продвигать заведение", value: "")
                }
                .buttonStyle(.plain)
                SanHairline(leading: 60)
                NavigationLink(value: HostQuickAction.promote) {
                    settingsRow(icon: "list.bullet.rectangle", title: "Все кампании", value: "")
                }
                .buttonStyle(.plain)
            }
            .sanGroupCard()
        }
    }

    // MARK: Удаление

    /// В самом низу, отдельно и красным — как в «Настройках» iOS: то, что
    /// нельзя отменить, не стоит рядом с ежедневным.
    private var deleteButton: some View {
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            Text("Удалить заведение")
                .font(.golos(15, .semibold)).foregroundStyle(.red)
                .frame(maxWidth: .infinity).frame(height: 50)
        }
        .buttonStyle(.plain)
        .sanGroupCard()
        .padding(.top, 6)
    }

    // MARK: Строка

    private func settingsRow(icon: String, title: LocalizedStringKey, value: String,
                             missing: Bool = false) -> some View {
        HStack(spacing: 12) {
            SanIconTile(systemName: icon, size: 34)
            Text(title)
                .font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(verbatim: value)
                    .font(.golos(13))
                    .foregroundStyle(missing ? Color(hex: 0xC26A00) : Color.sanInkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Части формы заведения

/// Часть данных заведения, которую правит одна строка «Данных заведения».
/// `nil` в `HostVenueFormView(part:)` — форма целиком (создание заведения).
enum HostVenueFormPart: String, CaseIterable, Identifiable {
    case basics, addresses, hours, contacts, priceList

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .basics: return "Название и фото"
        case .addresses: return "Адреса"
        case .hours: return "Часы работы"
        case .contacts: return "Телефон и соцсети"
        case .priceList: return "Прайс-лист (PDF)"
        }
    }

    var icon: String {
        switch self {
        case .basics: return "storefront.fill"
        case .addresses: return "mappin.and.ellipse"
        case .hours: return "clock.fill"
        case .contacts: return "phone.fill"
        case .priceList: return "doc.richtext.fill"
        }
    }
}

// MARK: - Видно ли заведение гостям

/// Один ответ на «увидит ли гость заведение сейчас» — для строки статуса на
/// карточке, плашки модерации и переключателя в «Данных заведения».
struct HostVenueVisibility {
    let icon: String
    let color: Color
    /// Коротко — для строки под названием.
    let title: LocalizedStringKey
    /// Что это значит и что делать.
    let text: LocalizedStringKey
    /// Плашка над карточкой нужна только когда гость заведение не видит не
    /// по воле хозяина: модерация ещё идёт или отклонила.
    let needsAttention: Bool

    init(_ v: HostVenueDTO) {
        switch v.moderation {
        case .rejected:
            icon = "xmark.octagon.fill"; color = Color(hex: 0xC4262B)
            title = "Отклонено модерацией"
            text = "Исправьте данные заведения и сохраните — отправим на проверку снова."
            needsAttention = true
        case .pending:
            icon = "clock.fill"; color = Color(hex: 0xC26A00)
            title = "На проверке"
            text = "Обычно в течение суток. После одобрения заведение появится в ленте."
            needsAttention = true
        case .approved where v.isPaused:
            icon = "eye.slash.fill"; color = Color(hex: 0xC26A00)
            title = "Скрыто от гостей"
            text = "Заведения и его акций нет в ленте и поиске."
            needsAttention = false
        case .approved:
            icon = "eye.fill"; color = Color(hex: 0x1F7D3A)
            title = "Видно гостям"
            text = "Сейчас гости видят заведение в ленте."
            needsAttention = false
        }
    }
}
