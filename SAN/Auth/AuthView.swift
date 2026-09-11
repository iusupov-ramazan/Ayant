import SwiftUI
import AuthenticationServices
import AyantDomain
import AyantFeatures

/// Экран входа: Apple (нативно), Google, email (вход/регистрация), гость.
///
/// Два режима подачи. `.root` — корень приложения для невошедшего: есть «зайти
/// как гость». `.upgrade` — тот же экран, показанный ПОВЕРХ приложения гостю,
/// который упёрся в закрытую функцию: гостевой кнопки там нет (он уже гость,
/// повторное «продолжить как гость» — тупик), зато есть крестик, чтобы
/// вернуться к просмотру. Экран закрывается сам, как только гость перестал быть
/// гостем.
struct AuthView: View {
    enum Presentation { case root, upgrade }

    var presentation: Presentation = .root

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Mode { case signIn, register }
    enum Field { case name, email, password }

    /// Кнопка «Войти»/«Создать аккаунт» доступна только на валидной форме —
    /// проверки общие с Android (`AuthValidation` в домене).
    private var canSubmit: Bool {
        switch mode {
        case .signIn: return AuthValidation.canSignIn(email: email, password: password)
        case .register: return AuthValidation.canRegister(name: name, email: email, password: password)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                // Тап «мимо карточки» прячет клавиатуру. Жест висит на ФОНЕ, а
                // не на корневом ZStack: `.onTapGesture` на корне перехватывает
                // нажатия кнопок SwiftUI внутри — «Зайти как гость» и «Войти»
                // переставали срабатывать. Тот же урок записан в `SANApp.swift`
                // про ActivityTracker.
                .contentShape(Rectangle())
                .onTapGesture { focused = nil }

            ScrollView {
                VStack(spacing: 22) {
                    logo
                    card
                }
                .padding(20)
                .padding(.top, 40)
            }
            // Клавиатура прячется протяжкой по экрану и тапом по фону:
            // на маленьких экранах она перекрывала кнопку входа, а закрыть её
            // было нечем — на форме нет ни «Готово», ни свободного места.
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topLeading) {
            if presentation == .upgrade { closeButton }
        }
        // Вход состоялся — гость перестал быть гостем: закрываем экран, под ним
        // уже обновлённый корень.
        .onChange(of: session.isGuest) { _, isGuest in
            if presentation == .upgrade && !isGuest { dismiss() }
        }
        .alert("Ошибка", isPresented: .constant(session.errorMessage != nil)) {
            Button("Ок") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.22), in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityLabel("Закрыть")
    }

    private var logo: some View {
        VStack(spacing: 8) {
            Text("Ayant")
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(.white)
            Text(presentation == .upgrade
                 ? "Войдите или создайте аккаунт, чтобы копить баллы"
                 : "скидки • акции • новинки")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Picker("", selection: $mode) {
                Text("Вход").tag(Mode.signIn)
                Text("Регистрация").tag(Mode.register)
            }
            .pickerStyle(.segmented)

            if mode == .register {
                field("Имя", text: $name, icon: "person", field: .name,
                      hint: AuthValidation.nameHint(name))
            }
            field("Почта", text: $email, icon: "envelope", keyboard: .emailAddress,
                  field: .email, hint: AuthValidation.emailHint(email))
            secureField("Пароль", text: $password,
                        hint: mode == .register ? AuthValidation.passwordHint(password) : nil)

            Button(action: submitEmail) {
                primaryLabel(mode == .signIn ? "Войти" : "Создать аккаунт")
            }
            // Пустая форма больше не отправляется: раньше кнопка была активна
            // всегда и пустые поля уходили в Firebase за ошибкой на английском.
            .disabled(session.isWorking || !canSubmit)

            divider

            AppleSignInButton()

            // Google
            Button(action: session.signInGoogle) {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Продолжить с Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
            }

            // «Зайти как гость» — только в корне. Гостю, которого сюда привела
            // закрытая функция, эта кнопка вернула бы его ровно туда, откуда он
            // пришёл: он уже гость.
            if presentation == .root {
                Button("Зайти как гость") { session.continueAsGuest() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            if session.isWorking { ProgressView() }
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(Color(.systemGray4)).frame(height: 1)
            Text("или").font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color(.systemGray4)).frame(height: 1)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       icon: String, keyboard: UIKeyboardType = .default,
                       field: Field, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(field == .name ? .words : .never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: field)
                    .submitLabel(field == .name ? .next : (mode == .signIn ? .go : .next))
            }
            .padding(14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            hintText(hint)
        }
    }

    private func secureField(_ placeholder: String, text: Binding<String>,
                             hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
                SecureField(placeholder, text: text)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { submitEmail() } }
            }
            .padding(14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            hintText(hint)
        }
    }

    /// Подсказка под полем — появляется только когда в поле уже что-то ввели
    /// (`AuthValidation.*Hint` возвращает nil на пустом поле).
    @ViewBuilder private func hintText(_ hint: String?) -> some View {
        if let hint {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(canSubmit && !session.isWorking ? Color.sanAccent : Color.sanAccent.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 12))
    }

    private func submitEmail() {
        focused = nil
        switch mode {
        case .signIn:
            session.signInEmail(email, password)
        case .register:
            session.registerEmail(name: name, email: email, password: password)
        }
    }
}

/// Нативная кнопка Apple ОТДЕЛЬНЫМ типом.
///
/// В общей форме она перерисовывалась на каждое нажатие клавиши: тело
/// `AuthView` зависит от полей ввода, а `SignInWithAppleButton` — обёртка над
/// UIKit-контроллером авторизации. Пересборка вьюхи в момент, когда системная
/// шторка уже открыта, теряет её делегата — со стороны это «кнопка Apple то
/// работает, то нет». Своё тело зависит только от сессии, поэтому набор текста
/// его больше не трогает.
private struct AppleSignInButton: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            session.prepareAppleRequest(request)
        } onCompletion: { result in
            session.handleApple(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Второй тап поверх открытой шторки перезаписывал nonce, и ответ
        // Apple переставал сходиться с запросом.
        .disabled(session.isWorking)
        .opacity(session.isWorking ? 0.6 : 1)
    }
}

#Preview {
    AuthView().environmentObject(AyantStores.session())
}
