import SwiftUI

struct ContentView: View {
    @StateObject private var calculationEngine = CalculationEngine()
    @State private var selectedStepID: UUID? = nil
    
    // For Edit Sheet
    @State private var showEditSheet: Bool = false
    @State private var editingStep: CalculationStep? = nil
    @State private var editOperand1String: String = ""
    @State private var editOperand2String: String = ""
    
    // For Insert Sheet
    @State private var showInsertSheet: Bool = false
    
    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8 // Consistent precision
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        formatter.usesGroupingSeparator = false // Easier for editing
        return formatter
    }()

    // Define button layout and content
    let buttons: [[CalculatorButtonType]] = [
        [.clear, .plusMinus, .percent, .operation(.divide)],
        [.digit(7), .digit(8), .digit(9), .operation(.multiply)],
        [.digit(4), .digit(5), .digit(6), .operation(.subtract)],
        [.digit(1), .digit(2), .digit(3), .operation(.add)],
        [.digit(0), .decimal, .operation(.equals)]
    ]

    // Define columns for the grid
    var columns: [GridItem] {
        // For the last row, to make '0' span two columns:
        // We need 3 items in the last row if 0 spans 2.
        // The first three rows have 4 items.
        // This approach assumes a fixed layout where '0' spans.
        // A simpler approach is to have 4 columns always and '0' takes one.
        // For this iteration, let's use a flexible grid that can adapt.
        // We'll make the '0' button wider using a custom view or frame.
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) { // Reduced spacing for tighter layout
                // History View Area
                HistoryView(calculationEngine: calculationEngine, selectedStepID: $selectedStepID)
                    .frame(height: geometry.size.height * 0.25) // Assign a portion of height to history
                    .onChange(of: selectedStepID) { oldValue, newValue in
                        // This logic is primarily for triggering the edit sheet.
                        // We keep it separate from insert logic.
                        if !showInsertSheet { // Avoid re-triggering edit if insert sheet was just closed causing selection change
                            if let stepId = newValue,
                               let step = calculationEngine.history.first(where: { $0.id == stepId }) {
                                editingStep = step
                                editOperand1String = numberFormatter.string(from: NSNumber(value: step.operand1)) ?? "\(step.operand1)"
                                if let op2 = step.operand2 {
                                    editOperand2String = numberFormatter.string(from: NSNumber(value: op2)) ?? "\(op2)"
                                } else {
                                    editOperand2String = "" // Clear if no operand2
                                }
                                showEditSheet = true
                            } else {
                                showEditSheet = false
                            }
                        }
                    }
                    .sheet(isPresented: $showEditSheet) { // Edit Sheet
                        if let stepToEdit = editingStep {
                            EditStepView(
                                showSheet: $showEditSheet,
                                operand1String: $editOperand1String,
                                operand2String: $editOperand2String,
                                currentStep: stepToEdit,
                                onSave: { newOp1, newOp2 in
                                    if let id = editingStep?.id {
                                        calculationEngine.updateStep(stepId: id, newOperand1: newOp1, newOperand2: newOp2)
                                    }
                                    selectedStepID = nil // Deselect after saving
                                }
                            )
                        }
                    }

                // Display Area & Insert Button Row
                HStack {
                    if selectedStepID != nil {
                        Button(action: {
                            showInsertSheet = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .padding(.leading)
                        }
                        .disabled(selectedStepID == nil) // Technically redundant if only shown when selectedStepID != nil
                    }
                    Spacer()
                    Text(calculationEngine.currentDisplayValue)
                        .font(.system(size: geometry.size.width * 0.18, weight: .light)) // Adjusted font size
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, selectedStepID != nil ? 0 : 20) // Adjust padding if button is present
                }
                .frame(height: geometry.size.height * 0.15) // Adjusted height for display
                .background(Color.black)
                .sheet(isPresented: $showInsertSheet) { // Insert Sheet
                    InsertStepView(showSheet: $showInsertSheet) { newStep in
                        if let selectedId = selectedStepID,
                           let index = calculationEngine.history.firstIndex(where: { $0.id == selectedId }) {
                            calculationEngine.insertStep(step: newStep, at: index)
                        } else {
                            // If no selection, or selectedID somehow invalid, append to end.
                            // Or handle as error / disable button more strictly.
                            // For now, let's assume selectedStepID ensures a valid index.
                            // If selectedStepID is nil, this sheet shouldn't even be presented.
                            print("Error: No valid selection to insert before, or index out of bounds.")
                        }
                        selectedStepID = nil // Deselect after insert
                    }
                }


                // Buttons Area
                VStack(spacing: 12) { // Spacing for button rows
                    ForEach(buttons, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { buttonType in
                                Button(action: {
                                    handleButtonPress(buttonType)
                                }) {
                                    buttonView(buttonType, geometry: geometry)
                                }
                                .accessibilityLabel(buttonType.accessibilityLabel)
                            }
                        }
                    }
                }
            }
            .padding(.bottom)
            .background(Color.black.edgesIgnoringSafeArea(.all)) // Background for the whole calculator
        }
    }

    // Handle button presses
    private func handleButtonPress(_ buttonType: CalculatorButtonType) {
        switch buttonType {
        case .digit(let number):
            calculationEngine.inputDigit(String(number))
        case .operation(let op):
            calculationEngine.setOperation(op)
        case .decimal:
            calculationEngine.inputDigit(".")
        case .clear:
            calculationEngine.clear()
        case .plusMinus:
            // TODO: Implement plusMinus logic in CalculationEngine
            print("PlusMinus pressed - Not implemented yet")
        case .percent:
            // TODO: Implement percent logic in CalculationEngine
            print("Percent pressed - Not implemented yet")
        }
    }

    // View for individual buttons
    @ViewBuilder
    private func buttonView(_ buttonType: CalculatorButtonType, geometry: GeometryProxy) -> some View {
        let buttonSize = calculateButtonSize(geometry: geometry, buttonType: buttonType)
        
        Text(buttonType.displayValue)
            .font(.system(size: buttonSize.height * 0.4)) // Responsive font for button text
            .frame(width: buttonSize.width, height: buttonSize.height)
            .background(buttonType.backgroundColor)
            .foregroundColor(buttonType.foregroundColor)
            .cornerRadius(buttonSize.height / 2) // Circular buttons
    }
    
    private func calculateButtonSize(geometry: GeometryProxy, buttonType: CalculatorButtonType) -> CGSize {
        let spacing: CGFloat = 12 // Horizontal spacing between buttons in a row
        let verticalSpacing: CGFloat = 12 // Vertical spacing between button rows
        let bottomPadding: CGFloat = 12 // Padding at the bottom of the button area

        // Calculate available width for buttons
        // The number of columns is fixed at 4 for this calculation.
        let numberOfColumns: CGFloat = 4
        let totalHorizontalSpacing = spacing * (numberOfColumns - 1)
        // Assuming some horizontal padding for the whole VStack of buttons, let's say 12 on each side
        let horizontalPaddingForButtonArea: CGFloat = 12 * 2
        let availableWidth = geometry.size.width - totalHorizontalSpacing - horizontalPaddingForButtonArea
        
        let baseButtonWidth = availableWidth / numberOfColumns
        
        // Calculate available height for buttons
        // Total height for buttons area: remaining height after history and display
        let remainingHeight = geometry.size.height * (1 - 0.25 - 0.15) // History (0.25) + Display (0.15)
        let numberOfRows = CGFloat(buttons.count)
        let totalVerticalSpacing = verticalSpacing * (numberOfRows - 1)
        let availableHeight = remainingHeight - totalVerticalSpacing - bottomPadding
        
        let buttonHeight = min(baseButtonWidth, availableHeight / numberOfRows) // Ensure buttons are not too tall
                                                                       // Or make them square: baseButtonWidth
        
        if case .digit(0) = buttonType {
            // '0' button spans 2 columns width plus the spacing between them
            let zeroButtonWidth = (baseButtonWidth * 2) + spacing
            return CGSize(width: zeroButtonWidth, height: buttonHeight)
        }
        return CGSize(width: baseButtonWidth, height: buttonHeight)
    }
}

