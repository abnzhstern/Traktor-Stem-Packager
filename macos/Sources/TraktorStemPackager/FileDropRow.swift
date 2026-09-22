import SwiftUI
import UniformTypeIdentifiers

struct FileDropRow: View {
    let role: AudioRole
    @Binding var displayName: String
    let url: URL?
    let isValidated: Bool
    let hasProblem: Bool
    let select: (URL) -> Void
    let clear: () -> Void

    @State private var importing = false
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if role == .master {
                    Text("Master").font(.system(size: 13, weight: .semibold))
                } else {
                    TextField(role.rawValue, text: $displayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .help("Editable display name. The internal stem role remains \(role.rawValue).")
                }
            }
            .foregroundStyle(role == .master ? Color.white.opacity(0.86) : Color.black.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(width: 116, height: 42, alignment: .leading)
            .background(role.color)

            Button {
                importing = true
            } label: {
                HStack {
                    Image(systemName: url == nil ? "plus.circle" : "checkmark.circle.fill")
                        .foregroundStyle(indicatorColor)
                    Text(url?.lastPathComponent ?? "Drop audio file or click to choose")
                        .lineLimit(1)
                        .foregroundStyle(url == nil ? Color.white.opacity(0.48) : Color.white.opacity(0.88))
                    Spacer()
                    if url != nil {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.4))
                            .onTapGesture(perform: clear)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(rowBackground)
                .overlay(Rectangle().stroke(rowBorder, lineWidth: hasProblem || url == nil ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let first = urls.first { select(first) }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    if let object { DispatchQueue.main.async { select(object) } }
                }
                return true
            }
            .onDrag {
                guard let url else { return NSItemProvider() }
                return NSItemProvider(object: url as NSURL)
            }
        }
    }

    private var indicatorColor: Color {
        if hasProblem { return .red }
        if isValidated { return .green }
        if url == nil { return role.color.opacity(0.9) }
        return Color.white.opacity(0.55)
    }

    private var rowBackground: Color {
        if targeted { return role.color.opacity(0.18) }
        if hasProblem { return Color.red.opacity(0.10) }
        if isValidated { return Color.green.opacity(0.06) }
        if url == nil { return role.color.opacity(0.055) }
        return Color.white.opacity(0.055)
    }

    private var rowBorder: Color {
        if targeted { return role.color }
        if hasProblem { return .red }
        if isValidated { return Color.green.opacity(0.55) }
        if url == nil { return role.color.opacity(0.55) }
        return Color.white.opacity(0.09)
    }
}
