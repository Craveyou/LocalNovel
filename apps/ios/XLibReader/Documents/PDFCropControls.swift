import SwiftUI

struct PDFCropControls: View {
    let model: DocumentReaderModel

    var body: some View {
        Form {
            Section {
                Toggle("启用裁边", isOn: Binding(get: { model.pdfCrop.enabled }, set: { enabled in
                    var value = model.pdfCrop; value.enabled = enabled; model.setPDFCrop(value)
                }))
                .accessibilityIdentifier("pdfCrop.enabled")
                margin("左侧", keyPath: \.left, identifier: "pdfCrop.left")
                margin("右侧", keyPath: \.right, identifier: "pdfCrop.right")
                Button("恢复原页") { model.setPDFCrop(PDFCropSettings()) }
                    .accessibilityIdentifier("pdfCrop.reset")
            } footer: {
                Text("左右各可裁去 0–30%，所有 PDF 即时共用，不保存，重启应用后恢复默认。仅改变阅读显示，不修改原 PDF、书签或同步坐标。若正文被遮挡，请减小边距或恢复原页。")
            }
        }
        .navigationTitle("PDF 裁边")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func margin(_ title: String, keyPath: WritableKeyPath<PDFCropSettings, Double>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) \(Int((model.pdfCrop[keyPath: keyPath] * 100).rounded()))%")
            Slider(value: Binding(get: { model.pdfCrop[keyPath: keyPath] }, set: { amount in
                var value = model.pdfCrop; value[keyPath: keyPath] = amount; model.setPDFCrop(value)
            }), in: 0...0.30, step: 0.01)
            .accessibilityLabel(title + "裁边")
            .accessibilityValue("\(Int((model.pdfCrop[keyPath: keyPath] * 100).rounded()))%")
            .accessibilityIdentifier(identifier)
            .disabled(!model.pdfCrop.enabled)
        }
    }
}
