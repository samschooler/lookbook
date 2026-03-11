import SwiftUI
import UniformTypeIdentifiers

struct LUTPanel: View {
    @Bindable var pipeline: EditingPipeline
    @State private var showFileImporter = false
    @State private var showFolderImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUTs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if !pipeline.hasImage {
                        Text("Load a RAW file to see LUT previews")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 20)
                    }

                    LUTCard(
                        name: "None (Original)",
                        thumbnail: nil,
                        isSelected: pipeline.selectedLUTID == nil
                    )
                    .onTapGesture {
                        pipeline.selectedLUTID = nil
                    }

                    ForEach(pipeline.luts) { entry in
                        LUTCard(
                            name: entry.name,
                            thumbnail: entry.thumbnail,
                            isSelected: pipeline.selectedLUTID == entry.id
                        )
                        .onTapGesture {
                            pipeline.selectedLUTID = entry.id
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("+ File") {
                    showFileImporter = true
                }
                .buttonStyle(.borderless)

                Button("+ Folder") {
                    showFolderImporter = true
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Intensity")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.0f%%", pipeline.lutIntensity * 100))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $pipeline.lutIntensity, in: 0...1)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .disabled(pipeline.selectedLUT == nil)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        pipeline.addLUT(from: url)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    pipeline.addLUTsFromFolder(at: url)
                }
            }
        }
        .onAppear {
            pipeline.restoreBookmarkedFolders()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "cube" else {
                        return
                    }
                    Task { @MainActor in
                        pipeline.addLUT(from: url)
                    }
                }
            }
            return true
        }
    }
}

struct LUTCard: View {
    let name: String
    let thumbnail: CGImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let thumbnail = thumbnail {
                Image(decorative: thumbnail, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 60)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 60)
                    .cornerRadius(4)
            }

            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}
