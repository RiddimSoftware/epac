import SwiftUI
import SwiftData

struct PostalCodeSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PostalCodeViewModel()
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)

                        Text(NSLocalizedString("riding.setup.title", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("riding.setup.subtitle", comment: ""))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 14) {
                        TextField(NSLocalizedString("riding.setup.placeholder", comment: ""), text: $viewModel.postalCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .onSubmit { Task { await viewModel.lookup(modelContext: modelContext) } }

                        Button {
                            Task { await viewModel.lookup(modelContext: modelContext) }
                        } label: {
                            Group {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(NSLocalizedString("riding.setup.lookupButton", comment: ""))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isLoading || viewModel.postalCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal)

                    if let error = viewModel.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if let result = viewModel.result {
                        resultCard(result)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("riding.setup.navTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("riding.setup.skip", comment: "")) { onDone() }
                }
            }
        }
    }

    @ViewBuilder
    private func resultCard(_ result: RidingLookupResult) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(result.ridingName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                if !result.memberName.isEmpty {
                    Text(result.memberName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !result.partyName.isEmpty {
                        Text(result.partyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(NSLocalizedString("riding.result.mpLoadingLater", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            Button {
                viewModel.confirm()
                HapticEngine.success()
                onDone()
                ReviewRequestManager.shared.requestReviewIfAppropriate()
            } label: {
                Text(NSLocalizedString("riding.setup.confirmButton", comment: ""))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
}
