import Photos
import SwiftUI

struct BatchSelectView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var cellFrames: [String: CGRect] = [:]
    @GestureState private var isDragging = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部导航栏
                navigationBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                // 照片网格
                if viewModel.hasPhotos {
                    photoGrid
                } else {
                    Spacer()
                    EmptyStateView()
                        .foregroundColor(.white)
                    Spacer()
                }

                // 底部操作栏
                bottomBar
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }

            // Toast
            if let toast = viewModel.toast {
                VStack {
                    Spacer()
                    ToastView(model: toast)
                        .padding(.bottom, 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $viewModel.showDeleteSheet) {
            DeleteConfirmView(viewModel: viewModel)
        }
        .alert(item: $viewModel.alert) { model in
            alert(for: model)
        }
    }

    private var navigationBar: some View {
        HStack {
            Button {
                viewModel.exitBatchMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .foregroundColor(.white)
            }

            Spacer()

            Text(viewModel.batchSelectedCountText)
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Button {
                if viewModel.isAllSelectedForBatch {
                    viewModel.deselectAllForBatch()
                } else {
                    viewModel.selectAllForBatch()
                }
            } label: {
                Text(viewModel.isAllSelectedForBatch ? "取消全选" : "全选")
                    .foregroundColor(.blue)
            }
        }
    }

    private var photoGrid: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.assets, id: \.localIdentifier) { asset in
                        BatchPhotoCell(
                            asset: asset,
                            isSelected: viewModel.isBatchSelected(asset.localIdentifier),
                            onTap: {
                                viewModel.toggleBatchSelection(for: asset.localIdentifier)
                            },
                            onDoubleTap: {
                                viewModel.exitBatchMode(toAssetID: asset.localIdentifier)
                            }
                        )
                        .background(
                            GeometryReader { cellGeometry in
                                Color.clear.preference(
                                    key: CellFramePreferenceKey.self,
                                    value: [asset.localIdentifier: cellGeometry.frame(in: .named("scrollView"))]
                                )
                            }
                        )
                    }
                }
                .padding(2)
            }
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(CellFramePreferenceKey.self) { frames in
                cellFrames = frames
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        handleDragSelection(at: value.location)
                    }
            )
        }
    }

    private func handleDragSelection(at point: CGPoint) {
        for (assetID, frame) in cellFrames {
            if frame.contains(point) {
                viewModel.addToBatchSelection(assetID)
                break
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // 待删除计数
            HStack {
                Text(viewModel.pendingCountText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            // 加入待删除按钮
            Button {
                viewModel.markBatchSelectedForDeletion()
            } label: {
                Text("加入待删除 (\(viewModel.batchSelectedIDs.count))")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(viewModel.batchSelectedIDs.isEmpty)

            // 确认删除按钮
            Button {
                viewModel.showDeleteSheet = true
            } label: {
                Text("确认删除")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.pendingDeleteIDs.isEmpty)
        }
    }

    private func alert(for model: AlertModel) -> Alert {
        switch model.primaryButton {
        case let .default(title, action):
            return Alert(
                title: Text(model.title),
                message: Text(model.message),
                dismissButton: .default(Text(title), action: action)
            )
        }
    }
}

// MARK: - BatchPhotoCell

struct BatchPhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // 缩略图
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                }

                // 选中遮罩
                if isSelected {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                }

                // 勾选圆圈
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(6)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onTapGesture(count: 1) {
                onTap()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let size = CGSize(width: 200, height: 200)
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image {
                thumbnail = image
            }
        }
    }
}

// MARK: - CellFramePreferenceKey

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
