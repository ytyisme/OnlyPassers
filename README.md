# 路人画 / OnlyPassers

只把**路人**卡通化，**主体（主视角 / 自己）**和**风景**保持清晰、写实。

Selectively cartoonize bystanders. Keep the main subject and the scenery photoreal.

## 现在能做什么

这是一个可运行的 SwiftUI 骨架，还没有机器学习管线。

1. 从相册选一张照片，或在有相机的设备上拍摄。
2. 预览原图。
3. 点「开始处理」。`ProcessingService` 的占位实现会交回同一张图，并画上可见标记：绿色框是主体，橙色框是路人，底部有「尚未卡通化」。
4. 结果页并排看处理前后。说明文案是：**路人卡通化，主体与风景保持清晰**。

模拟器通常没有相机。请用相册，或在真机上拍摄。相册走系统的 PhotosUI 选择器，不申请完整相册权限。

## 用 Xcode 打开

需要 macOS 和 **Xcode 16 或更新**（iOS 17+ 模拟器）。没有 CocoaPods，也没有第三方 Swift Package，只用 SwiftUI、PhotosUI 和 UIKit。

1. 打开 `OnlyPassers.xcodeproj`。
2. Scheme 选 **OnlyPassers**，运行目的地选一台 iPhone 模拟器（iOS 17 或更高）。
3. 签名里还没有 Team。若 Xcode 提示签名，在 Signing & Capabilities 选择你的 Team；模拟器也可以用 Sign to Run Locally。
4. Run。Bundle ID 目前是 `com.ytyisme.OnlyPassers`，可以按需修改。

工程使用 Xcode 16 的同步文件夹（`PBXFileSystemSynchronizedRootGroup`）。在 `OnlyPassers/` 里新增 Swift 文件会自动进 target，一般不用改 `project.pbxproj`。`Info.plist` 已排除在资源拷贝之外。

请保持默认的 actor 隔离（nonisolated）。如果以后接受 Xcode 的升级建议、把 `SWIFT_DEFAULT_ACTOR_ISOLATION` 设成 `MainActor`，模型上的 `Sendable` 需要再看一眼。

## 目录

| 路径 | 作用 |
| --- | --- |
| `OnlyPassers/App` | 入口、导航、流程状态 |
| `OnlyPassers/Features/Capture` | 相册与相机 |
| `OnlyPassers/Features/Preview` | 原图预览，「开始处理」 |
| `OnlyPassers/Features/Result` | 处理前后对比 |
| `OnlyPassers/Models` | `FaceOrPersonRegion`、`ProcessRequest`、`ProcessResult` |
| `OnlyPassers/Services` | `ProcessingService`、`RegionDetecting` 与占位实现 |

## 占位实现

`StubRegionDetector` 不看照片内容，只返回三块固定区域，中间一块标成主体。`StubProcessingService` 把这些框画到图上，证明按钮已经接到流水线上。

之后替换实现即可，界面不用改：

- `RegionDetecting`：人物分割 / 人脸框。这里的归一化坐标原点在**左上角**（UIKit）。Vision 的 `boundingBox` 原点在左下角，转换放在检测器里。
- `ProcessingService`：只对非主体的人做卡通化，再和清晰的主体、风景合成。
- `ProcessRequest.regions`：空则走检测器。主体选择 UI 之后可以把用户确认过的区域填进来。
- `ProcessRequest.styleID`：预留给卡通风格，占位实现忽略它。默认值是 `cartoon-bystander`。

## 下一步

1. **人物分割**：用 `VNGeneratePersonSegmentationRequest`（以及人脸检测）替换 `StubRegionDetector`。
2. **主体选择**：让用户指定谁是主视角 / 自己，写入 `FaceOrPersonRegion.isMainSubject`。
3. **卡通只发生在路人上**：对非主体人物蒙版做风格迁移或生成式卡通，主体像素和背景保持原图。
4. 用合成结果替换 `StubProcessingService` 里的描边占位。

## English

OnlyPassers cartoonizes bystanders and leaves the main subject plus the scenery sharp. This repository is an iOS 17+ SwiftUI shell: pick or capture a photo, preview the original, tap Process, then compare before and after. `StubProcessingService` returns the same photo with placeholder boxes (green = subject, orange = bystanders) so the pipeline is visible. It compiles with Apple frameworks only. Open `OnlyPassers.xcodeproj` in Xcode 16 or later, choose an iPhone simulator, and run. Signing has no Team yet. Next ML steps: person segmentation, subject selection, then a cartoon style applied only to non-subject people.

## License

MIT. See [LICENSE](LICENSE).
