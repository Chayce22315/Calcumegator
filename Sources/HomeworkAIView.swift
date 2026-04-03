import SwiftUI

// MARK: - Bundled model options (UI)

enum HomeworkModelOption: String, CaseIterable, Identifiable {
    case llamaUltra = "Llama 3D · Ultra"
    case proSoon = "Homework Lite · Pro (soon)"
    case freeSoon = "Homework Mini · Free (soon)"

    var id: String { rawValue }

    var usesBundledLlama: Bool {
        self == .llamaUltra
    }
}

// MARK: - Custom styled dropdown (not system Menu / Picker)

private struct CustomStyledModelPicker: View {
    @Binding var selection: HomeworkModelOption
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .orange.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(selection.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
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
                                            Color.orange.opacity(isExpanded ? 0.65 : 0.35),
                                            Color.cyan.opacity(isExpanded ? 0.5 : 0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isExpanded ? 1.5 : 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(HomeworkModelOption.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            selection = option
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                isExpanded = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.rawValue)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if option == .llamaUltra {
                                        Text("Core ML · Models/Ultra/llama_3d")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    } else {
                                        Text("Placeholder — bundle a model later")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if option == selection {
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
                        if index < HomeworkModelOption.allCases.count - 1 {
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
}

// MARK: - Homework tab

struct HomeworkAIView: View {
    @StateObject private var llama = LlamaInferenceManager()
    @State private var prompt = ""
    @State private var selectedModel: HomeworkModelOption = .llamaUltra
    @State private var pickerExpanded = false
    @State private var placeholderOutput = ""
    @State private var isRunningPlaceholder = false

    private var displayedResponse: String {
        if selectedModel.usesBundledLlama {
            return llama.outputText
        }
        return placeholderOutput
    }

    private var displayedError: String? {
        if selectedModel.usesBundledLlama {
            return llama.lastError
        }
        return nil
    }

    private var isBusy: Bool {
        if selectedModel.usesBundledLlama {
            return llama.isGenerating
        }
        return isRunningPlaceholder
    }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if pickerExpanded {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            pickerExpanded = false
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

                    CustomStyledModelPicker(selection: $selectedModel, isExpanded: $pickerExpanded)
                        .zIndex(1)

                    Group {
                        if selectedModel.usesBundledLlama {
                            if let err = llama.loadError {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red.opacity(0.9))
                            } else if llama.isLoaded {
                                Label("Llama 3D ready (loaded asynchronously)", systemImage: "checkmark.seal.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.green.opacity(0.9))
                            } else {
                                Label("Loading model…", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            (Text("Select ")
                                + Text("Llama 3D · Ultra").bold()
                                + Text(" to run your bundled Core ML package. Other rows are placeholders for future bundles."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your question")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Solve 3x + 2 = 14 for x", text: $prompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...8)
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
        .task(id: selectedModel.id) {
            await handleModelChange()
        }
    }

    private func handleModelChange() async {
        placeholderOutput = ""
        if selectedModel.usesBundledLlama {
            await llama.loadBundledLlamaIfNeeded()
        } else {
            llama.unload()
        }
    }

    private func runInference() async {
        let q = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if selectedModel.usesBundledLlama {
            await llama.generate(from: q, maxNewTokens: 128)
            return
        }

        isRunningPlaceholder = true
        placeholderOutput = ""
        let modelName = selectedModel.rawValue
        try? await Task.sleep(nanoseconds: 350_000_000)
        placeholderOutput =
            "(\(modelName)) The Swift birds are still riveting beams on this slot—no Core ML bundle is wired here yet. Your question was: “\(q)”\n\nAdd a `.mlpackage` under Models/Pro or Models/Free and hook it up the same way as Llama 3D."
        isRunningPlaceholder = false
    }
}

#Preview {
    HomeworkAIView()
        .preferredColorScheme(.dark)
}
