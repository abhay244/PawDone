import Foundation

/// Data TailTick keeps on this phone for the signed-in user.
enum LocalData {
    /// Removes it, e.g. after the account is deleted. The device ID stays: it identifies
    /// this phone, not the person.
    static func erase() {
        ProofPhotoStore().deleteAll()
        UserDefaults.standard.removeObject(forKey: PetStore.selectedPetKey)
    }
}
