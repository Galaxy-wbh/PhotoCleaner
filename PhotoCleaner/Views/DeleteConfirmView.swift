import Photos
import SwiftUI
import UIKit

struct DeleteConfirmView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSystemConfirm = false
    @State private var selectedAsset: PHAsset?

    // 拖动相关状态
    @StateObject private var dragState = DragToRemoveState()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private let dropZoneHeight: CGFloat = 100

    var body: some View {
        let assets = viewModel.pendingAssets()

        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 16) {
                        if assets.isEmpty {
                            Spacer()
                            Text("暂无待删除照片")
                                .foregroundColor(.secondary)
                            Spacer()
                        } else {
                            // 使用 UIKit 包装的可拖动网格
                            DraggableGridView(
                                assets: assets,
                                dragState: dragState,
                                dropZoneHeight: dropZoneHeight,
                                onTap: { asset in
                                    selectedAsset = asset
                                },
                                onRemove: { assetID in
                                    viewModel.removeFromPendingDelete(assetID: assetID)
                                }
                            )
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

                    // 底部感应区（仅在拖动时显示）
                    if dragState.isDragging {
                        VStack {
                            Spacer()
                            DropZoneView(isActive: dragState.isOverDropZone)
                                .frame(height: dropZoneHeight)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .animation(.easeOut(duration: 0.2), value: dragState.isDragging)
                    }

                    // 拖动中的图片浮层（现在在 UIKit 层渲染，这里只保留空占位）
                }
                .onChange(of: geometry.size) { _ in
                    dragState.containerHeight = geometry.size.height
                    dragState.dropZoneHeight = dropZoneHeight
                }
                .onAppear {
                    dragState.containerHeight = geometry.size.height
                    dragState.dropZoneHeight = dropZoneHeight
                }
            }
            .navigationTitle("待删除 (\(viewModel.pendingDeleteIDs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }
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

// MARK: - 拖动状态管理

class DragToRemoveState: ObservableObject {
    @Published var isDragging = false
    @Published var draggingAssetID: String?
    @Published var thumbnail: UIImage?
    @Published var currentPosition: CGPoint = .zero
    @Published var isOverDropZone = false

    var containerHeight: CGFloat = 0
    var dropZoneHeight: CGFloat = 100
    var onRemove: ((String) -> Void)?

    // 窗口相关
    var windowHeight: CGFloat {
        UIScreen.main.bounds.height
    }

    func startDragging(assetID: String, thumbnail: UIImage?, position: CGPoint) {
        self.draggingAssetID = assetID
        self.thumbnail = thumbnail
        self.currentPosition = position
        self.isDragging = true
        self.isOverDropZone = false
    }

    func updatePosition(_ position: CGPoint, windowY: CGFloat) {
        self.currentPosition = position
        // 使用窗口坐标检测感应区
        let dropZoneTop = windowHeight - dropZoneHeight
        self.isOverDropZone = windowY > dropZoneTop
    }

    func endDragging() {
        if isOverDropZone, let assetID = draggingAssetID {
            onRemove?(assetID)
        }
        reset()
    }

    func reset() {
        isDragging = false
        draggingAssetID = nil
        thumbnail = nil
        isOverDropZone = false
    }
}

// MARK: - UIKit 包装的可拖动网格

struct DraggableGridView: UIViewRepresentable {
    let assets: [PHAsset]
    let dragState: DragToRemoveState
    let dropZoneHeight: CGFloat
    let onTap: (PHAsset) -> Void
    let onRemove: (String) -> Void

    func makeUIView(context: Context) -> DraggableGridUIView {
        let view = DraggableGridUIView()
        view.dragState = dragState
        view.onTap = onTap
        view.onRemove = onRemove
        dragState.onRemove = onRemove
        return view
    }

    func updateUIView(_ uiView: DraggableGridUIView, context: Context) {
        uiView.assets = assets
        uiView.dragState = dragState
        uiView.onTap = onTap
        uiView.onRemove = onRemove
        dragState.onRemove = onRemove
        uiView.reloadData()
    }
}

// MARK: - UIKit 网格视图

class DraggableGridUIView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    var assets: [PHAsset] = []
    var dragState: DragToRemoveState?
    var onTap: ((PHAsset) -> Void)?
    var onRemove: ((String) -> Void)?

    private var collectionView: UICollectionView!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var draggingIndexPath: IndexPath?
    private var thumbnailCache: [String: UIImage] = [:]

    // 拖动图片浮层
    private var floatingImageView: UIImageView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCollectionView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4

        collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ThumbnailCell.self, forCellWithReuseIdentifier: "ThumbnailCell")
        addSubview(collectionView)
    }

    private func setupGestures() {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3
        longPressGesture.delegate = self
        collectionView.addGestureRecognizer(longPressGesture)
    }

    func reloadData() {
        collectionView.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds

        let width = bounds.width
        let itemWidth = (width - 4 * 4) / 3  // 3列，4个间距
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
            layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ThumbnailCell", for: indexPath) as! ThumbnailCell
        let asset = assets[indexPath.item]
        cell.configure(with: asset, cache: thumbnailCache) { [weak self] image in
            self?.thumbnailCache[asset.localIdentifier] = image
        }
        cell.setDragging(dragState?.draggingAssetID == asset.localIdentifier)
        return cell
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let asset = assets[indexPath.item]
        onTap?(asset)
    }

    // MARK: - Long Press Gesture

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        let locationInSelf = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
            draggingIndexPath = indexPath
            let asset = assets[indexPath.item]
            let thumbnail = thumbnailCache[asset.localIdentifier]

            // 禁用滚动
            collectionView.isScrollEnabled = false

            // 创建浮动图片
            createFloatingImage(thumbnail: thumbnail, at: locationInSelf)

            // 更新拖动状态（用于感应区显示）
            DispatchQueue.main.async {
                self.dragState?.startDragging(
                    assetID: asset.localIdentifier,
                    thumbnail: thumbnail,
                    position: locationInSelf
                )
            }

            // 触觉反馈
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // 更新单元格显示
            if let cell = collectionView.cellForItem(at: indexPath) as? ThumbnailCell {
                cell.setDragging(true)
            }

        case .changed:
            // 更新浮动图片位置
            updateFloatingImage(at: locationInSelf)

            // 更新拖动状态（用于感应区检测）
            let windowY = window.map { convert(locationInSelf, to: $0).y } ?? locationInSelf.y
            DispatchQueue.main.async {
                self.dragState?.updatePosition(locationInSelf, windowY: windowY)
            }

        case .ended, .cancelled, .failed:
            // 恢复滚动
            collectionView.isScrollEnabled = true

            // 移除浮动图片
            removeFloatingImage()

            // 结束拖动
            DispatchQueue.main.async {
                self.dragState?.endDragging()
            }

            // 恢复单元格显示
            if let indexPath = draggingIndexPath,
               let cell = collectionView.cellForItem(at: indexPath) as? ThumbnailCell {
                cell.setDragging(false)
            }
            draggingIndexPath = nil

        default:
            break
        }
    }

    // MARK: - Floating Image

    private func createFloatingImage(thumbnail: UIImage?, at position: CGPoint) {
        let imageView = UIImageView(image: thumbnail)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.4
        imageView.layer.shadowOffset = CGSize(width: 0, height: 6)
        imageView.layer.shadowRadius = 12
        imageView.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        imageView.center = position

        // 添加到窗口以确保在所有视图之上
        if let window = window {
            let windowPosition = convert(position, to: window)
            imageView.center = windowPosition
            window.addSubview(imageView)
        } else {
            addSubview(imageView)
        }

        // 弹出动画
        imageView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
            imageView.transform = .identity
        }

        floatingImageView = imageView
    }

    private func updateFloatingImage(at position: CGPoint) {
        guard let imageView = floatingImageView else { return }

        if let window = window {
            let windowPosition = convert(position, to: window)
            imageView.center = windowPosition

            // 检测是否在感应区，更新样式
            let isOverDropZone = dragState?.isOverDropZone ?? false
            let targetScale: CGFloat = isOverDropZone ? 0.7 : 1.0
            let targetAlpha: CGFloat = isOverDropZone ? 0.6 : 1.0

            UIView.animate(withDuration: 0.1) {
                imageView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
                imageView.alpha = targetAlpha
            }
        }
    }

    private func removeFloatingImage() {
        guard let imageView = floatingImageView else { return }

        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
            imageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            imageView.alpha = 0
        } completion: { _ in
            imageView.removeFromSuperview()
        }

        floatingImageView = nil
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - 缩略图单元格

class ThumbnailCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private var assetID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.systemGray5
        contentView.addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
    }

    func configure(with asset: PHAsset, cache: [String: UIImage], onLoad: @escaping (UIImage) -> Void) {
        assetID = asset.localIdentifier

        if let cached = cache[asset.localIdentifier] {
            imageView.image = cached
            return
        }

        imageView.image = nil

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        let size = CGSize(width: 200, height: 200)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self = self,
                  self.assetID == asset.localIdentifier,
                  let image = image else { return }
            DispatchQueue.main.async {
                self.imageView.image = image
                onLoad(image)
            }
        }
    }

    func setDragging(_ dragging: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.contentView.alpha = dragging ? 0.3 : 1.0
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        assetID = nil
        contentView.alpha = 1.0
    }
}

// MARK: - 底部感应区视图

struct DropZoneView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    isActive ? Color.green.opacity(0.8) : Color.gray.opacity(0.6)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            // 提示内容
            VStack(spacing: 4) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "arrow.down.to.line")
                    .font(.system(size: 24, weight: .medium))
                Text(isActive ? "松开移除" : "拖到这里移除")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - 单元格位置 PreferenceKey

struct DeleteCellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
