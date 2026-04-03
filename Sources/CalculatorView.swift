import SwiftUI

// MARK: - Model tier (UI only; no feature gating)

enum ModelTier: String, CaseIterable, Identifiable {
    case free = "Free"
    case pro = "Pro"
    case ultra = "Ultra"

    var id: String { rawValue }
}

// MARK: - Calculator

private enum CalcOperation {
    case add, subtract, multiply, divide
}

private struct CalculatorEngine {
    private var displayValue: Double = 0
    private var storedValue: Double?
    private var pendingOperation: CalcOperation?
    private var userIsTyping = false
    private var displayString = "0"

    func displayText() -> String { displayString }

    mutating func inputDigit(_ d: Int) {
        if !userIsTyping {
            displayString = String(d)
            userIsTyping = true
        } else {
            if displayString == "0" {
                displayString = String(d)
            } else {
                displayString.append(String(d))
            }
        }
        syncDisplayValue()
    }

    mutating func inputDecimal() {
        if !userIsTyping {
            displayString = "0."
            userIsTyping = true
        } else if !displayString.contains(".") {
            displayString.append(".")
        }
        syncDisplayValue()
    }

    mutating func setOperation(_ op: CalcOperation) {
        syncDisplayValue()
        if let stored = storedValue, let pending = pendingOperation {
            let result = apply(pending, stored, displayValue)
            displayString = format(result)
            displayValue = result
            storedValue = result
        } else {
            storedValue = displayValue
        }
        pendingOperation = op
        userIsTyping = false
    }

    mutating func equals() {
        syncDisplayValue()
        guard let stored = storedValue, let pending = pendingOperation else { return }
        let result = apply(pending, stored, displayValue)
        displayString = format(result)
        displayValue = result
        storedValue = nil
        pendingOperation = nil
        userIsTyping = false
    }

    mutating func clear() {
        displayValue = 0
        storedValue = nil
        pendingOperation = nil
        userIsTyping = false
        displayString = "0"
    }

    mutating func toggleSign() {
        syncDisplayValue()
        displayValue = -displayValue
        displayString = format(displayValue)
        userIsTyping = false
    }

    mutating func percent() {
        syncDisplayValue()
        displayValue /= 100
        displayString = format(displayValue)
        userIsTyping = false
    }

    private mutating func syncDisplayValue() {
        displayValue = Double(displayString) ?? 0
    }

    private func apply(_ op: CalcOperation, _ a: Double, _ b: Double) -> Double {
        switch op {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide: return b == 0 ? a : a / b
        }
    }

    private func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, value <= Double(Int.max), value >= Double(Int.min) {
            return String(Int(value))
        }
        let s = String(format: "%.8f", value)
        var trimmed = s
        while trimmed.last == "0" { trimmed.removeLast() }
        if trimmed.last == "." { trimmed.removeLast() }
        return trimmed
    }
}

// MARK: - View

struct CalculatorView: View {
    @State private var engine = CalculatorEngine()
    @State private var selectedTier: ModelTier = .free

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                tierPicker
                wipBanner
                homeworkTabHint
                display
                keypad
            }
            .padding()
        }
        .background(Color(white: 0.08).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calcumegator")
                .font(.largeTitle.bold())
            Text("Pixelated Studios · NextStop")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var tierPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI model tier")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Tier", selection: $selectedTier) {
                ForEach(ModelTier.allCases) { tier in
                    Text(tier.rawValue).tag(tier)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var wipBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Purchase subscription")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text("WORK IN PROGRESS")
                .font(.title2.bold())
                .foregroundStyle(.orange)

            Text(
                "A flock of tiny Swift birds—those cheerful Apple-coding mascots—have donned hardhats and are busy pouring concrete for the checkout flow. Hammers clang, cranes swing, and somewhere a receipt printer is still in the box."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            (Text("Payment is under construction, so ")
                + Text("Pro").bold()
                + Text(" and ")
                + Text("Ultra").bold()
                + Text(" are free for now—enjoy the full stack."))
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var homeworkTabHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.cyan.opacity(0.9))
            (Text("Need local AI homework help? Open the ")
                + Text("Homework").bold()
                + Text(" tab (all tiers unlocked)."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.11))
        )
    }

    private var display: some View {
        Text(engine.displayText())
            .font(.system(size: 56, weight: .light, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .padding(.vertical, 8)
    }

    private var keypad: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            key("C", style: .utility) { engine.clear() }
            key("±", style: .utility) { engine.toggleSign() }
            key("%", style: .utility) { engine.percent() }
            key("÷", style: .operator) { engine.setOperation(.divide) }

            key("7", style: .digit) { engine.inputDigit(7) }
            key("8", style: .digit) { engine.inputDigit(8) }
            key("9", style: .digit) { engine.inputDigit(9) }
            key("×", style: .operator) { engine.setOperation(.multiply) }

            key("4", style: .digit) { engine.inputDigit(4) }
            key("5", style: .digit) { engine.inputDigit(5) }
            key("6", style: .digit) { engine.inputDigit(6) }
            key("−", style: .operator) { engine.setOperation(.subtract) }

            key("1", style: .digit) { engine.inputDigit(1) }
            key("2", style: .digit) { engine.inputDigit(2) }
            key("3", style: .digit) { engine.inputDigit(3) }
            key("+", style: .operator) { engine.setOperation(.add) }

            zeroKey
            key(".", style: .digit) { engine.inputDecimal() }
            equalsKey
        }
    }

    private enum KeyStyle {
        case digit, utility, operator
    }

    private func key(_ title: String, style: KeyStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(background(for: style))
                .foregroundStyle(foreground(for: style))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var zeroKey: some View {
        Button {
            engine.inputDigit(0)
        } label: {
            Text("0")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 28)
                .frame(height: 72)
                .background(background(for: .digit))
                .foregroundStyle(foreground(for: .digit))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .gridCellColumns(2)
    }

    private var equalsKey: some View {
        Button {
            engine.equals()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.45, blue: 0.2))

                Text("=")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("M")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.95), Color.cyan.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: 18, y: -20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Equals, mega homework shortcut")
    }

    private func background(for style: KeyStyle) -> Color {
        switch style {
        case .digit: return Color(white: 0.22)
        case .utility: return Color(white: 0.32)
        case .operator: return Color(red: 1, green: 0.62, blue: 0.12)
        }
    }

    private func foreground(for style: KeyStyle) -> Color {
        switch style {
        case .digit: return .white
        case .utility: return .black
        case .operator: return .white
        }
    }
}

#Preview {
    CalculatorView()
        .preferredColorScheme(.dark)
}
