import Photos
import SwiftUI

struct DeleteConfirmView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSystemConfirm = false
    @State private var selectedAsset: PHAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        let assets = viewModel.pendingAssets()

        NavigationView {
            VStack(spacing: 16) {
                Text("即将删除 \(assets.count) 张照片")
                    .font(.headline)

                if assets.isEmpty {
                    Text("暂无待删除照片")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                GeometryReader { geo in
                                    PhotoAssetThumbnailView(
                                        asset: asset,
                                        size: CGSize(width: geo.size.width * 2, height: geo.size.width * 2)
                                    )
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedAsset = asset
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                if viewModel.isDeleting {
                    ProgressView("正在删除...")
                        .padding(.bottom, 8)
                }

                Button(role: .destructive) {
                    showSystemConfirm = true
                } label: {
                    Text("确认删除")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(assets.isEmpty || viewModel.isDeleting)

                Button("取消返回") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding()
            .navigationTitle("删除确认")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("确认从系统相册中删除这 \(assets.count) 张照片？", isPresented: $showSystemConfirm) {
            Button("删除", role: .destructive) {
                viewModel.confirmDeletion()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后可在系统「最近删除」中找回。")
        }
        .fullScreenCover(item: $selectedAsset) { asset in
            PhotoPreviewView(asset: asset) {
                selectedAsset = nil
            }
        }
    }
}

// MARK: - PHAsset Identifiable 扩展
extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

// MARK: - 全屏预览视图
struct PhotoPreviewView: View {
    let asset: PHAsset
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 1.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                PhotoAssetImageView(asset: asset, targetSize: proxy.size)
                    .offset(y: dragOffset.height)
                    .scaleEffect(scale)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    dragOffset = value.translation
                                    let progress = min(value.translation.height / 300, 1.0)
                                    backgroundOpacity = 1.0 - progress * 0.5
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 100 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = CGSize(width: 0, height: proxy.size.height)
                                        backgroundOpacity = 0
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onDismiss()
                                    }
                                } else {
                                    withAnimation(.spring()) {
                                        dragOffset = .zero
                                        backgroundOpacity = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture {
                        onDismiss()
                    }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }
        }
    }

    private var scale: CGFloat {
        let progress = min(abs(dragOffset.height) / 300, 1.0)
        return 1.0 - progress * 0.2
    }
}
