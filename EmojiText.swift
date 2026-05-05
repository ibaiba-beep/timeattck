import SwiftUI
import UIKit

struct EmojiText: UIViewRepresentable {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat = 24) {
        self.text = text
        self.size = size
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.font = UIFont.systemFont(ofSize: size)
        label.text = text
    }
}
