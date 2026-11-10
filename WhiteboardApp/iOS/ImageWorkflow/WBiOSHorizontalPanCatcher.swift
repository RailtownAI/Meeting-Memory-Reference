import SwiftUI
import UIKit

/// A transparent layer that reports **horizontal** drags and lets every other drag through to the
/// enclosing `ScrollView`.
///
/// SwiftUI can't express this. A `DragGesture` claims the touch as soon as it passes
/// `minimumDistance`, whatever direction the finger moved — declaring it with `.simultaneousGesture`
/// doesn't change that — so filtering by axis inside `onChanged` suppresses the *swipe* but the
/// scroll is already lost. UIKit arbitrates properly: a recogniser that declines to begin hands the
/// touch back, and the scroll view proceeds as if nothing was there.
///
/// `onChanged`/`onEnded` receive the horizontal translation in points, negative for a leftward drag.
struct WBiOSHorizontalPanCatcher: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Re-point at the newest closures: SwiftUI rebuilds this struct on every render, and the
        // coordinator outlives each one.
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: WBiOSHorizontalPanCatcher

        init(_ parent: WBiOSHorizontalPanCatcher) {
            self.parent = parent
        }

        @objc
        func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .changed:
                parent.onChanged(translation)
            case .ended, .cancelled, .failed:
                parent.onEnded(translation)
            default:
                break
            }
        }

        /// The whole point of dropping to UIKit: decline anything more vertical than horizontal, so
        /// the scroll view keeps the touch instead of it being swallowed by a swipe that then
        /// ignores it.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
