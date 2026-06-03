import SwiftUI

struct ToastData: Equatable {
    let text: String
    let icon: String
    let tint: Color
}

struct ToastView: View {
    let data: ToastData
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: data.icon)
                .font(.system(size: 15, weight: .bold))
            Text(data.text)
                .font(.subheadline.weight(.bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(data.tint.gradient))
        .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1))
        .shadow(color: data.tint.opacity(0.55), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}
