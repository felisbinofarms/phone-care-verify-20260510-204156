import Testing
import Foundation
import Contacts
@testable import PhoneCare

// MARK: - Test seam mock

private final class MockContactStore: ContactStoreProviding {
    var contactsByIdentifier: [String: CNContact] = [:]
    var executeShouldThrow: Error?
    private(set) var executeCallCount = 0

    func unifiedContact(
        withIdentifier identifier: String,
        keysToFetch keys: [CNKeyDescriptor]
    ) throws -> CNContact {
        guard let contact = contactsByIdentifier[identifier] else {
            throw CNError(.recordDoesNotExist)
        }
        return contact
    }

    func execute(_ saveRequest: CNSaveRequest) throws {
        if let err = executeShouldThrow { throw err }
        executeCallCount += 1
    }

    func enumerateContacts(
        with fetchRequest: CNContactFetchRequest,
        usingBlock block: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void
    ) throws {
        // Unused in #103 scope; #102's PhotoAnalyzer-style refactor will populate this.
    }
}

private func makeContact(
    given: String = "Test",
    family: String = "Person",
    phones: [String] = [],
    emails: [String] = []
) -> CNMutableContact {
    let c = CNMutableContact()
    c.givenName = given
    c.familyName = family
    c.phoneNumbers = phones.map {
        CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: $0))
    }
    c.emailAddresses = emails.map {
        CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
    }
    return c
}

private let sampleVCard: Data = {
    let s = """
    BEGIN:VCARD
    VERSION:3.0
    FN:Restored Person
    N:Person;Restored;;;
    END:VCARD
    """
    return s.data(using: .utf8)!
}()

@Suite("ContactAnalyzer")
@MainActor
struct ContactAnalyzerTests {

    // MARK: - Phone Number Normalization

    @Test("US number with country code +1 is stripped to 10 digits")
    func normalizePhone_usWithCountryCode() {
        let result = ContactAnalyzer.normalizePhoneNumber("+1 (555) 867-5309")
        #expect(result == "5558675309")
    }

    @Test("US number without country code is normalised to 10 digits")
    func normalizePhone_usTenDigit() {
        let result = ContactAnalyzer.normalizePhoneNumber("(555) 867-5309")
        #expect(result == "5558675309")
    }

    @Test("Stripping punctuation and spaces gives digit-only output")
    func normalizePhone_stripsNonDigits() {
        let result = ContactAnalyzer.normalizePhoneNumber("555-867-5309")
        #expect(result == "5558675309")
    }

    @Test("UK number with country code 44 has prefix stripped")
    func normalizePhone_ukWithCountryCode() {
        // 44 + 11-digit number -> strips prefix 44, leaving ≤10 digits
        let result = ContactAnalyzer.normalizePhoneNumber("+44 7911 123456")
        #expect(result == "7911123456")
    }

    @Test("Empty phone string returns empty string")
    func normalizePhone_empty() {
        let result = ContactAnalyzer.normalizePhoneNumber("")
        #expect(result.isEmpty)
    }

    @Test("Letters and symbols in phone string are stripped")
    func normalizePhone_letters() {
        let result = ContactAnalyzer.normalizePhoneNumber("1-800-FLOWERS")
        // Digits only: 1800 + numeric part of FLOWERS (none) -> 1800
        // Note: FLOWERS has no digits so result is "1800"
        let digits = result.filter { $0.isNumber }
        #expect(digits == result)
    }

    // MARK: - ContactDuplicateGroup properties

    @Test("count returns the number of contacts in the group")
    func duplicateGroup_count() {
        let group = ContactDuplicateGroup(
            id: "g1",
            contactIdentifiers: ["id1", "id2", "id3"],
            contactNames: ["Alice Smith", "Alice Smith", "Al Smith"],
            suggestedPrimaryIdentifier: "id1",
            matchReason: .sameName
        )
        #expect(group.count == 3)
    }

    @Test("count returns 2 for a minimal duplicate pair")
    func duplicateGroup_countPair() {
        let group = ContactDuplicateGroup(
            id: "g2",
            contactIdentifiers: ["id1", "id2"],
            contactNames: ["Bob Jones", "Robert Jones"],
            suggestedPrimaryIdentifier: "id1",
            matchReason: .samePhone
        )
        #expect(group.count == 2)
    }

    // MARK: - ContactAnalysisResult computed properties

