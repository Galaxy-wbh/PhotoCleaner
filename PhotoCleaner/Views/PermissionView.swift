import SwiftUI

struct PermissionRequestView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("需要访问你的相册")
                .font(.title2)
                .bold()
            Text("用于展示照片并进行清理。我们不会上传你的照片。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button(action: onRequest) {
                Text("授权访问")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}

struct PermissionDeniedView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("未获得相册权限")
                .font(.title2)
                .bold()
            Text("请在系统设置中开启照片访问权限。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button(action: onOpenSettings) {
                Text("前往设置")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}
