# 路人画 / OnlyPassers

只把**路人**卡通化，**主体（主视角 / 自己）**和**风景**保持清晰、写实。检测、蒙版和风格都在设备上完成，照片不会上传。

Selectively cartoonize bystanders. Keep the main subject and the scenery photoreal. Vision, person masks, and the cartoon composite all stay on device.

## 现在能做什么

1. 从相册选一张照片，或在有相机的设备上拍摄。选中的图会先转成正向像素，预览和检测用同一套左上角坐标。
2. 预览页用 Vision 找出人，并在照片上画出可点的框。
3. 点一个人，把他标成主体。不点也可以直接处理，这时用下面的默认规则。
4. 点「开始处理」。只有路人被卡通化；主体和风景用原图像素合成回去。
5. 结果页并排看处理前后。有路人时，处理后的说明是 **主体清晰 · 路人卡通**。

模拟器通常没有相机。请用相册，或在真机上拍摄。相册走系统的 PhotosUI 选择器，不申请完整相册权限。

`StubRegionDetector` 和 `StubProcessingService` 还在，只给 SwiftUI 预览用。正式界面走 `VisionRegionDetector` 和 `OnDeviceProcessingService`。

## 主体是怎么选的

预览里点谁，谁就是主体。这个选择写进 `FaceOrPersonRegion.isMainSubject`，再放进 `ProcessRequest.regions`。处理时不会改掉用户的选择。

用户没有点选时，`SubjectSelection` 的规则是：

1. 只检测到一个人：那个人就是主体。
2. 否则给人脸框和每个检测区域打分：`0.62 × √面积 + 0.38 × 居中程度`。面积是归一化框的宽×高。居中程度在画面正中为 1，在四个角为 0。
3. 分数最高的如果是人脸，并且它落在某个人物框里，**主体是那个人物**（整个人保持清晰，不只是脸）。
4. 分数最高的如果本来就是一个区域，主体就是那个区域。

检测器在返回区域之前就会套用这条规则，所以一进预览就能看到谁被标成绿色主体。

## 卡通路径

生产实现是端侧 Core Image，不是云端模型，仓库里也没有大的 Core ML 权重。

1. **蒙版**（按顺序退让）
   - `VNGeneratePersonInstanceMaskRequest`：每个人一张实例蒙版，只把非主体的实例放进卡通。这是首选。
   - `VNGeneratePersonSegmentationRequest`：全体人物分割，再挖掉主体框。实例蒙版失败时使用（模拟器上常见）。
   - 人物框：再失败时，按路人框铺一块柔边蒙版。只有人脸时，会把脸向下扩成一个大致的身体。主体框会被挖空。
2. **风格**：`BystanderStyling` 先把整张图画成卡通，再用蒙版合成。白的地方用卡通，黑的地方留原图，所以风景和主体像素不经过风格滤镜。
   - 默认 `styleID` 是 `cartoon-bystander`（`ProcessRequest.defaultStyleID`）：`CIComicEffect`。滤镜不可用时退到色块加勾线。
   - `cartoon-poster`：色块（`CIColorPosterize`）加 `CIEdges` 勾线。
   - 其它未知 id 仍走端侧漫画效果，避免不小心把图传出去。
3. **以后换 Core ML**：实现 `BystanderStyling`，用 `OnDeviceProcessingService(makeStylist:)` 注入。风格化器只收到整张图，不用自己区分主体。创建会在后台队列发生，不要联网，也不要依赖主线程。

长边超过 2048 像素时，选图就会先缩小。检测和合成都用这张图，避免漫画滤镜占满内存。有路人被处理时，结果页的「原图」是参与合成的那一张，方便和结果对齐。没有路人时，结果就是选图后的数据，不再压缩一次。

Vision 的 `boundingBox` 原点在左下角。`SubjectGeometry.topLeft(fromVisionBottomLeft:)` 会换成 `FaceOrPersonRegion` 用的左上角归一化坐标。实例蒙版的标签图第 0 行按转正后画面的顶部来读。

## 用 Xcode 打开

