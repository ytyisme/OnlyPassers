import SwiftUI
import UIKit

struct PreviewView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            if let image = model.originalImage {
                SubjectOverlayView(
                    image: image,
                    regions: model.regions,
                    isDetecting: model.isDetecting || !model.didDetect,
                    onSelect: { model.selectSubject(id: $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
            }

            status
            if !model.regions.isEmpty {
                subjectChips
            }

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
            .disabled(model.isProcessing || model.isDetecting || !model.didDetect || model.originalImage == nil)
            .padding(.horizontal)

            if model.isProcessing {
                Text("正在只把路人卡通化…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("重新选择") {
                model.reset()
            }
            .disabled(model.isProcessing)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .navigationTitle("选择主体")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.photoToken) {
            await model.detectSubjects()
        }
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 4) {
            if model.isDetecting || !model.didDetect {
                Text("正在识别照片里的人。")
            } else if model.regions.isEmpty {
                Text("没有检测到人。继续处理会保留原图。")
            } else if model.regions.count == 1 {
                Text("检测到 1 个人，将作为主体保持清晰。")
            } else {
                Text("点一个人设为主体（主视角 / 自己）。其余 \(model.passerbyCount) 人会被卡通化。")
                Text("不改选时，默认是更大、更靠近画面中心的人脸或人物。人脸落在人物框里时，整个人保持清晰。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    private var subjectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.regions.enumerated()), id: \.element.id) { index, region in
                    Button {
                        model.selectSubject(id: region.id)
                    } label: {
                        Text("\(index + 1) \(region.resultRoleTitle)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(region.isMainSubject ? RolePalette.subject : RolePalette.passerby)
                    .disabled(model.isProcessing)
                    .accessibilityLabel("人物 \(index + 1)，\(region.resultRoleTitle)")
                }
            }
            .padding(.horizontal)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PreviewView(model: {
            let model = AppModel(
                processing: StubProcessingService(),
                detecting: StubRegionDetector()
            )
            model.setPhoto(PreviewSample.scene())
            return model
        }())
    }
}
#endif
