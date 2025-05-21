import Foundation
import Combine // For ObservableObject
import os.log // For logging errors

// Enum for different calculation operations
enum OperationType: String, CaseIterable, Identifiable, Codable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
    case equals = "="

    var id: Self { self }

    var displayValue: String {
        return self.rawValue
    }
}

// Struct to represent a single step in the calculation
struct CalculationStep: Identifiable, Codable {
    let id: UUID
    var operand1: Double
    var operand2: Double?
    var operation: OperationType
    var result: Double?

    init(id: UUID = UUID(), operand1: Double, operand2: Double? = nil, operation: OperationType, result: Double? = nil) {
        self.id = id
        self.operand1 = operand1
        self.operand2 = operand2
        self.operation = operation
        self.result = result
    }
}

class CalculationEngine: ObservableObject {
    @Published var history: [CalculationStep] = []
    @Published var currentDisplayValue: String = "0"

    private let historyKey = "calculationHistory"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SmartCalculator", category: "CalculationEngine")

    private var currentOperand1: Double? = nil
    private var pendingOperation: OperationType? = nil
    private var expectingOperand2: Bool = false
    private var isDisplayingFinalResult: Bool = false // Flag for state after equals or chained calc

    // Adds a digit or decimal point to the current input
    func inputDigit(_ digit: String) {
        if currentDisplayValue.lowercased() == "error" {
            // If display shows "Error", first digit input clears error and starts new number.
            currentDisplayValue = (digit == ".") ? "0." : digit
            isDisplayingFinalResult = false // Treat as fresh input
            currentOperand1 = nil
            pendingOperation = nil
            expectingOperand2 = false
            if digit == "." && currentDisplayValue == "0." { return } // Wait for more digits if only decimal point
            return // Important to return here to avoid further processing in this call
        }

        if isDisplayingFinalResult {
            currentDisplayValue = (digit == ".") ? "0." : digit
            isDisplayingFinalResult = false
            currentOperand1 = nil // Clear previous calculation context
            pendingOperation = nil
            if digit == "." && currentDisplayValue == "0." { return }
        } else if digit == "." {
            if expectingOperand2 { 
                currentDisplayValue = "0."
                expectingOperand2 = false 
            } else if !currentDisplayValue.contains(".") { 
                currentDisplayValue += "."
            } 
            return 
        } else if expectingOperand2 { 
            currentDisplayValue = digit
            expectingOperand2 = false
        } else { 
            if currentDisplayValue == "0" && digit != "." { // Avoid "05", make it "5", but allow "0."
                currentDisplayValue = digit
            } else {
                currentDisplayValue += digit
            }
        }
    }

    // Sets the operation or performs calculation if equals
    func setOperation(_ operation: OperationType) {
        if currentDisplayValue.lowercased() == "error" {
            logger.log("Display shows error. Operation \(operation.displayValue) ignored. Please clear.")
            return // Do not proceed with any operation if display is "Error"
        }

        guard let value = Double(currentDisplayValue) else {
            // This case should ideally not be reached if "Error" is handled above,
            // but as a safeguard for other non-numeric states.
            logger.log("Invalid number in display: \(self.currentDisplayValue). Operation \(operation.displayValue) ignored.")
            return
        }
        
        // If an operation is pressed after a result was displayed,
        // use that result as the first operand for the new operation.
        if isDisplayingFinalResult && operation != .equals {
            currentOperand1 = value // The displayed result becomes operand1
            pendingOperation = operation
            expectingOperand2 = true
            isDisplayingFinalResult = false // No longer displaying a "final" result of previous calc
            return
        }
        isDisplayingFinalResult = false // Clear flag for any new operation sequence

        if operation == .equals {
            if let op1 = currentOperand1, let pendingOp = pendingOperation {
                // Standard case: 5 + 3 =
                addStep(operand1: op1, operand2: value, operation: pendingOp)
            } else if pendingOperation == nil && currentOperand1 == nil {
                // Case: User types a number (e.g., "5") and then hits "=".
                addStep(operand1: value, operand2: nil, operation: .equals)
            } else if let op1 = currentOperand1, pendingOperation == nil {
                // Case: 5 =, then user types 3 (value), then = again.
                // This means the previous operation was equals, currentOperand1 is the result of that.
                // Standard calculators would use 'value' as new operand2 for previous operation type.
                // Our model repeats last *actual* operation if equals is pressed again (handled in addStep).
                // So if user types "5 = 3 =", it's "5=5", then "3=3".
                // If it was "2+3=5", then user types "6", then "=", it should be "6=6".
                // The logic in addStep for .equals handles repeating the *actual* last operation.
                // For "X Y =", this is handled by currentOperand1 != nil and pendingOperation != nil
                // For "X =", then "Y" then "=", this is currentOperand1 = nil, pendingOp = nil, so "Y=Y"
                addStep(operand1: value, operand2: nil, operation: .equals)
            }
             currentOperand1 = nil // After equals, history.last.result is the new currentOperand1 if user continues chain.
             pendingOperation = nil
             isDisplayingFinalResult = true
        } else { // For non-equals operations (+, -, *, /)
            if let op1 = currentOperand1, let pendingOp = pendingOperation, !expectingOperand2 {
                // Chained operation: e.g., 5 + 3 * (user presses *). Calculate 5+3.
                addStep(operand1: op1, operand2: value, operation: pendingOp)
                currentOperand1 = history.last?.result // Result of (5+3) becomes op1 for *.
                pendingOperation = operation // New pending operation is *.
                expectingOperand2 = true
                isDisplayingFinalResult = true // Displaying intermediate result (e.g., "8" after 5+3)
            } else {
                // First operation in a calculation, or starting with a new number.
                currentOperand1 = value
                pendingOperation = operation
                expectingOperand2 = true
                // isDisplayingFinalResult is false, display shows current input, not a calculated result.
            }
        }
    }

