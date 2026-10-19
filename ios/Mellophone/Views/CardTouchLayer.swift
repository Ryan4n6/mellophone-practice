import SwiftUI
import UIKit

/// Taps and holds on a card, with where the finger is (#43).
///
/// UIKit and not SwiftUI because a SwiftUI long press reports no location,
/// and a long press sequenced into a drag reports none either until the
/// finger moves: a perfectly still hold on a note opened nothing. A UIKit
/// long press says where it began, and fails on its own if the finger moves
/// first, which leaves the swipe that turns the card to the page view.
struct CardTouchLayer: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onHoldBegan: (CGPoint) -> Void
    let onHoldEnded: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.45
        // No require(toFail:): a tap ends before the hold's 0.45 s, and once
        // the hold has begun the tap cannot also recognise, so a tap sounds
        // at once instead of waiting out the hold.
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.layer = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(layer: self) }

    final class Coordinator: NSObject {
        var layer: CardTouchLayer

        init(layer: CardTouchLayer) { self.layer = layer }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            layer.onTap(recognizer.location(in: recognizer.view))
        }

        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began: layer.onHoldBegan(point)
            case .ended: layer.onHoldEnded(point)
            default: break
            }
        }
    }
}
