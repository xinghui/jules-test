import SwiftUI

struct InsertStepView: View {
    @Binding var showSheet: Bool
    
    // State for the new step's details
    @State private var operand1String: String = ""
    @State private var selectedOperation: OperationType = .add // Default operation
    @State private var operand2String: String = ""

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    let onSave: (CalculationStep) -> Void
    
    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        formatter.usesGroupingSeparator = false // Easier for editing
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Calculation Step Details")) {
                    TextField("Operand 1", text: $operand1String)
                        .keyboardType(.decimalPad)
                    
                    Picker("Operation", selection: $selectedOperation) {
                        ForEach(OperationType.allCases.filter { $0 != .equals }, id: \.self) { op in
                            Text(op.displayValue).tag(op)
                        }
                    }
                    
                    // Operand 2 is relevant for binary operations
                    // For simplicity, we'll always show it.
                    // Could be conditionally hidden if selectedOperation was unary (not in this app)
                    TextField("Operand 2 (Optional for some operations)", text: $operand2String)
                        .keyboardType(.decimalPad)
                }
                
                Section {
                    Button("Save Step") {
                        guard let op1Value = numberFormatter.number(from: operand1String)?.doubleValue else {
                            alertMessage = "Invalid input for Operand 1. Please enter a valid number."
                            showAlert = true
                            return
                        }
                        
                        var op2Value: Double? = nil
                        if !operand2String.isEmpty {
                            guard let parsedOp2 = numberFormatter.number(from: operand2String)?.doubleValue else {
                                alertMessage = "Invalid input for Operand 2. Please enter a valid number or leave it empty."
                                showAlert = true
                                return
                            }
                            op2Value = parsedOp2
                        }
                        // Note: Unlike EditStepView, for a new step, if op2String is empty, op2Value remains nil.
                        // This is generally fine as CalculationEngine will handle it.
                        
                        let newStep = CalculationStep(operand1: op1Value, operand2: op2Value, operation: selectedOperation, result: nil)
                        onSave(newStep)
                        showSheet = false
                    }
                    Button("Cancel") {
                        showSheet = false
                    }
                }
            }
            .navigationTitle("Insert New Step")
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

// Preview
struct InsertStepView_Previews: PreviewProvider {
    static var previews: some View {
        InsertStepView(showSheet: .constant(true)) { step in
            print("New step to save: \(step.operand1) \(step.operation.displayValue) \(step.operand2 ?? 0.0)")
        }
    }
}