    // Adds a step and calculates its result
    func addStep(operand1: Double, operand2: Double?, operation: OperationType) {
        var result: Double?
        var stepOperand1 = operand1
        var stepOperand2 = operand2

        if operation == .equals {
            if history.isEmpty || currentOperand1 == nil { // Handles "5 =" -> result 5
                result = stepOperand1
            } else { // Handles "X op Y =" or repeating equals
                if let lastStep = history.last, lastStep.operation != .equals, operand2 != nil {
                    // This is the completion of a binary operation e.g. 5 + 3 =
                    // operand1 comes from currentOperand1, operand2 from currentDisplayValue
                    // The 'operation' param is the pendingOp.
                    result = calculateStepResult(operand1: stepOperand1, operand2: stepOperand2, operation: operation)
                } else if let lastStep = history.last, lastStep.operation != .equals, operand2 == nil {
                     // e.g. 5 + =, should be 5+5=10 if calc is like iOS
                     // our current model: 5 + (op2 is nil), then =.
                     // operand1 is 5. operation is +. result should be 5.
                     // This is more like "5 + (nothing) = 5".
                     // Let's assume if op2 is nil for equals, result is op1 unless we implement repeat-operand logic for equals.
                     // For "5 =", stepOperand1 is 5, stepOperand2 is nil, operation is .equals
                     // calculateStepResult for .equals with nil op2 returns op1.
                     result = calculateStepResult(operand1: stepOperand1, operand2: stepOperand2, operation: operation)
                }
                else if let lastCompletedStep = history.last(where: { $0.operation != .equals && $0.result != nil }),
                   let prevOp2 = lastCompletedStep.operand2,
                   let prevResult = history.last?.result { // Repeating equals: use previous result and previous op2
                    stepOperand1 = prevResult
                    stepOperand2 = prevOp2 // Use previous operand2
                    result = calculateStepResult(operand1: stepOperand1, operand2: stepOperand2, operation: lastCompletedStep.operation)
                } else { // Fallback for equals, e.g. first step is "X ="
                    result = stepOperand1
                }
            }
        } else { // For add, subtract, multiply, divide
            guard let op2 = operand2 else {
                // This implies an operation like "5 +" where op2 is not yet entered.
                // We don't add a full step for this yet; state is held in currentOperand1/pendingOperation.
                // If we were to display "5 +" in history, this step would have result=nil.
                // For now, addStep is usually called when we *can* calculate or it's an equals.
                // If it's called for an intermediate step (e.g. 5 + then user hits *), op2 is present.
                logger.log("addStep called for \(operation.displayValue) without operand2. This may be an incomplete step.")
                // currentDisplayValue = formatDisplay(value: operand1) // Display operand1 if op2 is missing
                // return // Or, allow step to be added with nil result if that's desired for history.
                result = nil // Or calculateStepResult will return nil if op2 is required and missing
            }
            result = calculateStepResult(operand1: stepOperand1, operand2: op2, operation: operation)
        }

        let newStep = CalculationStep(operand1: stepOperand1, operand2: stepOperand2, operation: operation, result: result)
        history.append(newStep)
        currentDisplayValue = formatDisplay(value: result)
        saveHistory()
    }

