import SwiftUI
import AffirmAlarmCore

struct AffirmationEditView: View {
    @ObservedObject var viewModel: AffirmationEditViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let error = viewModel.validationError {
                Text(error).foregroundColor(.red)
            }
            ForEach($viewModel.affirmations) { $affirmation in
                TextField("Affirmation", text: $affirmation.text)
            }
            .onDelete { viewModel.removeAffirmation(at: $0) }
            .onMove { viewModel.moveAffirmation(from: $0, to: $1) }

            Button("Add affirmation") { viewModel.addAffirmation() }
                .accessibilityIdentifier("addAffirmationButton")
        }
        .toolbar { EditButton() }
        .navigationTitle("Your Affirmations")
        .safeAreaInset(edge: .bottom) {
            Button("Save") {
                if viewModel.save() { dismiss() }
            }
            .accessibilityIdentifier("saveAffirmationsButton")
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
