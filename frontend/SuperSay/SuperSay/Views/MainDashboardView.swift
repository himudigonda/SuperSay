import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @Environment(\.colorScheme) var colorScheme
    
    // Local state for the slider to make it feel instant during drag
    @State private var localProgress: Double = 0
    @State private var isEditingSlider = false
    
    var body: some View {
        ZStack {
            // THE GLOWING AMBIENCE (CENTRAL)
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
                
                // FOOTER: CONTROLS & SMOOTH SEEKER
                VStack(spacing: 30) {
                    if vm.status == .speaking || vm.status == .paused || vm.status == .thinking || vm.audio.isPlaying {
                        VStack(spacing: 8) {
                            // --- THE SMOOTH SEEKER ---
                            Slider(value: $localProgress, in: 0...1, onEditingChanged: { editing in
                                isEditingSlider = editing
                                vm.audio.isDragging = editing
                                if !editing {
                                    vm.audio.seek(to: localProgress)
                                }
                            })
                            .tint(.cyan)
                            .controlSize(.small)
                            // This ensures the slider updates its position from the engine 
                            // ONLY when the user isn't touching it
                            .onReceive(vm.audio.$progress) { newProgress in
                                if !isEditingSlider {
                                    localProgress = newProgress
                                }
                            }
                            
                            HStack {
                                let total = vm.audio.duration
                                let current = isEditingSlider ? localProgress * total : vm.audio.currentTime
                                
                                Text(formatTime(current))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                
                                Spacer()
                                
                                Text("-" + formatTime(max(0, total - current)))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 100)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        // Placeholder to maintain layout
                        VStack(spacing: 8) {
                            Slider(value: .constant(0), in: 0...1).disabled(true).controlSize(.small)
                            HStack {
                                Text("0:00")
                                Spacer()
                                Text("-0:00")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.3))
                        }
                        .padding(.horizontal, 100)
                    }
                    
                    transportControls
                }
                .padding(.bottom, 60)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SUPER SAY")
                    .font(.system(size: 11, weight: .black))
                    .kerning(3)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isOnline ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    
                    Text(vm.isOnline ? "SYSTEM ONLINE" : "OFFLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(vm.isOnline ? .green : .red)
                }
            }
            
            Spacer()
            
            Text(vm.status.message.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.primary)
                .background(Capsule().stroke(lineWidth: 1).foregroundStyle(.primary.opacity(0.1)))
        }
        .padding(40)
    }
    
    private var visualizerSection: some View {
        VStack(spacing: 40) {
            ZStack {
                // The Outer Orbit
                Circle()
                    .stroke(lineWidth: 1)
                    .foregroundStyle(.primary.opacity(0.05))
                    .frame(width: 300, height: 300)
                
                // The Dynamic Pulse
                Circle()
                    .stroke(lineWidth: 1.5)
                    .foregroundStyle(vm.status == .speaking ? AnyShapeStyle(Color.cyan.opacity(0.6)) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    .frame(width: 240, height: 240)
                    .scaleEffect(vm.status == .speaking ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: vm.status == .speaking)
                
                // THE WAVEFORM ICON
                Image(systemName: "waveform")
                    .font(.system(size: 100, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: vm.status == .speaking ? [.cyan, .purple] : [.gray, .primary.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(.bounce, value: vm.status == .speaking)
                    .shadow(color: vm.status == .speaking ? .cyan.opacity(0.4) : .clear, radius: 30)
            }
            
            VStack(spacing: 12) {
                Text(vm.currentVoiceDisplay)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .kerning(2)
                
                let total = vm.audio.duration
                let current = isEditingSlider ? localProgress * total : vm.audio.currentTime
                
                if vm.status == .speaking || vm.status == .paused || vm.status == .thinking || vm.audio.isPlaying {
                    Text(formatTime(current))
                        .font(.system(size: 32, weight: .thin, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                } else {
                    Text("0:00")
                    .font(.system(size: 32, weight: .thin, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
    }
    
    private var transportControls: some View {
        HStack(spacing: 60) {
            TransportButton(icon: "backward.fill", size: 20) { 
                vm.audio.seek(to: max(0, vm.audio.progress - 0.1)) 
            }
            
            Button {
                vm.audio.togglePause()
            } label: {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 72, height: 72)
                        .shadow(color: .cyan.opacity(0.4), radius: 20)
                    
                    Image(systemName: vm.audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
            }
            .buttonStyle(.plain)
            
            TransportButton(icon: "forward.fill", size: 20) { 
                vm.audio.seek(to: min(1, vm.audio.progress + 0.1)) 
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct TransportButton: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let size: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
