import Photos
import SwiftUI

struct PhotoBrowserView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.hasPhotos {
                GeometryReader { proxy in
                    swipeStack(in: proxy.size)
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
        .sheet(isPresented: $viewModel.showDeleteSheet) {
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
                PhotoAssetImageView(asset: current, targetSize: size)
                    .offset(dragOffset)
            }

            if let next = viewModel.nextAsset {
                PhotoAssetImageView(asset: next, targetSize: size)
                    .offset(x: size.width + dragOffset.width)
                    .opacity(0.6)
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
        let verticalThreshold = size.height * 0.15
        let translation = value.translation

        if abs(translation.height) > abs(translation.width), translation.height < -verticalThreshold {
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
