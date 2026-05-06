import Foundation
import Contacts
import OSLog

// MARK: - Contact Store Test Seam

/// Minimal protocol over CNContactStore. Production code uses the real store
/// via the default init; tests inject a mock to exercise denial, missing-contact,
/// and successful-merge paths deterministically.
protocol ContactStoreProviding: AnyObject {
    func unifiedContact(
        withIdentifier identifier: String,
        keysToFetch keys: [CNKeyDescriptor]
    ) throws -> CNContact

    func execute(_ saveRequest: CNSaveRequest) throws

    func enumerateContacts(
        with fetchRequest: CNContactFetchRequest,
        usingBlock block: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void
    ) throws
}

extension CNContactStore: ContactStoreProviding {}

// MARK: - Contact Duplicate Group

struct ContactDuplicateGroup: Sendable, Identifiable {
    let id: String
    let contactIdentifiers: [String]
    let contactNames: [String]
    let suggestedPrimaryIdentifier: String
    let matchReason: MatchReason

    enum MatchReason: String, Sendable {
        case sameName
        case samePhone
        case sameEmail
        case nameAndPhone
        case nameAndEmail
    }

    var count: Int { contactIdentifiers.count }
}

// MARK: - Contact Analysis Result

struct ContactAnalysisResult: Sendable {
    let totalContacts: Int
    let duplicateGroups: [ContactDuplicateGroup]
    let contactsWithoutPhone: Int
    let contactsWithoutEmail: Int

    var duplicateCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.count - 1 }
    }
}

// MARK: - Contact Analyzer

@MainActor
@Observable
final class ContactAnalyzer {

    // MARK: - State

