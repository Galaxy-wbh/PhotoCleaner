import PhotosUI
import SwiftUI
import UIKit

// MARK: - Live Photo 播放视图

struct LivePhotoPlayerView: UIViewRepresentable {
    let asset: PHAsset
    let targetSize: CGSize
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let livePhotoView = PHLivePhotoView()
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.delegate = context.coordinator
        return livePhotoView
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        // 当需要播放时加载 Live Photo
        if isPlaying {
            loadLivePhoto(into: uiView)
        } else {
            uiView.stopPlayback()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func loadLivePhoto(into livePhotoView: PHLivePhotoView) {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

        PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { livePhoto, info in
            guard let livePhoto else { return }
            DispatchQueue.main.async {
                livePhotoView.livePhoto = livePhoto
                // 自动开始播放
                livePhotoView.startPlayback(with: .full)
            }
        }
    }

    class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoPlayerView

        init(_ parent: LivePhotoPlayerView) {
            self.parent = parent
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            // 播放结束后，如果仍然处于按压状态，重新播放
            if parent.isPlaying {
                livePhotoView.startPlayback(with: .full)
            }
        }
    }
}

// MARK: - Live Photo 叠加层（全屏播放）

struct LivePhotoOverlay: View {
    let asset: PHAsset
    let targetSize: CGSize
    @Binding var isShowing: Bool

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            // Live Photo 播放器
            LivePhotoPlayerView(
                asset: asset,
                targetSize: targetSize,
                isPlaying: $isShowing
            )

            // 顶部 LIVE 标识
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "livephoto.play")
                            .font(.system(size: 14, weight: .semibold))
                        Text("LIVE")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
                    .padding(.leading, 16)
                    .padding(.top, 60)

                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            // 添加全局触摸监听
            setupTouchMonitor()
        }
        .onDisappear {
            removeTouchMonitor()
        }
    }

    private func setupTouchMonitor() {
        // 使用 NotificationCenter 来监听触摸结束
        NotificationCenter.default.addObserver(
            forName: .livephotoTouchEnded,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowing = false
            }
        }
    }

    private func removeTouchMonitor() {
        NotificationCenter.default.removeObserver(self, name: .livephotoTouchEnded, object: nil)
    }
}

extension Notification.Name {
    static let livephotoTouchEnded = Notification.Name("livephotoTouchEnded")
}

// MARK: - 长按手势检测器（用于 PhotoBrowserView）

struct LongPressGestureView: UIViewRepresentable {
    let minimumDuration: Double
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = minimumDuration
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onEnded: onEnded)
    }

    class Coordinator: NSObject {
        var onBegan: () -> Void
        var onEnded: () -> Void

        init(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onEnded = onEnded
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                onBegan()
            case .ended, .cancelled, .failed:
                onEnded()
                // 同时发送通知，确保 LivePhotoOverlay 能收到
                NotificationCenter.default.post(name: .livephotoTouchEnded, object: nil)
            default:
                break
            }
        }
    }
}
