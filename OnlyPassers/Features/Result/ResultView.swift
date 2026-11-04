import SwiftUI
import UIKit

struct ResultView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("路人卡通化，主体与风景保持清晰")
                        .font(.title3.bold())
                    Text("占位结果只画出了示意框。接入模型后，路人会变成卡通，主体和风景仍用原图像素。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let summary = model.result?.summary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let original = model.originalImage {
                    photoCard(title: "原图", image: original)
                }
                if let processed = model.processedImage {
                    photoCard(title: "处理后", image: processed)
                } else if model.isProcessing || model.result == nil {
                    ProgressView("正在准备结果…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                if let regions = model.result?.regions, !regions.isEmpty {
                    regionList(regions)
                }

                Button("再处理一张") {
                    model.reset()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(model.isProcessing)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("处理结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func photoCard(title: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }
    }

    private func regionList(_ regions: [FaceOrPersonRegion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("示意区域")
                .font(.headline)
            Text("固定占位，不是 Vision 检测结果。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(regions) { region in
                LabeledContent(region.roleTitle) {
                    Text(region.kindTitle)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ResultPreviewHost()
    }
}

private struct ResultPreviewHost: View {
    @State private var model = AppModel()

    var body: some View {
        ResultView(model: model)
            .task {
                model.setPhoto(PreviewSample.scene())
                await model.process()
            }
    }
}
#endif
