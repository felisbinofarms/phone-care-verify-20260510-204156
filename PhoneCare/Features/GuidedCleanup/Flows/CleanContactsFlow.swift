import SwiftUI

struct CleanContactsFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var coordinator = GuidedFlowCoordinator(
        flowType: .cleanContacts,
        steps: [
            FlowStep(
                id: "intro",
                title: "Let's clean up your contacts",
                description: "We will find duplicate contacts and help you merge them.",
                icon: "person.2.fill",
                isSkippable: false
            ),
            FlowStep(
                id: "scan",
                title: "Scanning contacts",
                description: "Looking through your address book for duplicates and similar entries.",
                icon: "magnifyingglass",
                isSkippable: false
            ),
            FlowStep(
                id: "review",
                title: "Review duplicates",
                description: "For each group, choose which information to keep. We will combine everything into one contact.",
                icon: "person.crop.circle.badge.checkmark",
                isSkippable: true
            ),
            FlowStep(
                id: "merge",
                title: "Safe to merge",
                description: "Before merging, we save a backup. You can undo any merge within 30 days.",
                icon: "shield.checkered",
                isSkippable: false
            ),
        ]
    )

    @State private var contactAnalyzer = ContactAnalyzer()
    @State private var scanResult: ContactAnalysisResult?
    @State private var isScanning = false
    @State private var isMerging = false
    @State private var mergeError = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.isComplete {
                    CompletionCelebrationView(
                        flowType: .cleanContacts,
                        itemsCleaned: coordinator.itemsCleaned,
                        bytesFreed: coordinator.bytesFreed,
                        onDone: { dismiss() }
                    )
                } else if let step = coordinator.currentStep {
                    FlowStepView(
                        step: step,
                        stepNumber: coordinator.currentStepNumber,
                        totalSteps: coordinator.totalSteps,
                        canGoBack: coordinator.canGoBack,
                        onConfirm: { handleConfirm(for: step) },
                        onSkip: { coordinator.skip() },
                        onBack: { coordinator.back() }
                    ) {
                        stepContent(for: step)
                    }
                }
            }
            .navigationTitle("Clean Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibleTapTarget()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallBottomSheet(trigger: .gatedCTA)
            }
        }
    }

    // MARK: - Step Actions

    private func handleConfirm(for step: FlowStep) {
        switch step.id {
        case "scan":
            guard scanResult != nil else { return }
            coordinator.next()
        case "merge":
            mergeAllDuplicates()
        default:
            coordinator.next()
        }
    }

    private func mergeAllDuplicates() {
        guard let result = scanResult, !result.duplicateGroups.isEmpty else {
            coordinator.next()
            return
        }

        guard subscriptionManager.isPremium else {
            showPaywall = true
            return
        }

        isMerging = true
        mergeError = false
        Task { @MainActor in
            var mergedCount = 0
            var failedCount = 0
            for group in result.duplicateGroups {
                let removeIDs = group.contactIdentifiers.filter { $0 != group.suggestedPrimaryIdentifier }
                guard !removeIDs.isEmpty else { continue }
                do {
                    try await contactAnalyzer.mergeContacts(
                        keepIdentifier: group.suggestedPrimaryIdentifier,
                        removeIdentifiers: removeIDs,
                        dataManager: dataManager
                    )
                    mergedCount += removeIDs.count
                } catch {
                    failedCount += 1
                }
            }
            isMerging = false
            if mergedCount > 0 {
                coordinator.recordCleanup(items: mergedCount, bytes: 0)
                coordinator.next()
            } else if failedCount > 0 {
                mergeError = true
            } else {
                coordinator.next()
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: FlowStep) -> some View {
        switch step.id {
        case "scan":
            VStack(spacing: PCTheme.Spacing.md) {
                if isScanning {
                    ProgressView()
                        .controlSize(.large)
                    Text("This usually takes just a few seconds.")
                        .typography(.footnote, color: .pcTextSecondary)
                } else if let result = scanResult {
                    let count = result.duplicateCount
                    Image(systemName: count > 0 ? "person.2.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.pcAccent)
                    Text(count > 0 ? "Found \(count) duplicate contacts" : "No duplicates found")
                        .typography(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCTheme.Spacing.lg)
            .task {
                guard scanResult == nil, !isScanning else { return }
                isScanning = true
                scanResult = await contactAnalyzer.analyze()
                isScanning = false
            }
        case "review":
            CardView {
                VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                    if let result = scanResult {
                        Text("\(result.duplicateGroups.count) groups to merge")
                            .typography(.subheadline)
                    }
                    tipRow("We show you duplicates side by side")
                    tipRow("Pick which name, phone, and email to keep")
                    tipRow("Everything is combined into one clean contact")
                }
            }
        case "merge":
            CardView {
                VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                    if isMerging {
                        HStack(spacing: PCTheme.Spacing.sm) {
                            ProgressView()
                            Text("Merging contacts...")
                                .typography(.subheadline, color: .pcTextSecondary)
                        }
                    } else if mergeError {
                        Text("Some contacts couldn't be merged. You can try again or skip this step.")
                            .typography(.subheadline, color: .pcTextSecondary)
                    } else {
                        Text("Your contacts are safe:")
                            .typography(.subheadline)
                    }
                    tipRow("A backup is created before any changes")
                    tipRow("Undo any merge within 30 days")
                    tipRow("Original contacts are backed up for 30 days")
                }
            }
        default:
            EmptyView()
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: PCTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.pcAccent)
                .voiceOverHidden()
            Text(text)
                .typography(.footnote, color: .pcTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