    private(set) var result: ContactAnalysisResult?
    private(set) var isAnalyzing: Bool = false
    private(set) var progress: Double = 0.0
    private(set) var statusMessage: String = ""

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "ContactAnalyzer")
    private let contactStore: ContactStoreProviding

    // MARK: - Init

    init(contactStore: ContactStoreProviding = CNContactStore()) {
        self.contactStore = contactStore
    }

    // MARK: - Analyze

    func analyze() async -> ContactAnalysisResult {
        isAnalyzing = true
        progress = 0.0
        statusMessage = "Reviewing contacts..."

        defer {
            isAnalyzing = false
            progress = 1.0
        }

        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authStatus == .authorized else {
            let emptyResult = ContactAnalysisResult(
                totalContacts: 0,
                duplicateGroups: [],
                contactsWithoutPhone: 0,
                contactsWithoutEmail: 0
            )
            result = emptyResult
            return emptyResult
        }

        let analysisResult = await Task.detached {
            await Self.performAnalysis()
        }.value

        progress = 1.0
        statusMessage = "Contact review complete"
        result = analysisResult
        return analysisResult
    }

    // MARK: - Merge Contacts

    func mergeContacts(
        keepIdentifier: String,
        removeIdentifiers: [String],
        dataManager: DataManager
    ) async throws {
        let store = contactStore

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
        ]

        // Fetch the primary contact
        guard let primaryContact = try? store.unifiedContact(
            withIdentifier: keepIdentifier,
            keysToFetch: keysToFetch
        ) else {
            throw ContactMergeError.contactNotFound
        }

        guard let mutablePrimary = primaryContact.mutableCopy() as? CNMutableContact else {
            throw ContactMergeError.mergeFailed("Could not create mutable copy of primary contact")
        }
        let saveRequest = CNSaveRequest()

        for removeID in removeIdentifiers {
            guard let contact = try? store.unifiedContact(
                withIdentifier: removeID,
                keysToFetch: keysToFetch
            ) else { continue }

            // Backup before deleting
            await backupContact(contact, mergedInto: keepIdentifier, dataManager: dataManager)

            // Merge phone numbers not already present
            let existingPhones = Set(mutablePrimary.phoneNumbers.map {
                Self.normalizePhoneNumber($0.value.stringValue)
            })
            for phone in contact.phoneNumbers {
                let normalized = Self.normalizePhoneNumber(phone.value.stringValue)
                if !existingPhones.contains(normalized) {
                    mutablePrimary.phoneNumbers.append(phone)
                }
            }

            // Merge emails not already present
            let existingEmails = Set(mutablePrimary.emailAddresses.map {
                ($0.value as String).lowercased()
            })
            for email in contact.emailAddresses {
                if !existingEmails.contains((email.value as String).lowercased()) {
                    mutablePrimary.emailAddresses.append(email)
                }
            }

            // Merge postal addresses
            let existingPostal = Set(mutablePrimary.postalAddresses.map {
                CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
            })
            for address in contact.postalAddresses {
                let formatted = CNPostalAddressFormatter.string(from: address.value, style: .mailingAddress)
                if !existingPostal.contains(formatted) {
                    mutablePrimary.postalAddresses.append(address)
                }
            }

            // Merge organization if primary is empty
            if mutablePrimary.organizationName.isEmpty && !contact.organizationName.isEmpty {
                mutablePrimary.organizationName = contact.organizationName
            }

            // Merge note
            if mutablePrimary.note.isEmpty && !contact.note.isEmpty {
                mutablePrimary.note = contact.note
            }

            // Merge image if primary has none
            if mutablePrimary.imageData == nil && contact.imageData != nil {
                mutablePrimary.imageData = contact.imageData
            }

            // Delete the duplicate
            guard let mutableDelete = contact.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(mutableDelete)
        }

        saveRequest.update(mutablePrimary)
        try store.execute(saveRequest)

        // Post-execute verification — guards against silent CNContactStore failures
        // where execute() returned without throwing but the store wasn't actually updated.
        let verifyKeys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor]

        guard (try? store.unifiedContact(
            withIdentifier: keepIdentifier,
            keysToFetch: verifyKeys
        )) != nil else {
            throw ContactMergeError.mergeFailed("Primary contact could not be verified after merge.")
        }

        let stillPresent = removeIdentifiers.filter { id in
            (try? store.unifiedContact(withIdentifier: id, keysToFetch: verifyKeys)) != nil
        }
        if !stillPresent.isEmpty {
            throw ContactMergeError.mergeFailed("\(stillPresent.count) duplicate contact(s) were not removed.")
        }

        logger.info("Merged \(removeIdentifiers.count) contacts into \(keepIdentifier)")
    }

    // MARK: - Restore Merged Contacts

    func restoreMergedContacts(
        mergedInto primaryID: String,
        mergedAfter mergeDate: Date,
        dataManager: DataManager
    ) async throws {
        let backups = try dataManager.fetch(
            ContactBackup.self,
            predicate: #Predicate<ContactBackup> {
                $0.mergedContactID == primaryID && $0.mergeDate >= mergeDate && $0.isRestored == false
            }
        )

        guard !backups.isEmpty else { return }

        let store = contactStore
        let saveRequest = CNSaveRequest()

        for backup in backups {
            let contacts = try CNContactVCardSerialization.contacts(with: backup.originalContactData)
            guard let contact = contacts.first else { continue }
            guard let mutable = contact.mutableCopy() as? CNMutableContact else {
                throw ContactMergeError.mergeFailed("Could not create mutable contact for restore")
            }
            saveRequest.add(mutable, toContainerWithIdentifier: nil)
            backup.isRestored = true
        }

        try store.execute(saveRequest)
        try dataManager.saveContext()
        logger.info("Restored \(backups.count) merged contacts for \(primaryID)")
    }

    // MARK: - Backup

    private func backupContact(
        _ contact: CNContact,
        mergedInto primaryID: String,
        dataManager: DataManager
    ) async {
        do {
            let data = try CNContactVCardSerialization.data(with: [contact])
            let backup = ContactBackup(
                originalContactData: data,
                mergedContactID: primaryID,
                mergeDate: Date()
            )
            try dataManager.save(backup)
        } catch {
            logger.error("Failed to backup contact: \(error.localizedDescription)")
        }
    }

    // MARK: - Static Analysis

    private static func performAnalysis() async -> ContactAnalysisResult {
        let store = CNContactStore()

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName

        struct ContactInfo: Sendable {
            let identifier: String
            let givenName: String
            let familyName: String
            let normalizedName: String
            let phoneNumbers: [String]
            let emailAddresses: [String]
            let fieldCount: Int
        }

        var contacts: [ContactInfo] = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let normalizedName = normalizeName(
                    given: contact.givenName,
                    family: contact.familyName
                )

                let phones = contact.phoneNumbers.map {
                    normalizePhoneNumber($0.value.stringValue)
                }

                let emails = contact.emailAddresses.map {
                    ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                }

                let fieldCount = [
                    contact.givenName.isEmpty ? 0 : 1,
                    contact.familyName.isEmpty ? 0 : 1,
                    contact.phoneNumbers.count,
                    contact.emailAddresses.count,
                ].reduce(0, +)

                contacts.append(ContactInfo(
                    identifier: contact.identifier,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    normalizedName: normalizedName,
                    phoneNumbers: phones,
                    emailAddresses: emails,
                    fieldCount: fieldCount
                ))
            }
        } catch {
            return ContactAnalysisResult(
                totalContacts: 0,
                duplicateGroups: [],
                contactsWithoutPhone: 0,
                contactsWithoutEmail: 0
            )
        }

        let totalContacts = contacts.count
        let contactsWithoutPhone = contacts.filter { $0.phoneNumbers.isEmpty }.count
        let contactsWithoutEmail = contacts.filter { $0.emailAddresses.isEmpty }.count

        // Find duplicates
        var duplicateGroups: [ContactDuplicateGroup] = []
        var processedIDs: Set<String> = []

        for i in 0..<contacts.count {
            let contact = contacts[i]
            guard !processedIDs.contains(contact.identifier) else { continue }
            guard !contact.normalizedName.isEmpty || !contact.phoneNumbers.isEmpty else { continue }

            var group: [ContactInfo] = [contact]
            var matchReason: ContactDuplicateGroup.MatchReason = .sameName

            for j in (i + 1)..<contacts.count {
                let candidate = contacts[j]
                guard !processedIDs.contains(candidate.identifier) else { continue }

                // Check name match
                let nameMatch = !contact.normalizedName.isEmpty
                    && !candidate.normalizedName.isEmpty
                    && contact.normalizedName == candidate.normalizedName

                // Check phone match
                let phoneMatch = !contact.phoneNumbers.isEmpty
                    && !candidate.phoneNumbers.isEmpty
                    && !Set(contact.phoneNumbers).isDisjoint(with: Set(candidate.phoneNumbers))

                // Check email match
                let emailMatch = !contact.emailAddresses.isEmpty
                    && !candidate.emailAddresses.isEmpty
                    && !Set(contact.emailAddresses).isDisjoint(with: Set(candidate.emailAddresses))

                if nameMatch && phoneMatch {
                    matchReason = .nameAndPhone
                    group.append(candidate)
                } else if nameMatch && emailMatch {
                    matchReason = .nameAndEmail
                    group.append(candidate)
                } else if nameMatch {
                    matchReason = .sameName
                    group.append(candidate)
                } else if phoneMatch {
                    matchReason = .samePhone
                    group.append(candidate)
                } else if emailMatch {
                    matchReason = .sameEmail
                    group.append(candidate)
                }
            }

            if group.count >= 2 {
                // Suggest the contact with the most filled fields as primary
                guard let best = group.max(by: { $0.fieldCount < $1.fieldCount }) ?? group.first else { continue }

                let names = group.map { info in
                    let name = [info.givenName, info.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return name.isEmpty ? "No name" : name
                }

                let dupGroup = ContactDuplicateGroup(
                    id: UUID().uuidString,
                    contactIdentifiers: group.map(\.identifier),
                    contactNames: names,
                    suggestedPrimaryIdentifier: best.identifier,
                    matchReason: matchReason
                )
                duplicateGroups.append(dupGroup)

                for info in group {
                    processedIDs.insert(info.identifier)
                }
            }
        }

        return ContactAnalysisResult(
            totalContacts: totalContacts,
            duplicateGroups: duplicateGroups,
            contactsWithoutPhone: contactsWithoutPhone,
            contactsWithoutEmail: contactsWithoutEmail
        )
    }

    // MARK: - Name Normalization

    private static func normalizeName(given: String, family: String) -> String {
        let parts = [given, family]
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        return parts.joined(separator: " ")
    }

    // MARK: - Phone Normalization

    static func normalizePhoneNumber(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        return String(digits.suffix(10))
    }
}

// MARK: - Error

enum ContactMergeError: LocalizedError {
    case contactNotFound
    case mergeFailed(String)

    var errorDescription: String? {
        switch self {
        case .contactNotFound:
            return "The contact could not be found."
        case .mergeFailed(let reason):
            return "Contact merge failed: \(reason)"
        }
    }
}
