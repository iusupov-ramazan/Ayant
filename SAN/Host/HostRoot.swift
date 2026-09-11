import SwiftUI
import AyantDomain
import AyantFeatures

// MARK: - Корневая навигация хоста (6 вкладок)

// HostRootView переехал в `HostShell.swift` — кремовый таб-бар с FAB сканера.

// MARK: - Онбординг хоста

struct HostOnboardingView: View {
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    var onFinished: () -> Void

    @State private var step = 0
    // Шаг 1
    @State private var businessName = ""
    @State private var category: VenueCategory = .cafe
    @State private var phone = ""
    @State private var email = ""
    @ObservedObject private var catStore = CategoryStore.shared
    // Шаг 2
    @State private var showVenueForm = false

    var body: some View {
        NavigationStack {
            ZStack {
                if step == 0 { basics } else { firstVenue }
            }
            // Фоном, а не слоем стека: `Color.ignoresSafeArea()` внутри ZStack
            // раздувает его до полного экрана и ломает нижние отступы.
            .background(Color.sanCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showVenueForm, onDismiss: finish) {
                HostVenueFormView(existing: nil)
            }
        }
    }

    // Шаг 1 — основное о бизнесе (SCREENS.md H1)
    private var basics: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.sanInk)
                                .frame(width: 40, height: 40)
                                .background(Color.sanSurface, in: Circle())
                        }
                        .buttonStyle(.sanPress(0.90))
                        Spacer()
                    }

                    Image("AppIconMark")
                        .resizable().frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: Color.sanAccent.opacity(0.32), radius: 8, y: 6)
                        // Марка приложения — если ассет не заведён, показываем витрину.
                        .overlay {
                            if UIImage(named: "AppIconMark") == nil {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(LinearGradient.sanAccentGradient)
                                    .overlay(Image(systemName: "storefront.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white))
                            }
                        }

                    SanStepProgress(step: 0)

                    Text("Подключите заведение к Ayant")
                        .sanText(40, .heavy, tracking: -2.2, lineHeight: 0.98)
                        .foregroundStyle(Color.sanInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Расскажите о вашем бизнесе. Оплата и верификация не требуются.")
                        .sanText(14.5, .regular, lineHeight: 1.45)
                        .foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    SanFieldCard {
                        SanFieldRow(label: "Название бизнеса") {
                            SanFieldInput(placeholder: "Например, Sierra Coffee", text: $businessName)
                        }
                        SanHairline(leading: 16)
                        SanFieldRow(label: "Категория") {
                            Menu {
                                ForEach(catStore.categories) { c in
                                    Button(c.rawValue) { category = c }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(category.locKey)
                                        .font(.golos(15.5, .semibold)).foregroundStyle(Color.sanInk)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.sanInkSoft)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        SanHairline(leading: 16)
                        SanFieldRow(label: "Телефон") {
                            SanFieldInput(placeholder: "+996 …", text: $phone, keyboard: .phonePad)
                        }
                        SanHairline(leading: 16)
                        SanFieldRow(label: "Email") {
                            SanFieldInput(placeholder: "you@example.com", text: $email, keyboard: .emailAddress)
                        }
                    }

                    SanNoteCard(text: "После отправки заведение попадёт на модерацию. Обычно проверяем в течение суток.")
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12).padding(.bottom, 24)
                .sanScreenEnter()
            }
            SanStickyFooter {
                Button("Продолжить") {
                    host.send(.createAccount(businessName: businessName, category: category,
                                             phone: phone, email: email))
                    step = 1
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(businessName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(businessName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
            }
        }
    }

    // Шаг 2 — первое заведение
    private var firstVenue: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                SanStepProgress(step: 1)
                SanIconTile(systemName: "storefront.fill", filled: true, size: 64)
                Text("Добавим первое заведение?")
                    .sanText(32, .heavy, tracking: -1.6, lineHeight: 1)
                    .foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Можно добавить сейчас или позже — со вкладки «Заведения».")
                    .sanText(14.5, .regular, lineHeight: 1.45)
                    .foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 24)
            .sanScreenEnter()

            SanStickyFooter {
                Button("Добавить заведение сейчас") { showVenueForm = true }
                    .buttonStyle(SanPrimaryButton())
                Button("Сделаю позже") { finish() }
                    .font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
            }
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}
