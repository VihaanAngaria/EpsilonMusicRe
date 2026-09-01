import SwiftUI

// MARK: - Equalizer screen (AxionEqScreen.kt parity)

struct EqualizerView: View {
    @EnvironmentObject private var eq: EqualizerEngine
    @Environment(\.epsPalette) private var pal

    @State private var showSaveAlert = false
    @State private var presetName = ""

    private let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Equalizer", showBack: true) {
                    Button {
                        saveCustomPreset()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(pal.textSecondary)
                    }
                }

                enableCard
                if eq.enabled {
                    modeCard
                    if eq.mode == 0 {
                        CircularEqControl()
                            .padding(.vertical, 8)
                    } else {
                        advancedBands
                    }
                    presetsSection
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .alert("Save preset", isPresented: $showSaveAlert) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    eq.saveCustomPreset(named: name)
                }
                presetName = ""
            }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("Saves the current band values as a custom preset.")
        }
    }

    private var enableCard: some View {
        SettingsGroup(title: "") {
            SettingsToggleRow(icon: "slider.horizontal.3",
                              title: "Professional audio processing",
                              subtitle: "10-band parametric EQ with biquad filters, applied to playback in real time",
                              isOn: Binding(
                                get: { eq.enabled },
                                set: { eq.enabled = $0 }))
        }
    }

    private var modeCard: some View {
        SettingsGroup(title: "Mode") {
            HStack {
                SegmentedChips(options: ["Simple", "Advanced"], selection: Binding(
                    get: { eq.mode },
                    set: { eq.mode = $0 }))
                Spacer()
                Button {
                    eq.bands = Array(repeating: 0, count: 10)
                    eq.activePresetId = "epsilon-signature-flat"
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pal.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private var advancedBands: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<10, id: \.self) { index in
                    EqBandSlider(value: Binding(
                        get: { Double(eq.bands[index]) },
                        set: { eq.bands[index] = Int($0) }))
                }
            }
            HStack(spacing: 6) {
                ForEach(bandLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(pal.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Preamp: \(String(format: "%.1f", eq.preampDb)) dB")
                .font(.system(size: 12))
                .foregroundStyle(pal.textSecondary)
                .padding(.horizontal, 4)
            Slider(value: Binding(
                get: { eq.preampDb },
                set: { eq.preampDb = $0 }), in: -12...12)
                .tint(pal.accent)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let groups = Dictionary(grouping: EQProfile.presets + eq.customProfiles, by: \.groupName)
            let ordered = ["Epsilon Signature", "Dolby Atmos", "Dirac Audio", "Custom"]
            ForEach(ordered, id: \.self) { groupName in
                if let group = groups[groupName], !group.isEmpty {
                    SectionHeader(title: groupName)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group) { preset in
                                presetChip(preset)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: EQProfile) -> some View {
        let isActive = eq.activePresetId == preset.id
        let canDelete = preset.groupName == "Custom"
        return HStack(spacing: 6) {
            Button {
                eq.applyPreset(preset)
            } label: {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : pal.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(isActive ? pal.accent : pal.surface))
            }
            .buttonStyle(.plain)
            if canDelete {
                Button {
                    eq.deleteCustomPreset(preset.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(pal.surfaceHigh, lineWidth: 1)
        )
    }

    private func saveCustomPreset() {
        presetName = ""
        showSaveAlert = true
    }
}

// MARK: - Vertical band slider (EqBandSlider parity: -600...600 raw)

struct EqBandSlider: View {
    @Binding var value: Double
    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f", value / 10))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(pal.textSecondary)
            GeometryReader { geometry in
                ZStack {
                    Capsule()
                        .fill(pal.surfaceHigh)
                        .frame(width: 4)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    // Fill from center.
                    Capsule()
                        .fill(pal.accent)
                        .frame(width: 4, height: fillHeight(geometry))
                        .position(x: geometry.size.width / 2, y: centerY(geometry))
                    Circle()
                        .fill(pal.accent)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .position(x: geometry.size.width / 2, y: thumbY(geometry))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let fraction = 1 - gesture.location.y / max(1, geometry.size.height)
                            let clamped = min(600, max(-600, Int(fraction * 1200 - 600)))
                            value = Double(clamped)
                        }
                )
            }
            .frame(width: 44, height: 190)
        }
    }

    private func thumbY(_ geometry: GeometryProxy) -> CGFloat {
        let fraction = (value + 600) / 1200
        return geometry.size.height * (1 - CGFloat(fraction))
    }

    private func centerY(_ geometry: GeometryProxy) -> CGFloat {
        let zero = geometry.size.height / 2
        let thumb = thumbY(geometry)
        return (zero + thumb) / 2
    }

    private func fillHeight(_ geometry: GeometryProxy) -> CGFloat {
        abs(geometry.size.height / 2 - thumbY(geometry))
    }
}

// MARK: - Circular EQ control (CircularEqControl.kt parity)

struct CircularEqControl: View {
    @EnvironmentObject private var eq: EqualizerEngine
    @Environment(\.epsPalette) private var pal

    @State private var bass: Double = 0
    @State private var mids: Double = 0
    @State private var treble: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, 360)
                let center = CGPoint(x: geometry.size.width / 2, y: size / 2)
                let radius = size / 2

                ZStack {
                    // Axis lines.
                    ForEach(axisAngles, id: \.self) { angle in
                        Path { path in
                            let inner = pointAt(angle: angle, distance: radius * 0.18, center: center)
                            let outer = pointAt(angle: angle, distance: radius * 0.46, center: center)
                            path.move(to: inner)
                            path.addLine(to: outer)
                        }
                        .stroke(pal.surfaceHigh, lineWidth: 2)
                    }
                    // Tick dots.
                    ForEach(axisAngles, id: \.self) { angle in
                        ForEach(0..<7, id: \.self) { tick in
                            let fraction = Double(tick) / 6.0
                            let distance = radius * (0.18 + 0.28 * fraction)
                            Circle()
                                .fill(pal.textSecondary.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .position(pointAt(angle: angle, distance: distance, center: center))
                        }
                    }
                    // Handles.
                    handleDot(angle: axisAngles[0], value: mids, label: "Mids")
                    handleDot(angle: axisAngles[1], value: bass, label: "Bass")
                    handleDot(angle: axisAngles[2], value: treble, label: "Treble")
                    // Center circle.
                    Circle()
                        .stroke(pal.accent.opacity(0.7), lineWidth: 2)
                        .frame(width: radius * 0.36, height: radius * 0.36)
                        .position(center)
                    Text("\(Int(bass.rounded()))")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(pal.textSecondary)
                        .position(pointAt(angle: axisAngles[1], distance: radius * 0.6, center: center))
                    Text("\(Int(mids.rounded()))")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(pal.textSecondary)
                        .position(pointAt(angle: axisAngles[0], distance: radius * 0.6, center: center))
                    Text("\(Int(treble.rounded()))")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(pal.textSecondary)
                        .position(pointAt(angle: axisAngles[2], distance: radius * 0.6, center: center))
                }
                .frame(width: geometry.size.width, height: size)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            updateAxis(for: drag.location, center: center, radius: radius)
                        }
                )
                .onAppear {
                    bass = eq.simpleBass
                    mids = eq.simpleMids
                    treble = eq.simpleTreble
                }
            }
            .frame(height: 320)
            .padding(.horizontal, 16)

            Text("Drag the Bass, Mids and Treble dots along their axes (±10)")
                .font(.system(size: 12))
                .foregroundStyle(pal.textSecondary)
        }
    }

    private var axisAngles: [Double] {
        // Mids at -90° (top), Bass at +30° (bottom-right), Treble at +150° (bottom-left).
        [-90.0, 30.0, 150.0]
    }

    private func pointAt(angle: Double, distance: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + distance * CGFloat(cos(radians)),
                       y: center.y + distance * CGFloat(sin(radians)))
    }

    private func handleDot(angle: Double, value: Double, label: String) -> some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, 360)
            let center = CGPoint(x: geometry.size.width / 2, y: size / 2)
            let radius = size / 2
            let normalized = (value + 10) / 20 // 0...1
            let distance = radius * (0.18 + 0.28 * CGFloat(normalized))
            ZStack {
                Circle()
                    .fill(pal.accent)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 3)
                Text(label.prefix(1))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .position(pointAt(angle: angle, distance: distance, center: center))
        }
        .allowsHitTesting(false)
    }

    private func updateAxis(for location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let fraction = max(0, min(1, Double((distance - radius * 0.18) / (radius * 0.28))))
        let value = (fraction * 20 - 10)
        let angle = atan2(dy, dx) * 180 / .pi
        // Snap to the closest axis within 45°.
        let normalized = angle < 0 ? angle + 360 : angle
        let candidates: [(target: Double, setter: (Double) -> Void)] = [
            (270.0, { mids = $0 }),
            (30.0, { bass = $0 }),
            (150.0, { treble = $0 }),
        ]
        var best: (target: Double, setter: (Double) -> Void)? = nil
        var bestDelta = 999.0
        for candidate in candidates {
            var delta = abs(normalized - candidate.target)
            if delta > 180 { delta = 360 - delta }
            if delta < bestDelta {
                bestDelta = delta
                best = candidate
            }
        }
        if let best = best, bestDelta < 60 {
            let clamped = max(-10, min(10, value))
            best.setter(clamped)
            eq.setSimpleValues(bass: bass, mids: mids, treble: treble)
        }
    }
}
