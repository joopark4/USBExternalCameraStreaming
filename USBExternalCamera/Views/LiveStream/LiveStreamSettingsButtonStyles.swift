import SwiftUI

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
