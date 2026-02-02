import Photos
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()

    var body: some View {
        Group {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                PermissionRequestView(onRequest: {
                    viewModel.requestAuthorization()
                })
            case .authorized, .limited:
                switch viewModel.browseMode {
                case .single:
                    PhotoBrowserView(viewModel: viewModel)
                case .batch:
                    BatchSelectView(viewModel: viewModel)
                }
            case .denied, .restricted:
                PermissionDeniedView(onOpenSettings: {
                    viewModel.openSettings()
                })
            @unknown default:
                PermissionDeniedView(onOpenSettings: {
                    viewModel.openSettings()
                })
            }
        }
        .onAppear {
            viewModel.bootstrap()
        }
    }
}
