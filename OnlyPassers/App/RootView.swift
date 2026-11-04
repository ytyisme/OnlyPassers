import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationStack {
            switch model.step {
            case .capture:
                CaptureView(model: model)
            case .preview:
                PreviewView(model: model)
            case .result:
                ResultView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.step)
        .alert("出错了", isPresented: errorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }
}

#if DEBUG
#Preview {
    RootView()
}
#endif
