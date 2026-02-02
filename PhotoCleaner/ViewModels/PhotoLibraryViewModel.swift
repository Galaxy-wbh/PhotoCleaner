import Photos
import SwiftUI
import UIKit

enum BrowseMode {
    case single   // 单张模式
    case batch    // 批量选择模式
}

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var pendingDeleteIDs: [String] = []
    @Published var toast: ToastModel?
    @Published var alert: AlertModel?
    @Published var showDeleteSheet = false
    @Published var isDeleting = false

    // 批量选择模式相关
    @Published var browseMode: BrowseMode = .single
    @Published private(set) var batchSelectedIDs: Set<String> = []
    private var entryIndex: Int = 0  // 进入批量模式时的索引

    private let pendingStore = PendingDeleteStore()
    private var undoState: UndoState?
    private var toastTask: Task<Void, Never>?

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func bootstrap() {
        pendingDeleteIDs = pendingStore.load()
        refreshAuthorization()
        if isAuthorized {
            loadAssets()
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var currentAsset: PHAsset? {
        guard currentIndex >= 0, currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var previousAsset: PHAsset? {
        let index = currentIndex - 1
        guard index >= 0, index < assets.count else { return nil }
        return assets[index]
    }

    var nextAsset: PHAsset? {
        let index = currentIndex + 1
        guard index >= 0, index < assets.count else { return nil }
        return assets[index]
    }

    var pendingCountText: String {
        "🗑 待删除：\(pendingDeleteIDs.count)"
    }

    var hasPhotos: Bool {
        !assets.isEmpty
    }

    var batchSelectedCountText: String {
        "已选择 \(batchSelectedIDs.count) 张"
    }

    var isAtFirstPhoto: Bool {
        currentIndex <= 0
    }

    var isAtLastPhoto: Bool {
        currentIndex >= assets.count - 1
    }

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if self?.isAuthorized == true {
                    self?.loadAssets()
                }
            }
        }
    }

    func refreshAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        var allAssets: [PHAsset] = []
        allAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }

        let pendingSet = Set(pendingDeleteIDs)
        assets = allAssets.filter { !pendingSet.contains($0.localIdentifier) }
        if currentIndex >= assets.count {
            currentIndex = max(assets.count - 1, 0)
        }
    }

    func moveNext() {
        guard currentIndex < assets.count - 1 else { return }
        currentIndex += 1
    }

    func movePrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func markCurrentForDeletion() {
        guard let asset = currentAsset else { return }
        let removedIndex = currentIndex
        let assetID = asset.localIdentifier

        if !pendingDeleteIDs.contains(assetID) {
            pendingDeleteIDs.append(assetID)
            pendingStore.save(pendingDeleteIDs)
        }

        assets.remove(at: removedIndex)
        if currentIndex >= assets.count {
            currentIndex = max(assets.count - 1, 0)
        }

        undoState = UndoState(asset: asset, index: removedIndex, assetID: assetID)
        showUndoToast()
    }

    func undoLastDeletion() {
        guard let undoState else { return }
        pendingDeleteIDs.removeAll { $0 == undoState.assetID }
        pendingStore.save(pendingDeleteIDs)

        let insertIndex = min(max(0, undoState.index), assets.count)
        assets.insert(undoState.asset, at: insertIndex)
        currentIndex = insertIndex
        self.undoState = nil
        toast = nil
    }

    func pendingAssets() -> [PHAsset] {
        guard !pendingDeleteIDs.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: pendingDeleteIDs, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    func confirmDeletion() {
        guard !pendingDeleteIDs.isEmpty else { return }
        let idsToDelete = pendingDeleteIDs
        let assetsToDelete = pendingAssets()
        guard !assetsToDelete.isEmpty else {
            pendingDeleteIDs.removeAll()
            pendingStore.save(pendingDeleteIDs)
            alert = AlertModel(
                title: "待删除照片不存在",
                message: "未找到可删除的照片，已清空暂存列表。",
                primaryButton: .default("好的", action: nil)
            )
            loadAssets()
            return
        }
        isDeleting = true

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }, completionHandler: { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isDeleting = false

                if success {
                    let remainingAssets = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
                    var remainingIDs: [String] = []
                    remainingAssets.enumerateObjects { asset, _, _ in
                        remainingIDs.append(asset.localIdentifier)
                    }

                    let failedSet = Set(remainingIDs)
                    self.pendingDeleteIDs.removeAll { !failedSet.contains($0) }
                    self.pendingStore.save(self.pendingDeleteIDs)
                    self.loadAssets()

                    if failedSet.isEmpty {
                        self.showToast(message: "已删除 \(idsToDelete.count) 张照片", actionTitle: nil, action: nil, duration: 2.5, clearUndo: true)
                    } else {
                        self.alert = AlertModel(
                            title: "部分删除失败",
                            message: "有 \(failedSet.count) 张照片未能删除，请稍后再试。",
                            primaryButton: .default("好的", action: nil)
                        )
                    }
                } else {
                    let message = error?.localizedDescription ?? "删除失败，请稍后重试。"
                    self.alert = AlertModel(
                        title: "删除失败",
                        message: message,
                        primaryButton: .default("好的", action: nil)
                    )
                }
            }
        })
    }

    private func showUndoToast() {
        showToast(
            message: "已加入删除",
            actionTitle: "撤销",
            action: { [weak self] in
                Task { @MainActor in
                    self?.undoLastDeletion()
                }
            },
            duration: 4.0,
            clearUndo: false
        )
    }

    func showBoundaryToast(isLast: Bool) {
        let message = isLast ? "已经是最后一张照片" : "已经是第一张照片"
        showToast(message: message, actionTitle: nil, action: nil, duration: 1.5, clearUndo: true)
    }

    // MARK: - 批量选择模式

    func enterBatchMode() {
        entryIndex = currentIndex
        batchSelectedIDs.removeAll()
        browseMode = .batch
    }

    func exitBatchMode(toAssetID: String? = nil) {
        browseMode = .single
        if let assetID = toAssetID,
           let index = assets.firstIndex(where: { $0.localIdentifier == assetID }) {
            currentIndex = index
        } else {
            // 返回进入时的位置，如果位置已失效则保持在有效范围内
            currentIndex = min(entryIndex, max(assets.count - 1, 0))
        }
        batchSelectedIDs.removeAll()
    }

    func toggleBatchSelection(for assetID: String) {
        if batchSelectedIDs.contains(assetID) {
            batchSelectedIDs.remove(assetID)
        } else {
            batchSelectedIDs.insert(assetID)
        }
    }

    func addToBatchSelection(_ assetID: String) {
        batchSelectedIDs.insert(assetID)
    }

    func removeFromBatchSelection(_ assetID: String) {
        batchSelectedIDs.remove(assetID)
    }

    /// 进入批量模式时的当前照片ID，用于ScrollView定位
    var entryAssetID: String? {
        guard entryIndex >= 0, entryIndex < assets.count else { return nil }
        return assets[entryIndex].localIdentifier
    }

    func isBatchSelected(_ assetID: String) -> Bool {
        batchSelectedIDs.contains(assetID)
    }

    func selectAllForBatch() {
        batchSelectedIDs = Set(assets.map { $0.localIdentifier })
    }

    func deselectAllForBatch() {
        batchSelectedIDs.removeAll()
    }

    var isAllSelectedForBatch: Bool {
        !assets.isEmpty && batchSelectedIDs.count == assets.count
    }

    func markBatchSelectedForDeletion() {
        guard !batchSelectedIDs.isEmpty else { return }

        let selectedCount = batchSelectedIDs.count
        for assetID in batchSelectedIDs {
            if !pendingDeleteIDs.contains(assetID) {
                pendingDeleteIDs.append(assetID)
            }
        }
        pendingStore.save(pendingDeleteIDs)

        // 从 assets 中移除已选中的照片
        assets.removeAll { batchSelectedIDs.contains($0.localIdentifier) }

        // 调整 currentIndex
        if currentIndex >= assets.count {
            currentIndex = max(assets.count - 1, 0)
        }

        batchSelectedIDs.removeAll()

        showToast(message: "已将 \(selectedCount) 张照片加入待删除", actionTitle: nil, action: nil, duration: 2.5, clearUndo: true)
    }

    private func showToast(message: String, actionTitle: String?, action: (() -> Void)?, duration: TimeInterval, clearUndo: Bool) {
        toastTask?.cancel()
        let model = ToastModel(message: message, actionTitle: actionTitle, action: action)
        toast = model

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if toast?.id == model.id {
                toast = nil
                if clearUndo {
                    undoState = nil
                }
            }
        }
    }
}

private struct UndoState {
    let asset: PHAsset
    let index: Int
    let assetID: String
}

struct AlertModel: Identifiable {
    enum ButtonStyle {
        case `default`(String, action: (() -> Void)?)
    }

    let id = UUID()
    let title: String
    let message: String
    let primaryButton: ButtonStyle
}

struct ToastModel: Identifiable {
    let id = UUID()
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
}
