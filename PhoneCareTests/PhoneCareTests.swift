import Testing
import Foundation
@testable import PhoneCare

@Suite("PhoneCare Sanity Checks")
struct PhoneCareTests {

    @Test("Module imports successfully")
    func moduleImports() {
        // If this compiles and runs, the PhoneCare module is accessible.
        #expect(true)
    }

    @Test("Health score calculator is available")
    func calculatorAvailable() {
        let input = HealthScoreInput(
            totalStorageBytes: 100,
            usedStorageBytes: 50,
            totalPhotos: 0,
            duplicatePhotos: 0,
            totalContacts: 0,
            duplicateContacts: 0,
            batteryHealth: 1.0,
            batteryLevel: 1.0,
            totalPermissions: 0,
            appropriatelySetPermissions: 0
        )
        let result = HealthScoreCalculator.calculate(from: input)
        #expect(result.compositeScore >= 0)
        #expect(result.compositeScore <= 100)
    }

    @Test("Privacy manifesto copy stays aligned with the zero-data-collection promise")
    func privacyManifestoCopyIsConsistent() {
        #expect(PrivacyManifesto.summaryText.contains("All processing stays on your iPhone"))
        #expect(PrivacyManifesto.detailsText.contains("fully on-device"))
        #expect(PrivacyManifesto.detailsText.contains("do not collect personal data"))
        #expect(PrivacyManifesto.noCollectionPoints.contains("No third-party analytics SDKs"))
        #expect(PrivacyManifesto.appStoreLabelValue == "Data Not Collected")
    }
}