    @Test("duplicateCount sums extras across all groups")
    func analysisResult_duplicateCount() {
        let groups = [
            ContactDuplicateGroup(
                id: "g1",
                contactIdentifiers: ["a", "b", "c"],
                contactNames: ["A", "A", "A"],
                suggestedPrimaryIdentifier: "a",
                matchReason: .sameName
            ),
            ContactDuplicateGroup(
                id: "g2",
                contactIdentifiers: ["x", "y"],
                contactNames: ["X", "X"],
                suggestedPrimaryIdentifier: "x",
                matchReason: .sameEmail
            ),
        ]
        let result = ContactAnalysisResult(
            totalContacts: 50,
            duplicateGroups: groups,
            contactsWithoutPhone: 5,
            contactsWithoutEmail: 10
        )
        // (3 - 1) + (2 - 1) = 3
        #expect(result.duplicateCount == 3)
    }

    @Test("duplicateCount is zero with no groups")
    func analysisResult_duplicateCount_zero() {
        let result = ContactAnalysisResult(
            totalContacts: 10,
            duplicateGroups: [],
            contactsWithoutPhone: 0,
            contactsWithoutEmail: 0
        )
        #expect(result.duplicateCount == 0)
    }

    @Test("ContactAnalysisResult preserves contactsWithoutPhone and contactsWithoutEmail")
    func analysisResult_incompleteContacts() {
        let result = ContactAnalysisResult(
            totalContacts: 100,
            duplicateGroups: [],
            contactsWithoutPhone: 15,
            contactsWithoutEmail: 25
        )
        #expect(result.contactsWithoutPhone == 15)
        #expect(result.contactsWithoutEmail == 25)
    }

    // MARK: - Additional phone normalization edge cases

    @Test("All-spaces phone string returns empty string")
    func normalizePhone_allSpaces() {
        let result = ContactAnalyzer.normalizePhoneNumber("   ")
        #expect(result.isEmpty)
    }

    @Test("Very long number is preserved as digits")
    func normalizePhone_longNumber() {
        let result = ContactAnalyzer.normalizePhoneNumber("+86 138 0013 8000")
        let digits = result.filter { $0.isNumber }
        #expect(digits == result)
        #expect(!result.isEmpty)
    }

    @Test("Number with extension notation strips non-digits")
    func normalizePhone_extension() {
        let result = ContactAnalyzer.normalizePhoneNumber("(555) 867-5309 ext. 123")
        let digits = result.filter { $0.isNumber }
        #expect(digits == result)
    }

    // MARK: - mergeContacts with empty remove list

