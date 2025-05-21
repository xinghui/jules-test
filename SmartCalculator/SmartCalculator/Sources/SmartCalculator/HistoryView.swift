import SwiftUI

struct HistoryView: View {
    @ObservedObject var calculationEngine: CalculationEngine
    @Binding var selectedStepID: UUID?

    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6 // Adjust as needed
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private func formatNumber(_ number: Double?) -> String {
        guard let number = number else { return "" }
        // Check if the number is an integer
        if floor(number) == number {
            let intFormatter = NumberFormatter()
            intFormatter.maximumFractionDigits = 0
            return intFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
        }
        return numberFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("History")
                    .font(.headline)
                    .padding(.horizontal)
                    .foregroundColor(.white) // Assuming dark theme from ContentView

                if calculationEngine.history.isEmpty {
                    Text("No history yet.")
                        .font(.caption)
                        .padding(.horizontal)
                        .foregroundColor(.gray)
                } else {
                    ForEach(calculationEngine.history) { step in
                        historyRow(for: step)
                            .padding(.horizontal)
                            .background(selectedStepID == step.id ? Color.blue.opacity(0.3) : Color.clear)
                            .cornerRadius(5)
                            .onTapGesture {
                                if selectedStepID == step.id {
                                    selectedStepID = nil // Deselect if tapped again
                                } else {
                                    selectedStepID = step.id
                                }
                            }
                    }
                }
            }
        }
        .frame(minHeight: 100, maxHeight: 200) // Adjust height as needed
        .background(Color.black.opacity(0.8)) // Slightly different background for history
    }

    @ViewBuilder
    private func historyRow(for step: CalculationStep) -> some View {
        HStack {
            Text(step.displayString(formatter: numberFormatter))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(selectedStepID == step.id ? .white : .gray)
                .lineLimit(1)
            Spacer() // Pushes content to the left
        }
    }
}

// Extension to CalculationStep for display formatting
extension CalculationStep {
    func displayString(formatter: NumberFormatter? = nil) -> String {
        let numFormatter = formatter ?? {
            let defaultFormatter = NumberFormatter()
            defaultFormatter.numberStyle = .decimal
            defaultFormatter.maximumFractionDigits = 6
            defaultFormatter.minimumFractionDigits = 0
            return defaultFormatter
        }()

        func format(_ number: Double?) -> String {
            guard let number = number else { return "?" } // Should not happen for valid steps
            if number.isNaN || number.isInfinite { return "Error" } // Explicitly handle NaN/Infinity

            if floor(number) == number && abs(number) < 1_000_000_000_000 { // Avoid scientific notation for large integers
                 let intFormatter = NumberFormatter()
                 intFormatter.numberStyle = .decimal
                 intFormatter.maximumFractionDigits = 0
                 return intFormatter.string(from: NSNumber(value: number)) ?? "\(Int(number))"
            }
            return numFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
        }

        let op1Str = format(operand1)
        
        if operation == .equals {
            // If it's an equals operation, often it's the result of a chain.
            // The 'operand1' for an equals step might be the result of the previous operation.
            // And 'operand2' might be nil or the value that was just entered before hitting equals.
            
            // Simplified: Show " = <result>" if it's an equals step that concludes a chain.
            // Or "<operand1> = <result>" if it was like "5 ="
            if operand2 == nil { // e.g. result of a chain like 2+3=, then this step is " = 5"
                                 // or a single number followed by equals "5="
                return "\(op1Str) \(operation.displayValue) \(format(result))"
            }
        }
        
        // For binary operations
        guard let op2 = operand2 else {
            // This could be a step like "5 +" waiting for second operand.
            // Or after an equals, if we store "5 =" then op2 is nil.
            return "\(op1Str) \(operation.displayValue) ..." // Or handle differently
        }
        let op2Str = format(op2)
        let resultStr = format(result)

        return "\(op1Str) \(operation.displayValue) \(op2Str) = \(resultStr)"
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample engine with some history
        let engine = CalculationEngine()
        engine.inputDigit("1")
        engine.inputDigit("0")
        engine.setOperation(.add)
        engine.inputDigit("5")
        engine.setOperation(.equals) // 10 + 5 = 15
        
        engine.inputDigit("3")
        engine.setOperation(.multiply)
        engine.inputDigit("2")
        engine.setOperation(.equals) // 3 * 2 = 6 -- this would be wrong, it should be 15 * 2 = 30
                                     // The engine logic for chaining would be: 15 (from prev result), then *
                                     // Let's re-do sample history carefully.
        
        let previewEngine = CalculationEngine()
        previewEngine.currentDisplayValue = "10"
        previewEngine.setOperation(.add) // op1 = 10, pending = add
        previewEngine.currentDisplayValue = "5"
        previewEngine.setOperation(.equals) // step: 10 + 5 = 15. currentDisplay = 15
        
        // Next operation starts with 15
        // User types "3" -> currentDisplayValue = "3" (engine.currentOperand1 is still 15)
        // User types "*" -> engine.setOperation(.multiply)
        //                  -> if there was a pending operation, it would calculate first.
        //                  -> currentOperand1 = 15 (result of previous)
        //                  -> pendingOperation = multiply
        //                  -> expectingOperand2 = true
        // User types "2" -> currentDisplayValue = "2"
        // User types "=" -> engine.setOperation(.equals)
        //                  -> addStep(operand1: 15, operand2: 2, operation: .multiply) -> result 30
        
        // So the history for "10 + 5 = , then * 2 =" would be:
        // 1. 10 + 5 = 15
        // 2. 15 * 2 = 30
        
        // Let's trace for the test preview:
        let testEngine = CalculationEngine()
        testEngine.inputDigit("1"); testEngine.inputDigit("0"); // Display "10"
        testEngine.setOperation(.add); // Op1: 10, Pending: Add
        testEngine.inputDigit("5"); // Display "5"
        testEngine.setOperation(.equals); // Calculates 10+5=15. History: [10+5=15]. Display "15"

        testEngine.setOperation(.multiply); // Op1: 15 (result), Pending: Multiply
        testEngine.inputDigit("2"); // Display "2"
        testEngine.setOperation(.equals); // Calculates 15*2=30. History: [10+5=15], [15*2=30]. Display "30"
        
        testEngine.inputDigit("7"); // Display "7"
        testEngine.setOperation(.equals); // History: ..., [7 = 7]

        return HistoryView(calculationEngine: testEngine, selectedStepID: .constant(nil))
            .background(Color.gray)
    }
}
