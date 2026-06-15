import SwiftUI
import UIKit

/// Невидимый трекер активности: ловит касания на уровне окна через
/// UITapGestureRecognizer с `cancelsTouchesInView = false`, поэтому НЕ перехватывает
/// нажатия кнопок SwiftUI (в отличие от .onTapGesture/.simultaneousGesture на корне,
/// которые ломали кнопки в списках — например, в Профиле).
struct ActivityTracker: UIViewRepresentable {
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onInteraction) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false   // сам по себе ничего не ловит
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard !context.coordinator.attached else { return }
        DispatchQueue.main.async {
            guard !context.coordinator.attached, let window = uiView.window else { return }
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap))
            tap.cancelsTouchesInView = false   // ← ключ: касания идут дальше к кнопкам
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = context.coordinator
            window.addGestureRecognizer(tap)
            context.coordinator.attached = true
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onInteraction: () -> Void
        var attached = false

        init(_ onInteraction: @escaping () -> Void) { self.onInteraction = onInteraction }

        @objc func handleTap() { onInteraction() }

        // Распознаём одновременно с любыми другими жестами — ничего не блокируем.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
