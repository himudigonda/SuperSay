import SwiftUI

struct SuperSayWindow: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var history: HistoryManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.colorScheme) var colorScheme
    // @State private var selectedTab: String? = "home" // Managed by VM now
    
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // APP BRANDING HEADER
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.cyan.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SuperSay")
                            .font(vm.appFont(size: 16, weight: .bold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                
                List(selection: $vm.selectedTab) {
                    Section(header: Text("Library").font(vm.appFont(size: 11, weight: .bold))) {
                        NavigationLink(value: "home") { 
                            Label("Now Playing", systemImage: "play.circle.fill")
                                .font(vm.appFont(size: 13))
                        }
                        NavigationLink(value: "library") { 
                            Label("Audiobooks", systemImage: "book.closed.fill")
                                .font(vm.appFont(size: 13))
                        }
                        NavigationLink(value: "history") { 
                            Label("The Vault", systemImage: "clock.arrow.circlepath")
                                .font(vm.appFont(size: 13))
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                
                Spacer()
                
                // SYSTEM / PREFERENCES AT BOTTOM
                VStack(spacing: 8) {
                    Divider().padding(.horizontal, 20).opacity(0.3)
                    
                    Button {
                        vm.selectedTab = "preferences"
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Preferences")
                                .font(vm.appFont(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(vm.selectedTab == "preferences" ? Color.cyan.opacity(0.15) : Color.clear)
                        .foregroundStyle(vm.selectedTab == "preferences" ? .cyan : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                
                // DEVELOPER ATTRIBUTION
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEVELOPED BY")
                        .font(vm.appFont(size: 8, weight: .black))
                        .kerning(1)
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text("Himansh Mudigonda")
                        .font(vm.appFont(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 18) {
                        Link(destination: URL(string: "https://github.com/himudigonda")!) {
                            Image("github") // Explicit Asset
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 36)
                        }
                        .help("GitHub")
                        
                        Link(destination: URL(string: "https://www.linkedin.com/in/himudigonda")!) {
                            Image("linkedin") // Explicit Asset
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 36)
                        }
                        .help("LinkedIn")
                        
                        Link(destination: URL(string: "https://himudigonda.me")!) {
                            Image(systemName: "globe") // System Icon
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .padding(4)
                        }
                        .help("Website")
                    }
                    .foregroundStyle(.cyan)
                }
                .padding(24)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack(alignment: .bottom) {
                // MAIN CONTENT
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // FLOATING MINI PLAYER (Global) - Hide when on main dashboard to avoid duplicate bars
                if (vm.status == .speaking || vm.status == .paused) && vm.selectedTab != "home" {
                    miniPlayerHUD
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(adaptiveBackdrop)
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(vm.appTheme == "system" ? nil : (vm.appTheme == "dark" ? .dark : .light))
        .sheet(isPresented: $vm.showUpdateSheet) {
            UpdateView()
                .environmentObject(vm)
        }
        .onAppear {
            // Background check for updates on startup
            vm.checkForUpdates(manual: false)
            
            // Prepare backend if needed
            Task {
                await launchManager.prepare()
            }
        }
        .overlay {
            if !launchManager.isReady {
                ZStack {
                    adaptiveBackdrop
                    
                    VStack(spacing: 20) {
                        if let error = launchManager.error {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)
                            Text("Launch Failed").font(vm.appFont(size: 18, weight: .bold))
                            Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                            
                            Button("Try Again") {
                                launchManager.error = nil
                                Task { await launchManager.prepare() }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            ProgressView()
                            Text("Initializing SuperSay...").font(vm.appFont(size: 16, weight: .medium))
                        }
                    }
                }
            }
        }
        .animation(.default, value: launchManager.isReady)
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch vm.selectedTab {
        case "home": MainDashboardView()
        case "library": LibraryView()
        case "history": VaultView()
        case "preferences": PreferencesView()
        default: MainDashboardView()
        }
    }
    
    private var miniPlayerHUD: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.status == .speaking ? "SPEAKING" : "PAUSED")
                    .font(vm.appFont(size: 8, weight: .black))
                    .foregroundStyle(.cyan)
                Text(history.history.first?.text ?? "Reading...")
                    .font(vm.appFont(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 250, alignment: .leading)
            
            ProgressView(value: audio.progress)
                .tint(.cyan)
                .scaleEffect(x: 1, y: 0.5)
            
            HStack(spacing: 12) {
                Button { vm.togglePlayback() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { audio.stop() } label: {
                    Image(systemName: "stop.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.title3)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 15)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding(20)
        .shadow(color: .black.opacity(0.1), radius: 10)
        .animation(.spring(), value: audio.progress)
    }

    private var adaptiveBackdrop: some View {
        Group {
            if vm.appTheme == "dark" || (vm.appTheme == "system" && colorScheme == .dark) {
                LinearGradient(colors: [Color.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(white: 0.98), Color(white: 0.92)], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}
