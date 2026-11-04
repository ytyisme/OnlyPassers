import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureView: View {
    var model: AppModel

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showCamera = false
    @State private var cameraUnavailable = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 12)
                    header
                    buttons
                    Spacer(minLength: 12)
                    Text("检测和卡通化都在本机完成，照片不会上传。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .navigationTitle("路人画")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pickerItem) {
            await loadSelectedPhoto()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onImage: { image in
                    showCamera = false
                    model.setPhoto(image)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $cameraUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这台设备没有可用的相机。模拟器通常如此。请改从相册选择，或在真机上重试。")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("路人画")
                .font(.largeTitle.bold())
            Text("OnlyPassers")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("把路人变成卡通，主体和风景保持清晰。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Group {
                    if isLoadingPhoto {
                        ProgressView()
                    } else {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoadingPhoto)

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    cameraUnavailable = true
                }
            } label: {
                Label("拍摄照片", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoadingPhoto)
        }
    }

    private func loadSelectedPhoto() async {
        guard let pickerItem else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            // Data.self 对很多资源会失败；用 image 的 DataRepresentation 更稳。
            guard let picked = try await pickerItem.loadTransferable(type: PickedPhoto.self),
                  let image = UIImage(data: picked.data) else {
                model.errorMessage = "无法读取所选照片。"
                return
            }
            model.setPhoto(image)
        } catch is CancellationError {
            return
        } catch {
            model.errorMessage = "读取照片失败。"
        }
    }
}

/// PhotosPicker 不保证 `Data.self` 能接住 `public.image`，单独声明一个导入类型。
private struct PickedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPhoto(data: data)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CaptureView(model: AppModel(
            processing: StubProcessingService(),
            detecting: StubRegionDetector()
        ))
    }
}
#endif
