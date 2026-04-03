import SwiftUI
import UIKit

// MARK: - Per-tier custom dropdown

private struct TierModelPickerRow: View {
    let tier: ModelTierFolder
    @Binding var selection: HomeworkTierModel
    @Binding var expandedTier: ModelTierFolder?
    let discovered: [HomeworkTierModel]

    private var options: [HomeworkTierModel] {
        HomeworkTierModel.options(for: tier, discovered: discovered)
    }

    private var isOpen: Bool { expandedTier == tier }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tier.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    expandedTier = isOpen ? nil : tier
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: tier == .ultra ? "cpu" : tier == .pro ? "bolt.fill" : "leaf.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .orange.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.orange.opacity(isOpen ? 0.65 : 0.35),
                                            Color.cyan.opacity(isOpen ? 0.5 : 0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isOpen ? 1.5 : 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            selection = option
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                expandedTier = nil
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(optionSubtitle(option))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if option.id == selection.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: index.isMultiple(of: 2) ? 0.12 : 0.14))
                        }
                        .buttonStyle(.plain)
                        if index < options.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var subtitle: String {
        if selection.isPlaceholder {
            return "Add .mlpackage to Models/\(tier.rawValue)"
        }
        if let path = selection.bundleFileURL?.lastPathComponent {
            return "Core ML · \(path)"
        }
        return "Core ML · \(selection.resourceStem)"
    }

    private func optionSubtitle(_ option: HomeworkTierModel) -> String {
        if option.isPlaceholder { return "No package found — add one to Xcode" }
        return option.bundleFileURL?.path ?? option.resourceStem
    }
}

// MARK: - Homework tab

struct HomeworkAIView: View {
    @StateObject private var llama = LlamaInferenceManager()
    @State private var discovered: [HomeworkTierModel] = []
    @State private var freePick = HomeworkTierModel.placeholder(for: .free)
    @State private var proPick = HomeworkTierModel.placeholder(for: .pro)
    @State private var ultraPick = HomeworkTierModel.placeholder(for: .ultra)
    @State private var solveTier: ModelTierFolder = .ultra
    @State private var expandedTier: ModelTierFolder?
    @State private var prompt = ""
    @State private var placeholderOutput = ""
    @State private var isRunningPlaceholder = false
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var ocrBusy = false

    private var modelForRun: HomeworkTierModel {
        switch solveTier {
        case .free: return freePick
        case .pro: return proPick
        case .ultra: return ultraPick
        }
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var displayedResponse: String {
        if modelForRun.isPlaceholder {
            return placeholderOutput
        }
        return llama.outputText
    }

    private var displayedError: String? {
        if modelForRun.isPlaceholder { return nil }
        return llama.lastError
    }

    private var isBusy: Bool {
        ocrBusy || isRunningPlaceholder || (!modelForRun.isPlaceholder && llama.isGenerating)
    }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if expandedTier != nil {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            expandedTier = nil
                        }
                    }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Homework AI")
                            .font(.largeTitle.bold())
                        Text("Local Core ML · Pixelated Studios · NextStop")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Models per tier")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 14) {
                        TierModelPickerRow(tier: .free, selection: $freePick, expandedTier: $expandedTier, discovered: discovered)
                        TierModelPickerRow(tier: .pro, selection: $proPick, expandedTier: $expandedTier, discovered: discovered)
                        TierModelPickerRow(tier: .ultra, selection: $ultraPick, expandedTier: $expandedTier, discovered: discovered)
                    }
                    .zIndex(1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Solve using")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Picker("Tier", selection: $solveTier) {
                            ForEach(ModelTierFolder.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Group {
                        if modelForRun.isPlaceholder {
                            (Text("Pick a real package above or add Core ML files under Models/\(modelForRun.tier.rawValue). Folder name ")
                                + Text("utlra").bold()
                                + Text(" is treated as Ultra."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let err = llama.loadError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                        } else if llama.isLoaded {
                            Label("Model ready (loaded off main thread)", systemImage: "checkmark.seal.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.green.opacity(0.9))
                        } else {
                            Label("Loading model…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your question")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(!cameraAvailable || ocrBusy)
                            .opacity(cameraAvailable ? 1 : 0.45)
                        }

                        if ocrBusy {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Reading text from photo…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !cameraAvailable {
                            Text("Camera not available on this device (e.g. Simulator). Use a physical iPhone to scan homework.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        TextField("Type a problem or use Camera to scan", text: $prompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...10)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(white: 0.14))
                            )
                    }

                    Button {
                        Task { await runInference() }
                    } label: {
                        HStack {
                            Spacer()
                            if isBusy {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Run model")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(0.95), Color.red.opacity(0.75)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let err = displayedError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(displayedResponse.isEmpty ? "—" : displayedResponse)
                            .font(.body)
                            .foregroundStyle(displayedResponse.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(white: 0.12))
                            )
                    }
                }
                .padding()
            }
        }
        .onAppear {
            refreshDiscovery()
        }
        .task(id: modelForRun.id) {
            await handleModelForRunChange()
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            guard let newImage else { return }
            Task {
                ocrBusy = true
                let text = await HomeworkTextRecognition.recognizeText(in: newImage)
                await MainActor.run {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        prompt = trimmed
                    }
                    ocrBusy = false
                    cameraImage = nil
                }
            }
        }
    }

    private func refreshDiscovery() {
        discovered = HomeworkTierModel.discover(in: .main)
        syncPicks()
    }

    private func syncPicks() {
        freePick = stablePick(current: freePick, tier: .free)
        proPick = stablePick(current: proPick, tier: .pro)
        ultraPick = stablePick(current: ultraPick, tier: .ultra)
    }

    private func stablePick(current: HomeworkTierModel, tier: ModelTierFolder) -> HomeworkTierModel {
        let opts = HomeworkTierModel.options(for: tier, discovered: discovered)
        if opts.contains(where: { $0.id == current.id }) { return current }
        return opts[0]
    }

    private func handleModelForRunChange() async {
        placeholderOutput = ""
        if modelForRun.isPlaceholder {
            llama.unload()
            return
        }
        await llama.loadModelIfNeeded(modelForRun)
    }

    private func runInference() async {
        let q = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if modelForRun.isPlaceholder {
            isRunningPlaceholder = true
            placeholderOutput = ""
            let name = modelForRun.tier.rawValue
            try? await Task.sleep(nanoseconds: 300_000_000)
            placeholderOutput =
                "No Core ML model is bundled for Models/\(name) yet. Your question: “\(q)”\n\nAdd a .mlpackage under Models/\(name) in Xcode (folder utlra is treated as Ultra), then rebuild."
            isRunningPlaceholder = false
            return
        }

        await llama.generate(from: q, maxNewTokens: 128)
    }
}

#Preview {
    HomeworkAIView()
        .preferredColorScheme(.dark)
}
