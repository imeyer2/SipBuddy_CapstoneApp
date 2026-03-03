// IncidentsView.swift — improved UX with swipe actions, animations, and haptics
import SwiftUI
import UIKit
import Combine

struct IncidentsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: IncidentStore

    @State private var showClearAll = false
    @State private var pendingDeleteID: UUID? = nil
    @State private var appearAnimation = false

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TopBar: App menu, name, connection, battery
                TopBar()

                // ManageBar: Keep Clear All only (no selection delete)
                if !store.incidents.isEmpty {
                    ManageBar(onClearAll: { showClearAll = true })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Divider()

                // Content area
                if store.incidents.isEmpty {
                    // Empty state with animation
                    EmptyIncidentsView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // List with swipe-to-delete
                    List {
                        ForEach(Array(store.incidents.enumerated()), id: \.element.id) { index, inc in
                            if inc.isReadyToOpen(now: now) {
                                NavigationLink(value: inc.id) {
                                    IncidentRow(incident: inc, now: now)
                                        .contentShape(Rectangle())
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .padding(.vertical, 4)
                                )
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(x: appearAnimation ? 0 : 20)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: appearAnimation)
                            } else {
                                IncidentRow(incident: inc, now: now)
                                    .contentShape(Rectangle())
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                            .padding(.vertical, 4)
                                    )
                                    .opacity(appearAnimation ? 1 : 0)
                                    .offset(x: appearAnimation ? 0 : 20)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: appearAnimation)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        // Haptic on pull-to-refresh
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // Brief delay to show refresh indicator
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
            .background(AppGradient.pageBackground.ignoresSafeArea())
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.incidents.isEmpty)
            // Navigation and dialogs
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .navigationDestination(for: UUID.self) { id in
                IncidentDetail(incidentID: id)
            }
            // Confirm single-clip delete (from long-press - keeping as fallback)
            .confirmationDialog(
                "Delete this clip?",
                isPresented: Binding(
                    get: { pendingDeleteID != nil },
                    set: { if !$0 { pendingDeleteID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteID {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.delete(ids: Set([id]))
                        }
                        pendingDeleteID = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingDeleteID = nil }
            }
            // Clear all dialog (bulk action retained)
            .confirmationDialog(
                "Delete all incidents?",
                isPresented: $showClearAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        store.deleteAll()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Timer and housekeeping
        .onReceive(ticker) { now = $0 }
        .onAppear {
            UIApplication.shared.applicationIconBadgeNumber = 0
            PostHogService.shared.screen("Incidents")
            // Stagger row animations on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Empty State View
private struct EmptyIncidentsView: View {
    @State private var floatAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .offset(y: floatAnimation ? -4 : 4)
            }
            
            Text("All Clear!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No incidents detected.\nYour drinks have been safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                floatAnimation = true
            }
        }
    }
}


// MARK: - Row (unchanged visuals)
private struct IncidentRow: View {
    let incident: Incident
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let img = incident.previewImage {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64).clipped()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "photo"))
                }

                if !incident.isReadyToOpen(now: now) {
                    VisualEffectBlur()
                        .cornerRadius(8)
                        .overlay(
                            VStack(spacing: 4) {
                                Text("Loading…").font(.caption).bold()
                                Text("Please Wait").font(.caption2)
                                if let s = incident.estimatedRemainingSeconds(now: now) {
                                    Text("Estimated Wait: \(incident.mmss(s))")
                                        .font(.caption2).monospacedDigit()
                                } else {
                                    Text("Estimated Wait: —:—").font(.caption2)
                                }
                            }
                                .padding(6)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if incident.isReadyToOpen(now: now) {
                    Text(incident.formattedDateTime).bold()
                    Text(incident.formattedLocation)
                        .font(.caption).foregroundColor(.secondary)
                    if !incident.isComplete {
                        Text("Incomplete (stalled)")
                            .font(.caption2).foregroundColor(.orange)
                    }
                } else {
                    Text("Loading…").bold()
                    Text("Please Wait").font(.caption).foregroundColor(.secondary)
                    if let s = incident.estimatedRemainingSeconds(now: now) {
                        Text("Estimated Wait: \(incident.mmss(s))")
                            .font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Viewer (Instagram Reels-style)
private enum PlayerMode: String, CaseIterable, Identifiable { 
    case reelStyle = "Reel"
    case frameByFrame = "Frames"
    var id: String { rawValue } 
}

struct IncidentDetail: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: IncidentStore
    @Environment(\.dismiss) private var dismiss
    let incidentID: UUID

    @State private var mode: PlayerMode = .reelStyle
    @State private var isPlaying: Bool = true
    @State private var frameIndex: Int = 0
    @State private var speedX: Double = 1.0
    @State private var isHoldingForSpeed: Bool = false
    @State private var showDeleteConfirm = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer? = nil

    private var baseFPS: Double { 30 }
    private var currentSpeed: Double { isHoldingForSpeed ? 2.0 : speedX }
    private var fps: Double { max(1, min(90, baseFPS * currentSpeed)) }

    private var incident: Incident? { ble.incidentStore.incidents.first { $0.id == incidentID } }
    private var images: [UIImage] { (incident?.framesPNG ?? []).compactMap { UIImage(data: $0) } }
    
    private var progress: Double {
        guard images.count > 1 else { return 0 }
        return Double(frameIndex) / Double(images.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Mode picker at top
                    Picker("Mode", selection: $mode) {
                        ForEach(PlayerMode.allCases) { m in 
                            Text(m.rawValue).tag(m) 
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: mode) { _, newMode in
                        if newMode == .reelStyle {
                            isPlaying = true
                        }
                    }
                    
                    if mode == .reelStyle {
                        // Reel-style player
                        reelStylePlayer(geo: geo)
                    } else {
                        // Frame-by-frame mode
                        frameByFramePlayer(geo: geo)
                    }
                }
            }
        }
        .navigationTitle("Incident")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    ShareButton(images: images, complete: incident?.isComplete ?? false, id: incidentID, iconOnly: true)
                    
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .alert("Delete this clip?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.delete(ids: Set([incidentID]))
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: images.count) { _, _ in 
            frameIndex = min(frameIndex, max(0, images.count - 1)) 
        }
        .onReceive(Timer.publish(every: max(0.02, 1.0 / fps), on: .main, in: .common).autoconnect()) { _ in
            guard mode == .reelStyle, isPlaying, !images.isEmpty else { return }
            frameIndex = (frameIndex + 1) % images.count
        }
        .onAppear {
            app.isPagingDisabled = true
            PostHogService.shared.trackIncidentViewed(
                incidentId: incidentID.uuidString,
                hasMedia: !images.isEmpty
            )
            startControlsTimer()
        }
        .onDisappear { 
            app.isPagingDisabled = false 
            controlsTimer?.invalidate()
        }
    }
    
    // MARK: - Reel Style Player
    @ViewBuilder
    private func reelStylePlayer(geo: GeometryProxy) -> some View {
        ZStack {
            // Main image with tap/hold gestures applied directly
            Group {
                if images.indices.contains(frameIndex) {
                    Image(uiImage: images[frameIndex])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No frames yet")
                            .foregroundColor(.gray)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPlaying.toggle()
                showControls = true
                startControlsTimer()
            }
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                if pressing {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isHoldingForSpeed = true
                    showControls = true
                } else {
                    isHoldingForSpeed = false
                    startControlsTimer()
                }
            }, perform: {})
            
            // Play/pause indicator (shows briefly on tap)
            if showControls && !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
            
            // 2x speed indicator
            if isHoldingForSpeed {
                VStack {
                    HStack {
                        Spacer()
                        Text("2x")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.3)))
                            .padding()
                    }
                    Spacer()
                }
            }
            
            // Bottom controls overlay
            VStack {
                Spacer()
                
                VStack(spacing: 12) {
                    // Progress bar
                    ReelProgressBar(progress: progress, frameIndex: frameIndex, totalFrames: images.count)
                        .onTapGesture { location in
                            // Allow scrubbing by tapping progress bar
                            guard images.count > 1 else { return }
                            let percent = location.x / (geo.size.width - 32)
                            let newIndex = Int(percent * Double(images.count - 1))
                            frameIndex = max(0, min(images.count - 1, newIndex))
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    
                    // Speed slider (when controls visible)
                    if showControls {
                        HStack(spacing: 8) {
                            Image(systemName: "tortoise.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                            
                            Slider(value: $speedX, in: 0.25...3.0, step: 0.05)
                                .tint(.white)
                            
                            Image(systemName: "hare.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                            
                            Text(String(format: "%.1fx", speedX))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white)
                                .frame(width: 40)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Hint text
                    if showControls && !isHoldingForSpeed {
                        Text("Tap to \(isPlaying ? "pause" : "play") • Hold for 2x speed")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.15), value: isHoldingForSpeed)
    }
    
    // MARK: - Frame by Frame Player
    @ViewBuilder
    private func frameByFramePlayer(geo: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            // Main image with zoom
            ZStack {
                if images.indices.contains(frameIndex) {
                    ZoomableImagePlayer(image: images[frameIndex])
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Text("No frames yet").foregroundColor(.gray))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: geo.size.height * 0.5)
            .padding(.horizontal)
            
            // Frame navigation
            HStack(spacing: 24) {
                Button { step(-1) } label: { 
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                
                Text("\(frameIndex + 1) / \(max(1, images.count))")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.white)
                    .frame(minWidth: 80)
                
                Button { step(+1) } label: { 
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
            }
            
            // Thumbnail strip
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images.indices, id: \.self) { idx in
                            Image(uiImage: images[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(idx == frameIndex ? Color.accentColor : .clear, lineWidth: 3)
                                )
                                .shadow(color: idx == frameIndex ? .accentColor.opacity(0.5) : .clear, radius: 4)
                                .onTapGesture { 
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    frameIndex = idx 
                                }
                                .id(idx)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: frameIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 16)
    }
    
    // MARK: - Helpers
    private func step(_ delta: Int) {
        guard !images.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        frameIndex = (frameIndex + delta + images.count) % images.count
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if isPlaying && !isHoldingForSpeed {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Progress Bar Component
private struct ReelProgressBar: View {
    let progress: Double
    let frameIndex: Int
    let totalFrames: Int
    
    var body: some View {
        VStack(spacing: 4) {
            // Progress track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            
            // Frame counter
            HStack {
                Text("Frame \(frameIndex + 1) of \(totalFrames)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Share
private struct SharePayload: Identifiable { let id = UUID(); let items: [Any] }

private struct ShareButton: View {
    let images: [UIImage]
    let complete: Bool
    let id: UUID
    var iconOnly: Bool = false

    @State private var shareItem: SharePayload? = nil
    
    private func performShare() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var items: [Any] = []
        if !images.isEmpty {
            if let gif = GIFEncoder.makeGIF(from: images, fps: 30) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).gif")
                if (try? gif.write(to: url)) != nil {
                    items = [url]
                } else {
                    items = [images[0]]
                }
            } else {
                items = [images[0]]
            }
        }
        if !items.isEmpty { shareItem = SharePayload(items: items) }
    }

    var body: some View {
        Group {
            if iconOnly {
                Button { performShare() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                Button { performShare() } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .disabled(images.isEmpty)
        .sheet(item: $shareItem) { payload in
            ActivityView(activityItems: payload.items)
        }
    }
}

// MARK: - Manage bar (Clear All only)
private struct ManageBar: View {
    let onClearAll: () -> Void

    var body: some View {
        HStack {
            Button(action: onClearAll) { Label("Clear All", systemImage: "trash") }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Zoomable image player (pinch + pan + double-tap)
private struct ZoomableImagePlayer: View {
    let image: UIImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .center)
                .offset(offset)
                .gesture(dragGesture(size: size))
                .simultaneousGesture(magnificationGesture(size: size))
                .onTapGesture(count: 2) { withAnimation(.spring()) { toggleDoubleTapZoom(containerSize: size) } }
                .animation(.interactiveSpring(), value: scale)
                .animation(.interactiveSpring(), value: offset)
                .clipped()
                .contentShape(Rectangle())
        }
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                var newScale = scale * delta
                newScale = max(minScale, min(maxScale, newScale))
                scale = newScale
                lastScale = value
                offset = clamped(offset: accumulatedOffset, in: size)
            }
            .onEnded { _ in
                lastScale = 1.0
                offset = clamped(offset: offset, in: size)
                accumulatedOffset = offset
            }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(width: accumulatedOffset.width + value.translation.width,
                                      height: accumulatedOffset.height + value.translation.height)
                offset = clamped(offset: proposed, in: size)
            }
            .onEnded { value in
                let proposed = CGSize(width: accumulatedOffset.width + value.translation.width,
                                      height: accumulatedOffset.height + value.translation.height)
                let clampedVal = clamped(offset: proposed, in: size)
                offset = clampedVal
                accumulatedOffset = clampedVal
            }
    }

    private func toggleDoubleTapZoom(containerSize: CGSize) {
        if scale <= 1.01 {
            scale = 2.0
        } else {
            scale = 1.0
            offset = .zero
            accumulatedOffset = .zero
        }
        offset = clamped(offset: offset, in: containerSize)
        accumulatedOffset = offset
    }

    private func clamped(offset: CGSize, in containerSize: CGSize) -> CGSize {
        let fitted = fittedImageSize(for: image.size, in: containerSize)
        let contentW = fitted.width * scale
        let contentH = fitted.height * scale

        let maxX: CGFloat = max(0, (contentW - containerSize.width) / 2)
        let maxY: CGFloat = max(0, (contentH - containerSize.height) / 2)

        let clampedX = max(-maxX, min(maxX, offset.width))
        let clampedY = max(-maxY, min(maxY, offset.height))
        return CGSize(width: clampedX, height: clampedY)
    }

    private func fittedImageSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

