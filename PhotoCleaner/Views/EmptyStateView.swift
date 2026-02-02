import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("已经没有更多照片了")
                .font(.title3)
                .bold()
            Text("可以确认删除或返回系统相册")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
