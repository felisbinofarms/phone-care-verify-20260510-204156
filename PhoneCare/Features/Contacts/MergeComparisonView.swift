import SwiftUI

struct MergeComparisonView: View {
    let group: DuplicateContactGroup
    var onMerge: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var fields: [ContactField]
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager
        @State private var showMergeConfirmation = false
        @State private var showPaywall = false

    init(group: DuplicateContactGroup, onMerge: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.group = group
        self.onMerge = onMerge
        self.onCancel = onCancel
        _fields = State(initialValue: group.fields)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PCTheme.Spacing.lg) {
                    // Header
                    headerSection

                    // Field-by-field comparison
                    fieldComparison

                    // Merge button
                    Button("Merge Contacts") {
                        if subscriptionManager.isPremium {
                            showMergeConfirmation = true
                        } else {
                            showPaywall = true
                        }
                    }
                    .primaryCTAStyle()
                    .padding(.top, PCTheme.Spacing.md)
                }
                .padding(.horizontal, PCTheme.Spacing.md)
                .padding(.top, PCTheme.Spacing.md)
                .padding(.bottom, PCTheme.Spacing.xl)
            }
            .background(Color.pcBackground)
            .navigationTitle("Compare & Merge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                    .accessibleTapTarget()
                }
            }
            }
            .confirmationDialog(
                "Merge \(group.contactIDs.count) contacts into one?",
                isPresented: $showMergeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Merge Contacts", role: .destructive) {
                    onMerge?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will combine \(group.contactIDs.count) entries into a single contact. You can undo this for 30 seconds after merging.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallBottomSheet()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        CardView {
            VStack(spacing: PCTheme.Spacing.sm) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.pcAccent)
                    .voiceOverHidden()

                Text(group.name)
                    .typography(.title3)

                Text("\(group.contactIDs.count) entries found")
                    .typography(.subheadline, color: .pcTextSecondary)

                Text("Choose which information to keep for each field. The most complete option is highlighted.")
                    .typography(.footnote, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Field Comparison

    private var fieldComparison: some View {
        VStack(spacing: PCTheme.Spacing.sm) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { fieldIndex, field in
                CardView {
                    VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                        Text(field.label)
                            .typography(.headline)
                            .voiceOverHeading()

                        ForEach(Array(field.values.enumerated()), id: \.offset) { valueIndex, value in
                            let isSelected = field.selectedIndex == valueIndex
                            let isMostComplete = mostCompleteIndex(for: field) == valueIndex

                            Button {
                                fields[fieldIndex].selectedIndex = valueIndex
                            } label: {
                                HStack(spacing: PCTheme.Spacing.sm) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? Color.pcAccent : Color.pcBorder)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(value.isEmpty ? "(empty)" : value)
                                            .typography(.subheadline, color: value.isEmpty ? .pcTextSecondary : .pcTextPrimary)

                                        if isMostComplete && !value.isEmpty {
                                            Text("Most complete")
                                                .typography(.caption, color: .pcAccent)
                                        }
                                    }

                                    Spacer()

                                    Text("Contact \(valueIndex + 1)")
                                        .typography(.caption, color: .pcTextSecondary)
                                }
                                .padding(.vertical, PCTheme.Spacing.xs)
                            }
                            .buttonStyle(.plain)
                            .accessibleTapTarget()
                            .accessibilityLabel("\(field.label): \(value.isEmpty ? "empty" : value), Contact \(valueIndex + 1)")
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            .accessibilityHint("Double tap to select this value")

                            if valueIndex < field.values.count - 1 {
                                Divider()
                                    .foregroundStyle(Color.pcBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func mostCompleteIndex(for field: ContactField) -> Int {
        var bestIndex = 0
        var bestLength = 0
        for (index, value) in field.values.enumerated() {
            if value.count > bestLength {
                bestLength = value.count
                bestIndex = index
            }
        }
        return bestIndex
    }
}
