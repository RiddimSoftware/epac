import SwiftData
import SwiftUI

private enum PostalCodeSetupLayout {
    static let rootSpacing: CGFloat = 28
    static let titleSpacing: CGFloat = 12
    static let iconSize: CGFloat = 56
    static let titleTopPadding = EpacSpacing.xl
    static let formSpacing: CGFloat = 14
    static let fieldCornerRadius = EpacCornerRadius.m
    static let errorSpacing = EpacSpacing.s
    static let resultSpacing = EpacSpacing.m
    static let resultTextSpacing = EpacSpacing.xs
}

struct PostalCodeSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PostalCodeViewModel()
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PostalCodeSetupLayout.rootSpacing) {
                    VStack(spacing: PostalCodeSetupLayout.titleSpacing) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: PostalCodeSetupLayout.iconSize))
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
                    .padding(.top, PostalCodeSetupLayout.titleTopPadding)

                    VStack(spacing: PostalCodeSetupLayout.formSpacing) {
                        TextField(NSLocalizedString("riding.setup.placeholder", comment: ""), text: $viewModel.postalCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(PostalCodeSetupLayout.fieldCornerRadius)
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
                            .cornerRadius(PostalCodeSetupLayout.fieldCornerRadius)
                        }
                        .disabled(viewModel.isLoading || viewModel.postalCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal)

                    if let error = viewModel.errorMessage {
                        HStack(alignment: .top, spacing: PostalCodeSetupLayout.errorSpacing) {
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
        VStack(spacing: PostalCodeSetupLayout.resultSpacing) {
            VStack(spacing: PostalCodeSetupLayout.resultTextSpacing) {
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
            .cornerRadius(PostalCodeSetupLayout.fieldCornerRadius)

            Button {
                viewModel.confirm()
                HapticEngine.success()
                onDone()
            } label: {
                Text(NSLocalizedString("riding.setup.confirmButton", comment: ""))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(PostalCodeSetupLayout.fieldCornerRadius)
            }
        }
        .padding(.horizontal)
    }
}