// Sheet View for Editing a Calculation Step
struct EditStepView: View {
    @Binding var showSheet: Bool
    @Binding var operand1String: String
    @Binding var operand2String: String
    let currentStep: CalculationStep
    let onSave: (Double?, Double?) -> Void

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Edit Step: \(currentStep.displayString(formatter: numberFormatter))")) {
                    TextField("Operand 1", text: $operand1String)
                        .keyboardType(.decimalPad)
                    
                    // Only show Operand 2 if the operation is not 'equals' or if it originally had an operand2
                    // For simplicity here, we'll always show it if the original step had it,
                    // or if the operation is not equals.
                    // A more robust solution might disable it based on operation type.
                    if currentStep.operation != .equals || currentStep.operand2 != nil {
                        TextField("Operand 2", text: $operand2String)
                            .keyboardType(.decimalPad)
                    } else {
                        Text("Operand 2: N/A for this step")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    Button("Save") {
                        // Validate Operand 1
                        guard let op1Value = numberFormatter.number(from: operand1String)?.doubleValue else {
                            alertMessage = "Invalid input for Operand 1. Please enter a valid number."
                            showAlert = true
                            return
                        }
                        
                        var op2Value: Double? = nil
                        if !operand2String.isEmpty {
                            guard let parsedOp2 = numberFormatter.number(from: operand2String)?.doubleValue else {
                                alertMessage = "Invalid input for Operand 2. Please enter a valid number or leave it empty if not applicable."
                                showAlert = true
                                return
                            }
                            op2Value = parsedOp2
                        } else if currentStep.operand2 != nil && currentStep.operation != .equals {
                            // If operand2 was originally present and is now empty (and not for an equals step where it might be optional by design)
                            // Check if the operation *requires* an operand2. Most binary operations do.
                            // For simplicity, we allow clearing op2, CalculationEngine will handle if it's valid for the op.
                            // If op2 is cleared for an operation that needs it, CalculationEngine.calculateStepResult might return nil/NaN.
                            op2Value = nil 
                        }
                        
                        onSave(op1Value, op2Value)
                        showSheet = false
                    }
                    Button("Cancel") {
                        showSheet = false
                    }
                }
            }
            .navigationTitle("Edit Calculation")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showSheet = false }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Input Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
}