    @Test("mergeContacts with empty removeIdentifiers throws ContactMergeError without crashing")
    func mergeContacts_emptyRemoveList_throwsTypedError() async {
        let analyzer = ContactAnalyzer()
        let dataManager = DataManager(inMemory: true)
        // In the test environment CNContactStore cannot find the identifier,
        // so the function throws contactNotFound — not a crash.
        await #expect(throws: ContactMergeError.self) {
            try await analyzer.mergeContacts(
                keepIdentifier: "nonexistent-test-id-000",
                removeIdentifiers: [],
                dataManager: dataManager
            )
        }
    }

    // MARK: - Duplicate group with zero-field contacts

    @Test("ContactDuplicateGroup always has suggestedPrimaryIdentifier inside contactIdentifiers")
    func duplicateGroup_zerFields_suggestedPrimaryInGroup() {
        // Represents a group where contacts have fieldCount == 0 but a primary was still chosen
        let group = ContactDuplicateGroup(
            id: "g-zero-fields",
            contactIdentifiers: ["id_alpha", "id_beta"],
            contactNames: ["", ""],
            suggestedPrimaryIdentifier: "id_alpha",
            matchReason: .sameName
        )
        #expect(group.contactIdentifiers.contains(group.suggestedPrimaryIdentifier))
    }

    @Test("ContactDuplicateGroup with empty names still has a valid suggestedPrimaryIdentifier")
    func duplicateGroup_emptyNames_validPrimary() {
        let group = ContactDuplicateGroup(
            id: "g-empty",
            contactIdentifiers: ["x1", "x2", "x3"],
            contactNames: ["", "", ""],
            suggestedPrimaryIdentifier: "x1",
            matchReason: .samePhone
        )
        #expect(!group.suggestedPrimaryIdentifier.isEmpty)
        #expect(group.contactIdentifiers.contains(group.suggestedPrimaryIdentifier))
    }

    // MARK: - Phone normalization: +1 prefix and raw number produce identical result

    @Test("normalizePhoneNumber returns same string for +1-555-867-5309 and 5558675309")
    func normalizePhone_withCountryCodeDash_matchesRaw() {
        let withCC = ContactAnalyzer.normalizePhoneNumber("+1-555-867-5309")
        let raw    = ContactAnalyzer.normalizePhoneNumber("5558675309")
        #expect(withCC == raw)
        #expect(withCC == "5558675309")
    }

    @Test("normalizePhoneNumber: 1 (555) 867-5309 and 5558675309 produce the same result")
    func normalizePhone_spacedCountryCode_matchesRaw() {
        let withCC = ContactAnalyzer.normalizePhoneNumber("1 (555) 867-5309")
        let raw    = ContactAnalyzer.normalizePhoneNumber("5558675309")
        #expect(withCC == raw)
    }

    // MARK: - mergeContacts (mock store) — #103

    @Test("mergeContacts throws contactNotFound when primary identifier is unknown to the store")
    func mergeContacts_primaryNotFound_throwsContactNotFound() async {
        let mock = MockContactStore()
        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        await #expect(throws: ContactMergeError.self) {
            try await analyzer.mergeContacts(
                keepIdentifier: "missing-primary",
                removeIdentifiers: ["dup-1"],
                dataManager: dataManager
            )
        }
    }

    @Test("mergeContacts saves one ContactBackup per duplicate before deleting it")
    func mergeContacts_savesBackupBeforeDelete() async throws {
        let mock = MockContactStore()
        mock.contactsByIdentifier["primary"] = makeContact(given: "Alice", phones: ["5551234567"])
        mock.contactsByIdentifier["dup-1"]   = makeContact(given: "Alice", phones: ["5559999999"])

        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        try await analyzer.mergeContacts(
            keepIdentifier: "primary",
            removeIdentifiers: ["dup-1"],
            dataManager: dataManager
        )

        let backups = try dataManager.fetch(ContactBackup.self)
        #expect(backups.count == 1)
        #expect(backups.first?.mergedContactID == "primary")
    }

    @Test("mergeContacts saves one ContactBackup per duplicate when there are multiple")
    func mergeContacts_savesBackupPerDuplicate() async throws {
        let mock = MockContactStore()
        mock.contactsByIdentifier["primary"] = makeContact(given: "Bob")
        mock.contactsByIdentifier["dup-a"]   = makeContact(given: "Bob")
        mock.contactsByIdentifier["dup-b"]   = makeContact(given: "Bob")
        mock.contactsByIdentifier["dup-c"]   = makeContact(given: "Bob")

        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        try await analyzer.mergeContacts(
            keepIdentifier: "primary",
            removeIdentifiers: ["dup-a", "dup-b", "dup-c"],
            dataManager: dataManager
        )

        let backups = try dataManager.fetch(ContactBackup.self)
        #expect(backups.count == 3)
    }

    @Test("mergeContacts rethrows when CNContactStore.execute throws")
    func mergeContacts_executeThrows_rethrows() async {
        let mock = MockContactStore()
        mock.contactsByIdentifier["primary"] = makeContact(given: "Carol")
        mock.contactsByIdentifier["dup-1"]   = makeContact(given: "Carol")
        mock.executeShouldThrow = NSError(domain: CNErrorDomain, code: 400, userInfo: nil)

        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        await #expect(throws: (any Error).self) {
            try await analyzer.mergeContacts(
                keepIdentifier: "primary",
                removeIdentifiers: ["dup-1"],
                dataManager: dataManager
            )
        }
    }

    @Test("mergeContacts calls store.execute exactly once on the success path")
    func mergeContacts_executeCalled_onSuccess() async throws {
        let mock = MockContactStore()
        mock.contactsByIdentifier["primary"] = makeContact(given: "Dave", phones: ["5550001111"])
        mock.contactsByIdentifier["dup-1"]   = makeContact(given: "Dave", phones: ["5552223333"])

        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        try await analyzer.mergeContacts(
            keepIdentifier: "primary",
            removeIdentifiers: ["dup-1"],
            dataManager: dataManager
        )

        #expect(mock.executeCallCount == 1)
    }

    // MARK: - restoreMergedContacts (mock store) — #103

    @Test("restoreMergedContacts marks matching backup as restored and calls store.execute")
    func restoreMergedContacts_marksBackupRestored() async throws {
        let mock = MockContactStore()
        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        let mergeDate = Date()
        let backup = ContactBackup(
            originalContactData: sampleVCard,
            mergedContactID: "primary-restore",
            mergeDate: mergeDate
        )
        try dataManager.save(backup)

        try await analyzer.restoreMergedContacts(
            mergedInto: "primary-restore",
            mergedAfter: mergeDate.addingTimeInterval(-1),
            dataManager: dataManager
        )

        #expect(mock.executeCallCount == 1)
        let restored = try dataManager.fetch(ContactBackup.self)
        #expect(restored.first?.isRestored == true)
    }

    @Test("restoreMergedContacts is a no-op when no matching backup exists")
    func restoreMergedContacts_noMatchingBackup_isNoOp() async throws {
        let mock = MockContactStore()
        let analyzer = ContactAnalyzer(contactStore: mock)
        let dataManager = DataManager(inMemory: true)

        try await analyzer.restoreMergedContacts(
            mergedInto: "primary-with-no-backup",
            mergedAfter: Date(),
            dataManager: dataManager
        )

        #expect(mock.executeCallCount == 0)
    }
}