    private func calculateStepResult(operand1: Double, operand2: Double?, operation: OperationType) -> Double? {
        guard let op2 = operand2 else {
             if operation == .equals { return operand1 } // e.g. "5 =" -> 5. Or "5+ =" -> 5
             return operation == .equals ? operand1 : nil // Only equals can proceed without op2 to mean "result is op1"
        }

        switch operation {
        case .add: return operand1 + op2
        case .subtract: return operand1 - op2
        case .multiply: return operand1 * op2
        case .divide: return op2 == 0 ? Double.nan : operand1 / op2
        case .equals: // This case implies op2 is not nil.
                      // If called from addStep for an equals operation, the actual calculation
                      // (e.g. sum, product) should have been determined by the pendingOperation.
                      // If calculateStepResult is directly called with .equals, it means "result is operand2"
                      // or "result is operand1". Standard calculators usually finalize a pending op.
                      // Our addStep logic re-passes the actual pending operation for equals.
                      // So, if .equals reaches here directly with op2, it implies "op1 = op2", result is op2.
                      // However, current addStep for equals with op1 & op2 re-calls with original operation.
                      // This path (operation == .equals AND op2 != nil) should ideally mean result is op1 or op2.
                      // Let's say "X = Y" means Y.
            return op2
        }
    }
    
    func calculate() { // Recalculates entire history. Primarily for dev/testing.
        var currentResult: Double? = nil
        for i in 0..<history.count {
            var step = history[i]
            let op1 = currentResult ?? step.operand1 
            
            if step.operation == .equals {
                 if let prevStep = history[safe: i-1], prevStep.operation != .equals, let prevRes = prevStep.result {
                    step.operand1 = prevRes
                    step.result = prevRes
                 } else { // First step is equals, or equals after equals
                    step.result = step.operand1
                 }
            } else {
                guard let op2 = step.operand2 else {
                    currentDisplayValue = formatDisplay(value: op1)
                    logger.warning("Recalculation stopped at step \(i) due to missing operand2 for non-equals operation.")
                    return
                }
                step.result = calculateStepResult(operand1: op1, operand2: op2, operation: step.operation)
            }
            history[i] = step
            currentResult = step.result
        }
        currentDisplayValue = formatDisplay(value: history.last?.result)
    }

    func updateStep(stepId: UUID, newOperand1: Double?, newOperand2: Double?) {
        guard let index = history.firstIndex(where: { $0.id == stepId }) else { return }
        
        var stepToUpdate = history[index]
        var op1Changed = false
        var op2Changed = false

        if let newOp1 = newOperand1 {
            stepToUpdate.operand1 = newOp1
            op1Changed = true
        }
        if let newOp2 = newOperand2 {
            stepToUpdate.operand2 = newOp2
            op2Changed = true
        } else if newOperand2 == nil && stepToUpdate.operand2 != nil { // Explicitly cleared op2
            stepToUpdate.operand2 = nil
            op2Changed = true
        }
        
        // If the operation is not equals, recalculate its result.
        // For equals, the result is typically operand1 (which is the result of the previous actual operation).
        if stepToUpdate.operation != .equals {
            // If op1 was not part of this update, and it's not the first step, it should be the result of the previous step.
            let operand1ForCalc = (op1Changed || index == 0) ? stepToUpdate.operand1 : (history[safe: index-1]?.result ?? stepToUpdate.operand1)
            stepToUpdate.result = calculateStepResult(operand1: operand1ForCalc,
                                                     operand2: stepToUpdate.operand2,
                                                     operation: stepToUpdate.operation)
            if !op1Changed && index > 0 { // If op1 was derived, update it in the step for consistency
                stepToUpdate.operand1 = operand1ForCalc
            }
        } else { // For .equals step
            if index > 0 { // Result of equals is result of previous step.
                stepToUpdate.result = history[safe: index-1]?.result ?? stepToUpdate.operand1
            } else { // Equals is the first step, result is its own operand1.
                stepToUpdate.result = stepToUpdate.operand1
            }
        }
        
        history[index] = stepToUpdate
        recalculate(from: index + 1) // Recalculate subsequent steps
        saveHistory()
    }