// Define button types and their properties
enum CalculatorButtonType: Hashable, Identifiable {
    case digit(Int)
    case operation(OperationType)
    case decimal
    case clear // AC
    case plusMinus // +/-
    case percent // %

    var id: String {
        switch self {
        case .digit(let num): return "digit-\(num)"
        case .operation(let op): return "op-\(op.displayValue)"
        case .decimal: return "decimal"
        case .clear: return "clear"
        case .plusMinus: return "plusMinus"
        case .percent: return "percent"
        }
    }

    var displayValue: String {
        switch self {
        case .digit(let number): return String(number)
        case .operation(let op): return op.displayValue
        case .decimal: return "."
        case .clear: return "AC"
        case .plusMinus: return "±"
        case .percent: return "%"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .digit, .decimal:
            return Color(white: 0.2) // Dark gray for numbers
        case .operation:
            return .orange // Orange for operations
        case .clear, .plusMinus, .percent:
            return Color(white: 0.6) // Light gray for others
        }
    }

    var foregroundColor: Color {
        switch self {
        case .clear, .plusMinus, .percent:
            return .black
        default:
            return .white
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .digit(let number): return String(number)
        case .operation(let op):
            switch op {
            case .add: return "Add"
            case .subtract: return "Subtract"
            case .multiply: return "Multiply"
            case .divide: return "Divide"
            case .equals: return "Equals"
            }
        case .decimal: return "Decimal point"
        case .clear: return "All Clear"
        case .plusMinus: return "Plus Minus toggle sign"
        case .percent: return "Percent"
        }
    }
}

// Make OperationType Hashable if it's not already (it is CaseIterable, Identifiable)
// For CalculatorButtonType to be Hashable when it has an associated value of OperationType,
// OperationType itself must be Hashable.
// Since OperationType is an enum and its rawValue is Int (implicitly if not specified otherwise, or String),
// or if it's just CaseIterable and Identifiable with `id: Self {self}`, it's inherently Hashable.

#Preview {
    ContentView()
}

// Ensure ContentView has the .sheet modifier
extension ContentView {
    var editSheetView: some View {
        // The EditStepView is defined above or in a separate file.
        // This is just to ensure the .sheet modifier is correctly placed in ContentView's body.
        // The actual sheet presentation is handled by the .sheet modifier in the body of ContentView.
        // This computed property is not strictly necessary if .sheet is directly in body.
        EmptyView() 
    }
}
