import SwiftUI

struct ToastView: View {
    let model: ToastModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.message)
                .foregroundColor(.white)
                .font(.subheadline)
            if let actionTitle = model.actionTitle, let action = model.action {
                Button(actionTitle) {
                    action()
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.75))
        .clipShape(Capsule())
        .shadow(radius: 8)
    }
}
