import SwiftUI
import SwiftData

@main
struct PhoneCareApp: App {
    @State private var appState = AppState()
    @State private var subscriptionManager = SubscriptionManager()
    @State private var permissionManager = PermissionManager()
    @State private var dataManager = DataManager()
    @State private var trialReminderService = TrialReminderService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(subscriptionManager)
                .environment(permissionManager)
                .environment(dataManager)
                .environment(trialReminderService)
                .modelContainer(dataManager.modelContainer)
                .preferredColorScheme(appState.resolvedColorScheme)
                .task {
                    guard !LaunchArguments.contains(LaunchArguments.skipStoreKitForUITests) else { return }
                    subscriptionManager.startTransactionListener()
                    await subscriptionManager.loadProducts()
                    await subscriptionManager.checkEntitlement()
                    await trialReminderService.sync(
                        isInTrial: subscriptionManager.isInTrial,
                        productID: subscriptionManager.currentProductID,
                        expirationDate: subscriptionManager.expirationDate
                    )
                }
                .task {
                    dataManager.enforceRetention()
                }
                .onChange(of: subscriptionManager.isInTrial) { _, _ in
                    Task {
                        await trialReminderService.sync(
                            isInTrial: subscriptionManager.isInTrial,
                            productID: subscriptionManager.currentProductID,
                            expirationDate: subscriptionManager.expirationDate
                        )
                    }
                }
        }
    }
}
