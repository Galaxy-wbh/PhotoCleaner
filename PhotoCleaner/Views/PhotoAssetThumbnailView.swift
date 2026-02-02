import Photos
import SwiftUI
import UIKit

struct PhotoAssetThumbnailView: View {
    let asset: PHAsset
    let size: CGSize

    @State private var image: UIImage?
    private static let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: size.width, height: size.height)
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            await requestThumbnail()
        }
    }

    private func requestThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        // 确保请求足够大的尺寸
        let minSize: CGFloat = 200
        let targetWidth = max(size.width * scale, minSize * scale)
        let targetHeight = max(size.height * scale, minSize * scale)
        let target = CGSize(width: targetWidth, height: targetHeight)

        await withCheckedContinuation { continuation in
            Self.imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                Task { @MainActor in
                    self.image = image
                    continuation.resume()
                }
            }
        }
    }
}
