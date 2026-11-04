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
                    Text(resultExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let summary = model.result?.summary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let original = beforeImage {
                    photoCard(title: "原图", caption: nil, image: original)
                }
                if let processed = model.processedImage {
                    photoCard(title: "处理后", caption: processedCaption, image: processed)
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

    private var beforeImage: UIImage? {
        if let data = model.result?.originalImageData, let image = UIImage(data: data) {
            return image
        }
        return model.originalImage
    }

    private var isPlaceholderResult: Bool {
        model.result?.summary.contains("占位") == true
    }

    private var resultExplanation: String {
        if isPlaceholderResult {
            return "当前是预览占位：图上只有示意框，还没有卡通化。"
        }
        return "对比原图和处理结果。只有路人被卡通化，主体和风景仍来自原图。"
    }

    private var processedCaption: String {
        if isPlaceholderResult {
            return "占位标记"
        }
        guard let regions = model.result?.regions, !regions.isEmpty else {
            return "保持原图"
        }
        if regions.contains(where: { !$0.isMainSubject }) {
            return "主体清晰 · 路人卡通"
        }
        return "主体清晰"
    }

    private func photoCard(title: String, caption: String?, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let caption {
                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(caption.map { "\(title)，\($0)" } ?? title)
        }
    }

    private func regionList(_ regions: [FaceOrPersonRegion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("人物")
                .font(.headline)
            Text(isPlaceholderResult ? "固定占位，不是 Vision 检测结果。" : "主体清晰，路人卡通。风景没有框，始终用原图。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                LabeledContent {
                    Text(region.kindTitle)
                        .foregroundStyle(.secondary)
                } label: {
                    Label {
                        Text("\(index + 1) · \(region.resultRoleTitle)")
                    } icon: {
                        Image(systemName: region.isMainSubject ? "person.fill.checkmark" : "person.fill")
                            .foregroundStyle(region.isMainSubject ? RolePalette.subject : RolePalette.passerby)
                    }
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
    @State private var model = AppModel(
        processing: StubProcessingService(),
        detecting: StubRegionDetector()
    )

    var body: some View {
        ResultView(model: model)
            .task {
                model.setPhoto(PreviewSample.scene())
                await model.process()
            }
    }
}
#endif
