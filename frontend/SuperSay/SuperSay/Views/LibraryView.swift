import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var pdf: PDFService
    @EnvironmentObject var vm: DashboardViewModel
    @State private var isHovering = false
    @State private var showFileImporter = false
    
    var body: some View {
        VStack {
            if pdf.isLoading {
                // LOADING STATE
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Parsing PDF...")
                        .font(vm.appFont(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if pdf.pages.isEmpty {
                // EMPTY / DROP STATE
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundStyle(isHovering ? .cyan : .secondary.opacity(0.3))
                            .frame(width: 160, height: 160)
                            .background(Circle().fill(isHovering ? Color.cyan.opacity(0.1) : Color.clear))
                        
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 50))
                            .foregroundStyle(isHovering ? .cyan : .secondary)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Audiobooks")
                            .font(vm.appFont(size: 20, weight: .bold))
                        
                        Text("Drop a PDF here or select a file to begin reading.")
                            .font(vm.appFont(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    if let error = pdf.errorMessage {
                        Text(error)
                            .font(vm.appFont(size: 12))
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                    
                    Button {
                        showFileImporter = true
                    } label: {
                        Text("Select PDF...")
                            .font(vm.appFont(size: 14, weight: .semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.cyan)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.pdf], isTargeted: $isHovering) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            DispatchQueue.main.async { pdf.load(url: url) }
                        }
                    }
                    return true
                }
                
            } else {
                // LIST STATE
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pdf.title)
                                .font(vm.appFont(size: 16, weight: .bold))
                                .lineLimit(1)
                            Text("\(pdf.pages.count) Pages")
                                .font(vm.appFont(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Open new file")
                        
                        Button {
                            pdf.pages = []
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Clear")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    
                    List(pdf.pages) { page in
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Text("\(page.index)")
                                    .font(vm.appFont(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.text)
                                    .font(vm.appFont(size: 13))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary.opacity(0.8))
                            }
                            
                            Spacer()
                            
                            Button {
                                Task { await vm.speakSelection(text: page.text) }
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        // NATIVE FILE PICKER
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    pdf.load(url: url)
                }
            case .failure(let error):
                print("Error selecting file: \(error.localizedDescription)")
            }
        }
    }
}
