import SwiftUI
import AuthenticationServices

/// Экран входа: Apple (нативно), Google, email (вход/регистрация), гость.
struct AuthView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    enum Mode { case signIn, register }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    logo
                    card
                }
                .padding(20)
                .padding(.top, 40)
            }
        }
        .alert("Ошибка", isPresented: .constant(session.errorMessage != nil)) {
            Button("Ок") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var logo: some View {
        VStack(spacing: 8) {
            Text("Ayant")
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(.white)
            Text("скидки • акции • новинки")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
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
                field("Имя", text: $name, icon: "person")
            }
            field("Почта", text: $email, icon: "envelope", keyboard: .emailAddress)
            secureField("Пароль", text: $password)

            Button(action: submitEmail) {
                primaryLabel(mode == .signIn ? "Войти" : "Создать аккаунт")
            }
            .disabled(session.isWorking)

            divider

            // Нативный Sign in with Apple (с nonce для Firebase)
            SignInWithAppleButton(.continue) { req in
                session.prepareAppleRequest(req)
            } onCompletion: { result in
                session.handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))

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

            Button("Зайти как гость") { session.continueAsGuest() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

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
                       icon: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(placeholder, text: text)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submitEmail() {
        switch mode {
        case .signIn:
            session.signInEmail(email, password)
        case .register:
            session.registerEmail(name: name, email: email, password: password)
        }
    }
}

#Preview {
    AuthView().environmentObject(SessionStore())
}