    func insertStep(step: CalculationStep, at index: Int) {
        var mutableStep = step
        
        // Determine operand1 for the new step based on context if not explicitly set (e.g. to 0 by UI)
        if index > 0 && mutableStep.operand1 == 0 { // Assuming 0 might be placeholder from UI for "use previous result"
            mutableStep.operand1 = history[safe: index-1]?.result ?? 0
        }

        if mutableStep.result == nil { // Calculate result if not provided (usually the case for new steps)
            if mutableStep.operation == .equals {
                mutableStep.result = mutableStep.operand1 // For equals, result is operand1
            } else {
                mutableStep.result = calculateStepResult(operand1: mutableStep.operand1, operand2: mutableStep.operand2, operation: mutableStep.operation)
            }
        }

        history.insert(mutableStep, at: index)
        recalculate(from: index + 1) 
        saveHistory()
    }
    
    private func recalculate(from startIndex: Int) {
        if history.isEmpty && startIndex == 0 {
            currentDisplayValue = "0"
            // saveHistory() // Not here, caller of recalculate should save if it's a user action.
            return
        }
        
        var previousStepResult: Double? = (startIndex > 0 && startIndex < history.count) ? history[safe: startIndex-1]?.result : nil

        for i in startIndex..<history.count {
            var currentStep = history[i]
            var op1ForCurrentStep = previousStepResult ?? currentStep.operand1
            
            // If the step being recalculated is not the first step in history,
            // its operand1 should generally be the result of the previous step,
            // unless its operation makes it independent (e.g. it's the start of a new sub-calc, not supported yet)
            // or its operand1 was explicitly set and should be preserved.
            // For now, we assume sequential chaining for recalculation.
            if i > 0 { // If not the first step of the entire history
                 currentStep.operand1 = previousStepResult ?? currentStep.operand1 // Update step's operand1 for consistency
            }


            if currentStep.operation == .equals {
                // Result of equals is the value of its operand1 (which should be result of previous chain)
                currentStep.result = currentStep.operand1 
            } else {
                // For binary ops, operand2 is necessary. If missing, result is nil (or error).
                if currentStep.operand2 == nil {
                    currentStep.result = nil // Or handle as error, or op1 if unary.
                    logger.warning("Recalculating step \(i) (\(currentStep.operation.displayValue)) resulted in nil due to missing operand2.")
                } else {
                    currentStep.result = calculateStepResult(operand1: currentStep.operand1, operand2: currentStep.operand2, operation: currentStep.operation)
                }
            }
            
            history[i] = currentStep
            previousStepResult = currentStep.result
        }
        currentDisplayValue = formatDisplay(value: history.last?.result)
        // saveHistory() // Caller of recalculate should decide if save is needed.
                       // e.g. loadHistory calls recalculate but doesn't need another save.
                       // updateStep/insertStep call recalculate then save.
    }

    func clear() {
        history.removeAll()
        currentDisplayValue = "0"
        currentOperand1 = nil
        pendingOperation = nil
        expectingOperand2 = false
        isDisplayingFinalResult = false // Reset this flag as well
        saveHistory() 
    }

    // MARK: - Persistence
    private func saveHistory() {
        do {
            let encodedHistory = try JSONEncoder().encode(history)
            UserDefaults.standard.set(encodedHistory, forKey: historyKey)
            logger.log("History saved successfully. \(self.history.count) steps.")
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        guard let savedHistoryData = UserDefaults.standard.data(forKey: historyKey) else {
            logger.log("No saved history found.")
            return
        }
        
        do {
            let decodedHistory = try JSONDecoder().decode([CalculationStep].self, from: savedHistoryData)
            self.history = decodedHistory
            logger.log("History loaded successfully. \(self.history.count) steps.")
            
            if !self.history.isEmpty {
                recalculate(from: 0) 
                // After recalculate, the last step's result is in currentDisplayValue.
                // We also need to set isDisplayingFinalResult if the history ends on a result.
                if history.last?.result != nil {
                    isDisplayingFinalResult = true
                }
            } else {
                currentDisplayValue = "0"
                isDisplayingFinalResult = false
            }
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
    
    override init() {
        super.init() 
        loadHistory()
    }

    private func formatDisplay(value: Double?) -> String {
        guard let val = value else { return "Error" } 
        if val.isNaN { return "Error" } 
        if val.isInfinite { return "Error" } 

        if val == floor(val) {
            return String(format: "%.0f", val)
        } else {
            // Basic formatting for decimals. Could be more sophisticated.
            return String(val) 
        }
    }
}

// Safe collection access
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// The String.isResultPlaceholder() extension is no longer needed
// as the isDisplayingFinalResult flag handles the logic for overwriting
// the display after a calculation.
