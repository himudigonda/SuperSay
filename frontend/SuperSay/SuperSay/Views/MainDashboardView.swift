import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var audio: AudioService
    @Environment(\.colorScheme) var colorScheme
    
    // Local state
    @State private var localProgress: Double = 0
    @State private var isEditingSlider = false
    
    var body: some View {
        ZStack {
            // AMBIENCE
            Circle()
                .fill(vm.status == .speaking ? AnyShapeStyle(Color.cyan.opacity(colorScheme == .dark ? 0.12 : 0.08)) : AnyShapeStyle(Color.clear))
                .frame(width: 450, height: 450)
                .blur(radius: 90)
                .animation(.easeInOut(duration: 1.2), value: vm.status)
            
            VStack(spacing: 0) {
                headerSection
                Spacer()
                visualizerSection
                Spacer()
                footerSection
            }
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SUPER SAY")
                    .font(vm.appFont(size: 11, weight: .black))
                    .kerning(3)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    if vm.isBackendOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("SYSTEM ONLINE")
                            .font(vm.appFont(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                    } else if vm.isBackendInitializing {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 6, height: 6)
                        Text("INITIALIZING...")
                            .font(vm.appFont(size: 9, weight: .bold))
                            .foregroundStyle(.yellow)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("OFFLINE")
                            .font(vm.appFont(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .id(vm.isBackendOnline) // Force redraw when online status changes
                .id(vm.isBackendInitializing)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Text(vm.status.message.uppercased())
                    .font(vm.appFont(size: 10, weight: .bold))
                    .kerning(1.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.primary)
                    .background(Capsule().stroke(lineWidth: 1).foregroundStyle(.primary.opacity(0.1)))
                
                if audio.duration > 0 {
                    Button {
                        audio.exportToDesktop()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("SAVE")
                                .font(vm.appFont(size: 10, weight: .black))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Export Last Clip to Desktop (Cmd+Shift+M)")
                }
            }
        }
        .padding(40)
    }
    
    private var visualizerSection: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle().stroke(lineWidth: 1).foregroundStyle(.primary.opacity(0.05)).frame(width: 260, height: 260)
                
                Circle()
                    .stroke(lineWidth: 1.5)
                    .foregroundStyle(vm.status == .speaking ? AnyShapeStyle(Color.cyan.opacity(0.6)) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    .frame(width: 200, height: 200)
                    .scaleEffect(vm.status == .speaking ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: vm.status == .speaking)
                
                Image(systemName: "waveform")
                    .font(.system(size: 80, weight: .ultraLight))
                    .symbolEffect(.bounce, value: vm.status == .speaking)
            }
            
            VStack(spacing: 12) {
                Text(vm.currentVoiceDisplay.uppercased()) // Simplified display logic
                    .font(vm.appFont(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                
                let total = audio.duration
                let current = isEditingSlider ? localProgress * total : audio.currentTime
                Text(formatTime(current))
                    .font(vm.appFont(size: 32, weight: .thin))
                    .contentTransition(.numericText())
            }
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 30) {
            if vm.status == .speaking || vm.status == .paused || audio.duration > 0 {
                // Slider Logic (same as before but using 'audio' environment object)
                Slider(value: $localProgress, in: 0...1, onEditingChanged: { editing in
                    isEditingSlider = editing
                    audio.isDragging = editing
                    if !editing { audio.seek(to: localProgress) }
                })
                .onReceive(audio.$progress) { p in if !isEditingSlider { localProgress = p } }
                .padding(.horizontal, 100)
            }
            
            HStack(spacing: 60) {
                TransportButton(icon: "backward.fill", size: 20) { audio.seek(to: max(0, audio.progress - 0.1)) }
                
                Button { audio.togglePause() } label: {
                    ZStack {
                        Circle().fill(colorScheme == .dark ? Color.white : Color.black).frame(width: 72, height: 72)
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                    }
                }.buttonStyle(.plain)
                
                TransportButton(icon: "forward.fill", size: 20) { audio.seek(to: min(1, audio.progress + 0.1)) }
            }
        }
        .padding(.bottom, 40)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct TransportButton: View {
    @EnvironmentObject var vm: DashboardViewModel
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(vm.appFont(size: size, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
