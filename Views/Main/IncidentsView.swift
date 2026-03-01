import SwiftUI

struct IncidentsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: IncidentStore

    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<UUID> = []
    @State private var showClearAll = false

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ManageBar(
                    editMode: $editMode,
                    selectionCount: editMode == .active ? selection.count : 0,
                    onToggleEdit: { withAnimation { editMode = (editMode == .active ? .inactive : .active) } },
                    onDeleteSelected: {
                        store.delete(ids: selection)
                        selection.removeAll()
                        editMode = .inactive
                    },
                    onClearAll: { showClearAll = true }
                )
                Divider()

                if editMode == .active {
                    // Edit mode: selection enabled, no navigation
                    List(selection: $selection) {
                        ForEach(store.incidents) { inc in
                            IncidentRow(incident: inc, now: now)
                        }
                        .onDelete { offsets in store.delete(at: offsets) }
                    }
                } else {
                    // Normal mode: no selection binding → NavigationLink works
                    List {
                        ForEach(store.incidents) { inc in
                            if inc.isReadyToOpen(now: now) {
                                NavigationLink(value: inc.id) {
                                    IncidentRow(incident: inc, now: now)
                                        .contentShape(Rectangle()) // full-row hit area
                                }
                            } else {
                                IncidentRow(incident: inc, now: now)
                            }
                        }
                        .onDelete { offsets in store.delete(at: offsets) }
                    }
                }
            }
            .navigationTitle("Incidents")
            .navigationDestination(for: UUID.self) { id in
                IncidentDetail(incidentID: id)  // your existing player view
            }
            .confirmationDialog("Delete all incidents?",
                                isPresented: $showClearAll,
                                titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    store.deleteAll()
                    selection.removeAll()
                    editMode = .inactive
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: editMode) { _, newValue in
            if newValue != .active { selection.removeAll() }  // ensure taps navigate again
        }
    }
}




// MARK: - Row
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
                    // Ready state → show time, date (day month year), location
                    Text(incident.formattedDateTime).bold()
                    Text(incident.formattedLocation)
                        .font(.caption).foregroundColor(.secondary)
                    if !incident.isComplete {
                        Text("Incomplete (stalled)")
                            .font(.caption2).foregroundColor(.orange)
                    }
                } else {
                    // Waiting state → mirrored text (also in overlay), but keep a small line here for accessibility
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

// MARK: - Detail Viewer
private enum PlayerMode: String, CaseIterable, Identifiable { case loopForward = "Loop", frameByFrame = "Frame-by-frame"; var id: String { rawValue } }

struct IncidentDetail: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var app: AppState
    let incidentID: UUID

    @State private var mode: PlayerMode = .loopForward
    @State private var isPlaying: Bool = true
    @State private var frameIndex: Int = 0
    @State private var speedX: Double = 1.0  // 0.25× … 3×

    private var baseFPS: Double { 30 }       // default 30 FPS
    private var fps: Double { max(1, min(90, baseFPS * speedX)) }

    private var incident: Incident? { ble.incidentStore.incidents.first { $0.id == incidentID } }
    private var images: [UIImage] { (incident?.framesPNG ?? []).compactMap { UIImage(data: $0) } }

    var body: some View {
        VStack(spacing: 12) {
            // Mode toggle
            Picker("Mode", selection: $mode) {
                ForEach(PlayerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)

            ZStack {
                if images.indices.contains(frameIndex) {
                    ZoomableImagePlayer(image: images[frameIndex])
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)).overlay(Text("No frames yet"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 360)

            if mode == .loopForward {
                // Speed slider (no FPS slider, just speed multiple)
                HStack {
                    Image(systemName: "tortoise")
                    Slider(value: $speedX, in: 0.25...3.0, step: 0.05)
                    Image(systemName: "hare")
                }
                .padding(.horizontal)
            } else {
                // Frame-by-frame controls (no scrubber slider)
                HStack(spacing: 16) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left").imageScale(.large) }
                    Text("\(frameIndex + 1) / \(max(1, images.count))").monospacedDigit()
                    Button { step(+1) } label: { Image(systemName: "chevron.right").imageScale(.large) }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { idx in
                            Image(uiImage: images[idx])
                                .resizable().scaledToFill()
                                .frame(width: 48, height: 48).clipped()
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(idx == frameIndex ? Color.accentColor : .clear, lineWidth: 2))
                                .onTapGesture { frameIndex = idx }
                        }
                    }.padding(.horizontal)
                }
            }

            HStack {
                ShareButton(images: images, complete: incident?.isComplete ?? false, id: incidentID)
                Spacer()
                Toggle(isOn: $isPlaying) { Text(mode == .loopForward ? "Playing" : "Pause on select").font(.caption) }
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .disabled(mode == .frameByFrame) // frame‑by‑frame doesn’t auto‑advance
            }
        }
        .padding()
        .navigationTitle("Incident")
        .onChange(of: images.count) { _, _ in frameIndex = min(frameIndex, max(0, images.count - 1)) }
        .onReceive(Timer.publish(every: max(0.02, 1.0 / fps), on: .main, in: .common).autoconnect()) { _ in
            guard mode == .loopForward, isPlaying, !images.isEmpty else { return }
            frameIndex = (frameIndex + 1) % images.count // forward‑only loop
        }
        .onAppear { app.isPagingDisabled = true }
        .onDisappear { app.isPagingDisabled = false }
    }

    private func step(_ delta: Int) {
        guard !images.isEmpty else { return }
        frameIndex = (frameIndex + delta + images.count) % images.count
    }
}

