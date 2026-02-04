import Photos
import SwiftUI

struct PhotoBrowserView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var dragOffset: CGSize = .zero
    @State private var isShowingLivePhoto: Bool = false

    private var currentIsLivePhoto: Bool {
        viewModel.currentAsset?.mediaSubtypes.contains(.photoLive) == true
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.hasPhotos {
                GeometryReader { proxy in
                    ZStack {
                        swipeStack(in: proxy.size)

                        // Live Photo 播放叠加层
                        if isShowingLivePhoto, let asset = viewModel.currentAsset {
                            LivePhotoOverlay(
                                asset: asset,
                                targetSize: proxy.size,
                                isShowing: $isShowingLivePhoto
                            )
                            .transition(.opacity)
                        }
                    }
                }
            } else {
                EmptyStateView()
                    .foregroundColor(.white)
            }

            VStack {
                HStack {
                    Button {
                        if !viewModel.pendingDeleteIDs.isEmpty {
                            viewModel.showDeleteSheet = true
                        }
                    } label: {
                        Text(viewModel.pendingCountText)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.pendingDeleteIDs.isEmpty)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Spacer()

                Button {
                    viewModel.showDeleteSheet = true
                } label: {
                    Text("确认删除")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .disabled(viewModel.pendingDeleteIDs.isEmpty)
            }

            if let toast = viewModel.toast {
                VStack {
                    Spacer()
                    ToastView(model: toast)
                        .padding(.bottom, 88)
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

    @ViewBuilder
    private func swipeStack(in size: CGSize) -> some View {
        ZStack {
            if let previous = viewModel.previousAsset {
                PhotoAssetImageView(asset: previous, targetSize: size)
                    .offset(x: -size.width + dragOffset.width)
                    .opacity(0.6)
            }

            if let current = viewModel.currentAsset {
                ZStack {
                    PhotoAssetImageView(asset: current, targetSize: size)

                    // Live Photo 标识（左上角）
                    if currentIsLivePhoto {
                        VStack {
                            HStack {
                                LivePhotoBadge()
                                    .padding(.leading, 16)
                                    .padding(.top, 60)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
                .offset(dragOffset)
            }

            if let next = viewModel.nextAsset {
                PhotoAssetImageView(asset: next, targetSize: size)
                    .offset(x: size.width + dragOffset.width)
                    .opacity(0.6)
            }

            // 长按手势检测层（仅当是 Live Photo 时才启用）
            if currentIsLivePhoto {
                LongPressGestureView(
                    minimumDuration: 0.3,
                    onBegan: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingLivePhoto = true
                        }
                    },
                    onEnded: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingLivePhoto = false
                        }
                    }
                )
                .allowsHitTesting(!isShowingLivePhoto)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    handleSwipe(value: value, size: size)
                }
        )
    }

    private func handleSwipe(value: DragGesture.Value, size: CGSize) {
        let horizontalThreshold = size.width * 0.2
        let upThreshold = size.height * 0.18
        let downThreshold = size.height * 0.25
        let verticalDominanceRatio: CGFloat = 1.6
        let translation = value.translation

        // 向上滑动 - 加入待删除
        if abs(translation.height) > abs(translation.width) * verticalDominanceRatio,
           translation.height < -upThreshold {
            withAnimation(.easeIn(duration: 0.2)) {
                dragOffset = CGSize(width: 0, height: -size.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                viewModel.markCurrentForDeletion()
                withAnimation(.none) {
                    dragOffset = .zero
                }
            }
            return
        }

        // 向下滑动 - 进入批量选择模式
        if abs(translation.height) > abs(translation.width) * verticalDominanceRatio,
           translation.height > downThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: 0, height: size.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.enterBatchMode()
                withAnimation(.none) {
                    dragOffset = .zero
                }
            }
            return
        }

        if translation.width <= -horizontalThreshold {
            if viewModel.isAtLastPhoto {
                viewModel.showBoundaryToast(isLast: true)
                withAnimation(.spring()) {
                    dragOffset = .zero
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dragOffset = CGSize(width: -size.width, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.moveNext()
                    withAnimation(.none) {
                        dragOffset = .zero
                    }
                }
            }
        } else if translation.width >= horizontalThreshold {
            if viewModel.isAtFirstPhoto {
                viewModel.showBoundaryToast(isLast: false)
                withAnimation(.spring()) {
                    dragOffset = .zero
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dragOffset = CGSize(width: size.width, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.movePrevious()
                    withAnimation(.none) {
                        dragOffset = .zero
                    }
                }
            }
        } else {
            withAnimation(.spring()) {
                dragOffset = .zero
            }
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
