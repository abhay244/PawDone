import StoreKit
import SwiftUI

struct AccountView: View {
    @Environment(PetStore.self) private var store
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var isSavingName = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    @State private var shownInvite: Invite?
    @State private var removingMember: UUID?
    @State private var leaving: Membership?
    @State private var isJoining = false
    @State private var isShowingPaywall = false
    @State private var isManagingSubscription = false

    var body: some View {
        NavigationStack {
            Form {
                petSection
                householdSection
                premiumSection
                notificationsSection
                nameSection
                otherHouseholdsSection

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Account")
            .onAppear { name = store.myName }
            .sheet(item: $shownInvite) { invite in
                InviteSheet(invite: invite, petName: store.pet?.name ?? "your pet")
            }
            .sheet(isPresented: $isJoining) {
                JoinHouseholdView()
            }
            .confirmationDialog(
                "Remove \(store.name(for: removingMember))?",
                isPresented: isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let removingMember { remove(removingMember) }
                }
            } message: {
                Text("They'll stop seeing \(store.pet?.name ?? "your pet") and getting its notifications.")
            }
            .confirmationDialog(
                "Leave \(leaving?.ownerName ?? "this")'s household?",
                isPresented: isConfirmingLeave,
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    if let leaving { leave(leaving) }
                }
            } message: {
                Text("You'll need a new invite code to join again.")
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
            .onChange(of: isManagingSubscription) { _, isOpen in
                // Pick up a cancellation or plan change made in the sheet.
                if !isOpen { Task { await store.refreshPremium() } }
            }
            .alert("Something went wrong", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var petSection: some View {
        if let pet = store.pet {
            Section("Pet") {
                if store.isOwner {
                    NavigationLink {
                        PetEditView()
                    } label: {
                        PetSummaryRow(pet: pet, ownerName: nil)
                    }
                } else {
                    PetSummaryRow(pet: pet, ownerName: store.ownerName(of: pet))
                }
                if store.pets.count > 1 {
                    Picker("Showing", selection: selectedPetID) {
                        ForEach(store.pets) { pet in
                            Text(label(for: pet)).tag(pet.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var householdSection: some View {
        if let pet = store.pet {
            if store.isOwner {
                Section {
                    ForEach(store.memberIDs, id: \.self) { memberID in
                        Label(store.name(for: memberID), systemImage: "person.fill")
                            .swipeActions {
                                Button("Remove", role: .destructive) { removingMember = memberID }
                            }
                    }
                    ForEach(store.invites) { invite in
                        Button {
                            shownInvite = invite
                        } label: {
                            LabeledContent {
                                Text("Until \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            } label: {
                                Label("Invite \(InviteCode.display(invite.code))", systemImage: "envelope")
                            }
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Cancel invite", role: .destructive) { cancel(invite) }
                        }
                    }
                    Button {
                        startInvite()
                    } label: {
                        Label("Invite someone", systemImage: "person.badge.plus")
                    }
                    .disabled(!store.canInviteMore || isWorking)
                } header: {
                    Text("Family & helpers")
                } footer: {
                    Text(householdFooter(petName: pet.name))
                }
            } else if let membership = store.memberships.first(where: { $0.ownerID == pet.ownerID }) {
                Section {
                    Button("Leave \(membership.ownerName)'s household", role: .destructive) {
                        leaving = membership
                    }
                } header: {
                    Text("Household")
                } footer: {
                    Text("You help with \(pet.name). Only \(membership.ownerName) can change the schedule.")
                }
            }
        }
    }

    private var premiumSection: some View {
        Section {
            if store.iHavePremium {
                LabeledContent("PawDone Premium", value: "Active")
                if let expiresAt = store.myEntitlement?.expiresAt {
                    LabeledContent("Renews or ends", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                }
                Button("Manage subscription") { isManagingSubscription = true }
            } else {
                Button {
                    isShowingPaywall = true
                } label: {
                    Label("Get PawDone Premium", systemImage: "star.fill")
                }
            }
        } header: {
            Text("Premium")
        } footer: {
            if !store.iHavePremium {
                Text("Invite family and helpers, share photo proof and use PawDone on all your devices.")
            }
        }
    }

    @ViewBuilder private var notificationsSection: some View {
        if let pet = store.pet {
            Section {
                Toggle("Reminders for \(pet.name)", isOn: remindersEnabled)
                if PushRegistrar.shared.authorizationStatus == .denied {
                    Button("Turn on notifications in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(PushRegistrar.shared.authorizationStatus == .denied
                    ? "Notifications are off for PawDone, so reminders can't reach this phone."
                    : "A notification when one of \(pet.name)'s tasks is due and not done yet.")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(saveName)
            if nameChanged {
                Button("Save name", action: saveName)
                    .disabled(isSavingName)
            }
        } header: {
            Text("Your name")
        } footer: {
            Text("Shown to family and helpers when you mark tasks done.")
        }
    }

    private var otherHouseholdsSection: some View {
        Section {
            ForEach(store.pausedMemberships) { membership in
                LabeledContent(membership.petName ?? "\(membership.ownerName)'s pet", value: "Paused")
            }
            Button {
                isJoining = true
            } label: {
                Label("Join a household", systemImage: "person.2")
            }
        } footer: {
            if !store.pausedMemberships.isEmpty {
                Text("Paused households come back when their owner renews Premium.")
            }
        }
    }

    // MARK: Helpers

    private func label(for pet: Pet) -> String {
        guard let ownerName = store.ownerName(of: pet) else { return pet.name }
        return "\(pet.name) · \(ownerName)'s"
    }

    private func householdFooter(petName: String) -> String {
        if !store.hasPremium {
            return "Inviting family and helpers is part of Premium."
        }
        if !store.canInviteMore {
            return "Up to \(PetStore.householdLimit) people. Remove someone or cancel an invite to invite someone else."
        }
        return "Helpers see \(petName)'s day and can mark tasks done, but can't change the schedule. Up to \(PetStore.householdLimit) people."
    }

    private var selectedPetID: Binding<UUID> {
        Binding(
            get: { store.pet?.id ?? UUID() },
            set: { id in
                if let pet = store.pets.first(where: { $0.id == id }) {
                    Task { await store.selectPet(pet) }
                }
            }
        )
    }

    private var remindersEnabled: Binding<Bool> {
        Binding(
            get: { store.remindersEnabled },
            set: { enabled in
                Task {
                    do {
                        try await store.setRemindersEnabled(enabled)
                    } catch {
                        errorMessage = UserFacingError.message(for: error)
                    }
                }
            }
        )
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { removingMember != nil }, set: { if !$0 { removingMember = nil } })
    }

    private var isConfirmingLeave: Binding<Bool> {
        Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameChanged: Bool { !trimmedName.isEmpty && trimmedName != store.myName }

    // MARK: Actions

    private func startInvite() {
        guard store.hasPremium else {
            isShowingPaywall = true
            return
        }
        perform { shownInvite = try await store.createInvite() }
    }

    private func cancel(_ invite: Invite) {
        perform { try await store.cancelInvite(invite) }
    }

    private func remove(_ memberID: UUID) {
        perform { try await store.removeMember(memberID) }
    }

    private func leave(_ membership: Membership) {
        perform { try await store.leaveHousehold(membership) }
    }

    private func saveName() {
        guard nameChanged else { return }
        isSavingName = true
        Task {
            do {
                try await store.saveName(trimmedName)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSavingName = false
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await action()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isWorking = false
        }
    }
}

private struct PetSummaryRow: View {
    let pet: Pet
    /// Set when the user helps with someone else's pet.
    let ownerName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pet.species.symbol)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(pet.name)
                    .font(.body.weight(.medium))
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: String {
        var parts = [pet.species.label]
        if let breed = pet.breed { parts.append(breed) }
        if let ownerName { parts.append("\(ownerName)'s") }
        return parts.joined(separator: " · ")
    }
}
