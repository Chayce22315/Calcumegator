import Combine
import CoreML
import Foundation

// MARK: - Errors

enum LlamaInferenceError: LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case unsupportedSchema(String)
    case predictionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Could not find llama_3d in the app bundle (Models/Ultra)."
        case .modelNotLoaded:
            return "The Core ML model is not loaded yet."
        case .unsupportedSchema(let hint):
            return "This model’s inputs/outputs are not handled yet.\n\(hint)"
        case .predictionFailed(let message):
            return message
        }
    }
}

// MARK: - Manager

/// Loads `llama_3d` from the bundled `Models/Ultra` folder asynchronously and runs a small greedy text-generation loop.
/// Real Llama exports vary (state, KV cache, tokenizer). This class tries string I/O first, then a token/logits loop with heuristic tokenization.
@MainActor
final class LlamaInferenceManager: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var outputText = ""
    @Published private(set) var lastError: String?

    private var model: MLModel?

    /// Looks for compiled `mlmodelc` or `mlpackage` after Xcode copies the `Models` folder into the bundle.
    static func bundledLlamaURL() -> URL? {
        let bundle = Bundle.main
        let names = ["llama_3d"]
        let extensions = ["mlmodelc", "mlpackage"]
        let subdirs = [
            "Models/Ultra",
            "Ultra",
            "Models",
            ""
        ]
        for sub in subdirs {
            for name in names {
                for ext in extensions {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub.isEmpty ? nil : sub),
                       FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
        }
        if let resourceURL = bundle.resourceURL {
            let manual = resourceURL.appendingPathComponent("Models/Ultra/llama_3d.mlpackage")
            if FileManager.default.fileExists(atPath: manual.path) { return manual }
            let manualC = resourceURL.appendingPathComponent("Models/Ultra/llama_3d.mlmodelc")
            if FileManager.default.fileExists(atPath: manualC.path) { return manualC }
        }
        return nil
    }

    nonisolated private static func loadModelAsync(at url: URL) async throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try await withCheckedThrowingContinuation { continuation in
            MLModel.load(contentsOf: url, configuration: config) { result in
                switch result {
                case .success(let model):
                    continuation.resume(returning: model)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadBundledLlamaIfNeeded() async {
        guard model == nil else { return }
        loadError = nil
        lastError = nil
        guard let url = Self.bundledLlamaURL() else {
            loadError = LlamaInferenceError.modelNotFound.localizedDescription
            return
        }
        do {
            let loaded = try await Self.loadModelAsync(at: url)
            model = loaded
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
            isLoaded = false
        }
    }

    func unload() {
        model = nil
        isLoaded = false
        loadError = nil
        outputText = ""
        lastError = nil
    }

    /// Runs generation off the main actor; publishes `outputText` when finished.
    func generate(from prompt: String, maxNewTokens: Int = 128) async {
        lastError = nil
        outputText = ""
        guard let model else {
            lastError = LlamaInferenceError.modelNotLoaded.localizedDescription
            return
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Type a question first."
            return
        }

        isGenerating = true
        let result: Result<String, Error> = await Task.detached {
            do {
                let text = try Self.runGeneration(model: model, prompt: trimmed, maxNewTokens: maxNewTokens)
                return .success(text)
            } catch {
                return .failure(error)
            }
        }.value

        isGenerating = false
        switch result {
        case .success(let text):
            outputText = text
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    // MARK: - Core ML generation (background-safe)

    nonisolated private static func runGeneration(model: MLModel, prompt: String, maxNewTokens: Int) throws -> String {
        let desc = model.modelDescription

        if let stringOut = try? predictStringPipeline(model: model, desc: desc, prompt: prompt) {
            return stringOut
        }
        return try predictTokenLoop(model: model, desc: desc, prompt: prompt, maxNewTokens: maxNewTokens)
    }

    /// Single forward pass: string → string (some packaged LLM wrappers expose this).
    nonisolated private static func predictStringPipeline(model: MLModel, desc: MLModelDescription, prompt: String) throws -> String {
        guard let stringInputName = desc.inputDescriptionsByName.first(where: { $0.value.type == .string })?.key else {
            throw LlamaInferenceError.unsupportedSchema("No string input.")
        }
        guard let stringOutputPair = desc.outputDescriptionsByName.first(where: { $0.value.type == .string }) else {
            throw LlamaInferenceError.unsupportedSchema("No string output.")
        }
        let stringOutputName = stringOutputPair.key
        let input = try MLDictionaryFeatureProvider(dictionary: [stringInputName: MLFeatureValue(string: prompt)])
        let prediction = try model.prediction(from: input)
        guard let value = prediction.featureValue(for: stringOutputName)?.stringValue else {
            throw LlamaInferenceError.predictionFailed("Missing string output \(stringOutputName).")
        }
        return value
    }

    /// Greedy autoregressive loop using int32 token input and float logits output (heuristic layout).
    nonisolated private static func predictTokenLoop(
        model: MLModel,
        desc: MLModelDescription,
        prompt: String,
        maxNewTokens: Int
    ) throws -> String {
        // Avoid `Dictionary.filter { }` — on newer SDKs it can resolve to the `Predicate`-based overload (breaks CI).
        var tokenCandidates: [(key: String, value: MLFeatureDescription)] = []
        for (key, value) in desc.inputDescriptionsByName {
            guard value.type == .multiArray else { continue }
            guard value.multiArrayConstraint?.dataType == .int32 else { continue }
            tokenCandidates.append((key, value))
        }
        guard let inputPair = tokenCandidates.max(by: { tokenInputScore($0.key) < tokenInputScore($1.key) }) else {
            throw LlamaInferenceError.unsupportedSchema(schemaHint(from: desc))
        }
        let inputName = inputPair.key
        let inputDesc = inputPair.value

        let logitsName = desc.outputDescriptionsByName.first(where: { pair in
            let out = pair.value
            guard out.type == .multiArray, let dt = out.multiArrayConstraint?.dataType else { return false }
            guard dt == .float32 || dt == .float16 || dt == .double else { return false }
            let lower = pair.key.lowercased()
            return lower.contains("logit") || lower.contains("lm_head") || lower.contains("logits")
        })?.key ?? desc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key

        guard let logitsName else {
            throw LlamaInferenceError.unsupportedSchema("No multiArray output for logits.\n\(schemaHint(from: desc))")
        }

        let shape = inputDesc.multiArrayConstraint?.shape as [NSNumber]? ?? [1, NSNumber(value: 128)]
        let batch = max(shape.first?.intValue ?? 1, 1)
        let seqDim: Int = {
            if shape.count >= 2 { return max(shape[1].intValue, 1) }
            return 128
        }()

        var tokens = heuristicTokenize(prompt, maxCount: max(seqDim - maxNewTokens, 8))
        if tokens.isEmpty { tokens = [32] }

        var generated = ""
        var carry: [String: MLFeatureValue] = [:]

        for _ in 0..<maxNewTokens {
            var padded = tokens
            if padded.count > seqDim {
                padded = Array(padded.suffix(seqDim))
            }
            while padded.count < seqDim {
                padded.append(0)
            }

            let shapeNums = [NSNumber(value: batch), NSNumber(value: seqDim)]
            let tokenArray = try makeInt32MultiArray(shape: shapeNums, values: padded)

            var featureDict: [String: MLFeatureValue] = [inputName: MLFeatureValue(multiArray: tokenArray)]
            for (name, value) in carry {
                if name != inputName {
                    featureDict[name] = value
                }
            }

            for (name, od) in desc.inputDescriptionsByName {
                if featureDict[name] != nil { continue }
                if let def = try? defaultInputFeature(for: od) {
                    featureDict[name] = def
                }
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction: MLFeatureProvider
            do {
                prediction = try model.prediction(from: provider)
            } catch {
                throw LlamaInferenceError.predictionFailed("\(error.localizedDescription)\n\(schemaHint(from: desc))")
            }

            for name in prediction.featureNames {
                guard name != logitsName else { continue }
                guard desc.inputDescriptionsByName[name] != nil else { continue }
                if let v = prediction.featureValue(for: name) {
                    carry[name] = v
                }
            }

            guard let logits = prediction.featureValue(for: logitsName)?.multiArrayValue else {
                throw LlamaInferenceError.predictionFailed("Output \(logitsName) missing.")
            }

            let activeLen = min(tokens.count, seqDim)
            let pos = max(0, activeLen - 1)
            let nextId = argmaxTokenId(logits: logits, sequencePosition: pos)
            if nextId == 0 || nextId == 2 {
                break
            }
            tokens.append(nextId)
            generated.append(contentsOf: heuristicDetokenize(nextId))
        }

        if generated.isEmpty {
            return "(Model ran but produced no decoded text.)\n\(schemaHint(from: desc))"
        }
        return generated
    }

    nonisolated private static func tokenInputScore(_ name: String) -> Int {
        let n = name.lowercased()
        if n.contains("input_ids") || n.contains("inputids") { return 100 }
        if n.contains("token") && n.contains("id") { return 80 }
        if n.contains("tokens") { return 70 }
        if n.contains("input") && n.contains("token") { return 60 }
        if n.contains("ids") { return 40 }
        return 10
    }

    nonisolated private static func heuristicTokenize(_ text: String, maxCount: Int) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(min(maxCount, text.count))
        for scalar in text.unicodeScalars {
            guard out.count < maxCount else { break }
            let v = Int32(truncatingIfNeeded: Int(scalar.value) % 32_000)
            out.append(max(1, v))
        }
        return out
    }

    nonisolated private static func heuristicDetokenize(_ id: Int32) -> String {
        if let u = UnicodeScalar(UInt32(id)), u.isASCII {
            return String(Character(u))
        }
        if id > 0, id < 256 {
            let u = UnicodeScalar(UInt8(truncatingIfNeeded: id))
            return String(Character(u))
        }
        return ""
    }

    nonisolated private static func makeInt32MultiArray(shape: [NSNumber], values: [Int32]) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape, dataType: .int32)
        let count = min(values.count, arr.count)
        let ptr = arr.dataPointer.bindMemory(to: Int32.self, capacity: arr.count)
        for i in 0..<arr.count {
            ptr[i] = i < count ? values[i] : 0
        }
        return arr
    }

    nonisolated private static func stridesInts(_ array: MLMultiArray) -> [Int] {
        (0..<array.strides.count).map { array.strides[$0].intValue }
    }

    nonisolated private static func linearIndex(strides: [Int], indices: [Int]) -> Int {
        var offset = 0
        for i in 0..<indices.count {
            offset += indices[i] * strides[i]
        }
        return offset
    }

    nonisolated private static func doubleAt(_ array: MLMultiArray, indices: [Int]) -> Double {
        let s = stridesInts(array)
        guard indices.count == s.count else { return 0 }
        let idx = linearIndex(strides: s, indices: indices)
        guard idx >= 0, idx < array.count else { return 0 }
        switch array.dataType {
        case .double:
            let p = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            return p[idx]
        case .float32:
            let p = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return Double(p[idx])
        case .float16:
            let p = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            return Double(p[idx])
        default:
            return 0
        }
    }

    nonisolated private static func argmaxTokenId(logits: MLMultiArray, sequencePosition pos: Int) -> Int32 {
        let rank = logits.shape.count
        guard rank >= 2 else { return 0 }
        let vocab = logits.shape[rank - 1].intValue
        let seqLen = logits.shape[rank - 2].intValue
        let position = min(max(pos, 0), max(seqLen - 1, 0))

        var bestIndex = 0
        var bestValue: Double = -.greatestFiniteMagnitude

        if rank == 3 {
            for v in 0..<vocab {
                let value = doubleAt(logits, indices: [0, position, v])
                if value > bestValue {
                    bestValue = value
                    bestIndex = v
                }
            }
        } else if rank == 2 {
            let inner = logits.shape[1].intValue
            for v in 0..<min(vocab, inner) {
                let value = doubleAt(logits, indices: [position, v])
                if value > bestValue {
                    bestValue = value
                    bestIndex = v
                }
            }
        } else if rank == 4 {
            let seqAxis = rank - 2
            let seqExtent = logits.shape[seqAxis].intValue
            let posClamped = min(max(pos, 0), max(seqExtent - 1, 0))
            for v in 0..<vocab {
                var idx = [Int](repeating: 0, count: rank)
                idx[seqAxis] = posClamped
                idx[rank - 1] = v
                let value = doubleAt(logits, indices: idx)
                if value > bestValue {
                    bestValue = value
                    bestIndex = v
                }
            }
        }

        return Int32(bestIndex)
    }

    /// Fills missing inputs with zeros of the advertised shape (common for masks / positions).
    nonisolated private static func defaultInputFeature(for desc: MLFeatureDescription) throws -> MLFeatureValue? {
        switch desc.type {
        case .multiArray:
            guard let c = desc.multiArrayConstraint else { return nil }
            let shape = c.shape as [NSNumber]
            switch c.dataType {
            case .float32, .float16, .double:
                let arr = try MLMultiArray(shape: shape, dataType: .float32)
                return MLFeatureValue(multiArray: arr)
            case .int32:
                let arr = try MLMultiArray(shape: shape, dataType: .int32)
                return MLFeatureValue(multiArray: arr)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    nonisolated private static func schemaHint(from desc: MLModelDescription) -> String {
        let inputs = desc.inputDescriptionsByName.map { "\($0.key): \(String(describing: $0.value.type))" }.joined(separator: ", ")
        let outputs = desc.outputDescriptionsByName.map { "\($0.key): \(String(describing: $0.value.type))" }.joined(separator: ", ")
        return "Inputs: [\(inputs)]\nOutputs: [\(outputs)]"
    }
}