需要 macOS 和 **Xcode 16 或更新**（iOS 17+ 模拟器或真机）。没有 CocoaPods，也没有第三方 Swift Package。用到的系统框架是 SwiftUI、PhotosUI、UIKit、Vision、Core Image、Core Video 和 ImageIO。

1. 打开 `OnlyPassers.xcodeproj`。
2. Scheme 选 **OnlyPassers**，运行目的地选一台 iPhone（iOS 17 或更高）。人物实例蒙版在真机上更可靠；模拟器若报推理上下文错误，会自动退到人体 / 人脸框。
3. 签名里还没有 Team。若 Xcode 提示签名，在 Signing & Capabilities 选择你的 Team；模拟器也可以用 Sign to Run Locally。
4. Run。Bundle ID 目前是 `com.ytyisme.OnlyPassers`，可以按需修改。

工程使用 Xcode 16 的同步文件夹（`PBXFileSystemSynchronizedRootGroup`）。在 `OnlyPassers/` 里新增 Swift 文件会自动进 target，一般不用改 `project.pbxproj`。`Info.plist` 已排除在资源拷贝之外。

请保持默认的 actor 隔离（nonisolated）。如果以后接受 Xcode 的升级建议、把 `SWIFT_DEFAULT_ACTOR_ISOLATION` 设成 `MainActor`，模型上的 `Sendable` 需要再看一眼。

## 目录

| 路径 | 作用 |
| --- | --- |
| `OnlyPassers/App` | 入口、导航、流程状态。默认注入端侧检测和处理 |
| `OnlyPassers/Features/Capture` | 相册与相机 |
| `OnlyPassers/Features/Preview` | 原图、人物框、点选主体 |
| `OnlyPassers/Features/Result` | 处理前后对比，以及主体清晰 / 路人卡通 |
| `OnlyPassers/Models` | `FaceOrPersonRegion`、`ProcessRequest`、`ProcessResult` |
| `OnlyPassers/Services` | Vision 检测、主体选择、路人蒙版、Core Image 卡通，以及预览占位 |

## 还没做

- 没有打包生成式 Core ML 风格模型。现在的卡通是 Core Image，接缝和笔触还不是插画模型的效果。
- 人物实例蒙版一次大约覆盖四个人。多出来的人如果能被人体框或人脸框看到，会用框形蒙版补上，边缘不如实例蒙版干净。
- 人叠在一起时，宁可让挨着主体的路人保持清晰，也不要把主体卡通化。
- 模拟器上实例分割和人物分割可能失败，这时看到的是框形卡通，不是轮廓蒙版。
- 还没有实况取景或视频。风格选择也还没有单独的界面，只认 `ProcessRequest.styleID`。

## English

OnlyPassers cartoonizes bystanders and leaves the main subject plus the scenery sharp. Pick or capture a photo, tap who is the main subject (or skip and accept the default), then compare before and after. Nothing is uploaded.

Detection uses Vision on device: person instance masks first, then human rectangles, then face rectangles. Boxes are converted from Vision’s bottom-left normalized space to UIKit top-left before they become `FaceOrPersonRegion` values. The default subject is the highest score of `0.62 * sqrt(area) + 0.38 * centrality` among faces and regions. A winning face inside a person box selects that whole person. A single detected person is always the subject. A tap writes `isMainSubject` and is sent on `ProcessRequest.regions`.

The cartoon path is Core Image, masked to non-subject people. `CIComicEffect` is the default for `cartoon-bystander`. `cartoon-poster` is posterize plus edges. If instance masks are unavailable, the app falls back to person segmentation minus the subject box, then to soft boxes. `BystanderStyling` and `OnDeviceProcessingService(makeStylist:)` are the extension point for a future on-device Core ML style model. The working image is capped at 2048 pixels on the long side. Stubs remain for SwiftUI previews only.

Open `OnlyPassers.xcodeproj` in Xcode 16 or later, choose an iPhone on iOS 17+, and run. Signing has no Team yet. Instance masks are more reliable on a device; the simulator may fall back to boxes.

## License

MIT. See [LICENSE](LICENSE).
