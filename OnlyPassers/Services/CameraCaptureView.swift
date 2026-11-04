import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 系统相机。模拟器通常没有相机，调用方应先看 `UIImagePickerController.isSourceTypeAvailable`。
struct CameraCaptureView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            // 系统在主线程回调，但不能直接碰 MainActor 上的 SwiftUI 闭包。
            MainActor.assumeIsolated {
                if let image {
                    self.parent.onImage(image)
                } else {
                    self.parent.onCancel()
                }
            }
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            MainActor.assumeIsolated {
                self.parent.onCancel()
            }
        }
    }
}
