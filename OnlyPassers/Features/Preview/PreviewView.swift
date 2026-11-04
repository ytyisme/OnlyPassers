import SwiftUI
import UIKit

struct PreviewView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if let image = model.originalImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .accessibilityLabel("原图")
            }

            Text("确认这张原图。处理时会把路人卡通化，主体和风景保持清晰。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task { await model.process() }
            } label: {
                Group {
                    if model.isProcessing {
                        ProgressView()
                    } else {
                        Text("开始处理")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isProcessing || model.originalImage == nil)
            .padding(.horizontal)

            Button("重新选择") {
                model.reset()
            }
            .disabled(model.isProcessing)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .navigationTitle("原图预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PreviewView(model: {
            let model = AppModel()
            model.setPhoto(PreviewSample.scene())
            return model
        }())
    }
}
#endif
