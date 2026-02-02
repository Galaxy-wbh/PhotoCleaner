import Photos
import SwiftUI
import UIKit

// MARK: - 图片缓存管理器
final class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    private let imageManager = PHCachingImageManager()

    private init() {
        cache.countLimit = 100  // 增大缓存容量
        cache.totalCostLimit = 200 * 1024 * 1024  // 200MB
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// 预加载指定照片的高清图片到缓存
    func preloadImage(for asset: PHAsset, targetSize: CGSize) {
        let assetID = asset.localIdentifier

        // 已在缓存中则跳过
        if image(for: assetID) != nil {
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

        imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            if let image {
                self?.setImage(image, for: assetID)
            }
        }
    }
}

struct PhotoAssetImageView: View {
    let asset: PHAsset
    let targetSize: CGSize

    @State private var loadedImage: UIImage?
    @State private var loadedAssetID: String = ""
    private static let imageManager = PHCachingImageManager()

    private var displayImage: UIImage? {
        // 优先显示已加载的正确图片
        if loadedAssetID == asset.localIdentifier, let loadedImage {
            return loadedImage
        }
        // 其次尝试从缓存获取
        return ImageCache.shared.image(for: asset.localIdentifier)
    }

    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .task(id: asset.localIdentifier) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let assetID = asset.localIdentifier

        // 如果已经加载了正确的图片，直接返回
        if loadedAssetID == assetID, loadedImage != nil {
            return
        }

        // 先从缓存获取
        if let cachedImage = ImageCache.shared.image(for: assetID) {
            self.loadedImage = cachedImage
            self.loadedAssetID = assetID
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

        await withCheckedContinuation { continuation in
            Self.imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                Task { @MainActor in
                    if let image {
                        ImageCache.shared.setImage(image, for: assetID)
                        self.loadedImage = image
                        self.loadedAssetID = assetID
                    }
                    continuation.resume()
                }
            }
        }
    }
}