// MARK: - Share (fixed: item-based sheet to avoid first-tap blank)
private struct SharePayload: Identifiable { let id = UUID(); let items: [Any] }

private struct ShareButton: View {
    let images: [UIImage]
    let complete: Bool
    let id: UUID

    @State private var shareItem: SharePayload? = nil

    var body: some View {
        Button {
            // Build share items BEFORE presenting to avoid blank sheet
            var items: [Any] = []

            if !images.isEmpty {
                if let gif = GIFEncoder.makeGIF(from: images, fps: 30) {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).gif")
                    if (try? gif.write(to: url)) != nil {
                        items = [url]
                    }
                    else {
                        items = [images[0]]
                    }
                }
                else {
                    items = [images[0]]
                }
            }

            if !items.isEmpty {
            shareItem = SharePayload(items: items)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .disabled(images.isEmpty)
        .sheet(item: $shareItem) { payload in
        ActivityView(activityItems: payload.items)
        }
    }
}


// MARK: - Small UI bits you already had (kept lightweight)
private struct ManageBar: View {
    @Binding var editMode: EditMode
    let selectionCount: Int
    let onToggleEdit: () -> Void
    let onDeleteSelected: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack {
            Button(action: onClearAll) { Label("Clear All", systemImage: "trash") }.buttonStyle(.bordered)
            if selectionCount > 0 {
                Button(action: onDeleteSelected) { Text("Delete (\(selectionCount))") }.buttonStyle(.bordered)
            }
            Spacer()
            Button(action: onToggleEdit) { Text(editMode == .active ? "Done" : "Select") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.ultraThinMaterial)
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

    // Configuration
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            // Image is aspectFit in the available rect; we then apply scale+offset
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
                .clipped() // avoid bleed
                .contentShape(Rectangle())
        }
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // relative to lastScale to allow smooth pinch
                let delta = value / lastScale
                var newScale = scale * delta
                newScale = max(minScale, min(maxScale, newScale))
                scale = newScale
                lastScale = value
                offset = clamped(offset: accumulatedOffset, in: size)
            }
            .onEnded { _ in
                // reset baseline
                lastScale = 1.0
                // Clamp after end to ensure inside bounds
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
        // Ensure within bounds after changes
        offset = clamped(offset: offset, in: containerSize)
        accumulatedOffset = offset
    }

    private func clamped(offset: CGSize, in containerSize: CGSize) -> CGSize {
        // Compute content size after aspectFit and scaling
        let fitted = fittedImageSize(for: image.size, in: containerSize)
        let contentW = fitted.width * scale
        let contentH = fitted.height * scale

        // If content smaller than container on one axis, no panning on that axis
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
