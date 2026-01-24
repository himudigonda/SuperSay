import SwiftUI

struct SuperSayWindow: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var persistence: PersistenceService
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: String? = "home"
    
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
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                
                List(selection: $selectedTab) {
                    Section("Library") {
                        NavigationLink(value: "home") { Label("Now Playing", systemImage: "play.circle.fill") }
                        NavigationLink(value: "library") { Label("Audiobooks", systemImage: "book.closed.fill") }
                        NavigationLink(value: "history") { Label("The Vault", systemImage: "clock.arrow.circlepath") }
                    }
                    
                    Section("System") {
                        NavigationLink(value: "settings") { Label("The Lab", systemImage: "terminal.fill") }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                
                Spacer()
                
                // DEVELOPER ATTRIBUTION
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEVELOPED BY")
                        .font(.system(size: 8, weight: .black))
                        .kerning(1)
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text("Himansh Mudigonda")
                        .font(.system(size: 11, weight: .bold))
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
                    }
                    .foregroundStyle(.cyan)
                }
                .padding(24)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            ZStack(alignment: .bottom) {
                // MAIN CONTENT
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // FLOATING MINI PLAYER (Global) - Hide when on main dashboard to avoid duplicate bars
                if (dashboardVM.status == .speaking || dashboardVM.status == .paused) && selectedTab != "home" {
                    miniPlayerHUD
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(adaptiveBackdrop)
        }
        .frame(minWidth: 1000, minHeight: 750)
        .preferredColorScheme(settings.appTheme == "system" ? nil : (settings.appTheme == "dark" ? .dark : .light))
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case "home": MainDashboardView()
        case "library": LibraryView()
        case "history": VaultView()
        case "settings": LabView()
        default: MainDashboardView()
        }
    }
    
    private var miniPlayerHUD: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dashboardVM.status == .speaking ? "SPEAKING" : "PAUSED")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.cyan)
                Text(persistence.history.first?.text ?? "Reading...")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 250, alignment: .leading)
            
            ProgressView(value: audio.progress)
                .tint(.cyan)
                .scaleEffect(x: 1, y: 0.5)
            
            HStack(spacing: 12) {
                Button { audio.togglePause() } label: {
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
            if settings.appTheme == "dark" || (settings.appTheme == "system" && colorScheme == .dark) {
                LinearGradient(colors: [Color.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(white: 0.98), Color(white: 0.92)], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}
