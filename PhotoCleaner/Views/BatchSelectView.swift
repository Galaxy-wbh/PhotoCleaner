import Photos
import SwiftUI

struct BatchSelectView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var dragSelectMode: Bool? = nil  // true = 选中模式, false = 取消选中模式, nil = 未开始
    @State private var dragProcessedIDs: Set<String> = []  // 当前滑动已处理的照片ID
    @State private var isGridReady = false  // 网格是否已定位完成

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
        .fullScreenCover(isPresented: $viewModel.showDeleteSheet) {
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
            ScrollViewReader { scrollProxy in
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
                                    // 先预加载高清图片，再退出批量模式
                                    ImageCache.shared.preloadImage(for: asset, targetSize: geometry.size)
                                    viewModel.exitBatchMode(toAssetID: asset.localIdentifier)
                                }
                            )
                            .id(asset.localIdentifier)
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
                        .onChanged { value in
                            handleDragSelection(at: value.location)
                        }
                        .onEnded { _ in
                            // 滑动结束，重置状态
                            dragSelectMode = nil
                            dragProcessedIDs.removeAll()
                        }
                )
                .opacity(isGridReady ? 1 : 0)
                .onAppear {
                    // 进入批量模式时立即滚动到当前照片位置（无动画）
                    if let entryAssetID = viewModel.entryAssetID {
                        // 使用 DispatchQueue 确保 ScrollView 已经渲染
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(entryAssetID, anchor: .center)
                            // 滚动完成后显示网格
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    isGridReady = true
                                }
                            }
                        }
                    } else {
                        isGridReady = true
                    }
                }
            }
        }
    }

    private func handleDragSelection(at point: CGPoint) {
        for (assetID, frame) in cellFrames {
            if frame.contains(point) {
                // 如果这个照片已经在本次滑动中处理过，跳过
                if dragProcessedIDs.contains(assetID) {
                    break
                }

                // 第一次触碰照片时，根据该照片的当前状态决定滑动模式
                if dragSelectMode == nil {
                    // 如果当前照片已选中，则进入取消选中模式；否则进入选中模式
                    dragSelectMode = !viewModel.isBatchSelected(assetID)
                }

                // 根据滑动模式执行选中或取消选中
                if dragSelectMode == true {
                    viewModel.addToBatchSelection(assetID)
                } else {
                    viewModel.removeFromBatchSelection(assetID)
                }

                // 记录已处理
                dragProcessedIDs.insert(assetID)
                break
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // 待删除计数（可点击进入列表）
            HStack {
                Button {
                    if !viewModel.pendingDeleteIDs.isEmpty {
                        viewModel.showDeleteSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.pendingCountText)
                            .font(.subheadline)
                        if !viewModel.pendingDeleteIDs.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(viewModel.pendingDeleteIDs.isEmpty ? .white.opacity(0.5) : .white.opacity(0.9))
                }
                .disabled(viewModel.pendingDeleteIDs.isEmpty)
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

    private var isLivePhoto: Bool {
        asset.mediaSubtypes.contains(.photoLive)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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

                // Live Photo 标识（左上角）
                if isLivePhoto {
                    VStack {
                        HStack {
                            LivePhotoBadge()
                                .padding(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.width)
                }

                // 勾选圆圈（右上角）
                VStack {
                    HStack {
                        Spacer()
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
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.width)
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

// MARK: - Live Photo 标识组件

struct LivePhotoBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "livephoto")
                .font(.system(size: 10, weight: .semibold))
            Text("LIVE")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }
}

// MARK: - CellFramePreferenceKey

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
