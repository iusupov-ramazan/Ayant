package kg.ayant.app.data

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kg.ayant.app.data.firestore.FS
import kg.ayant.app.data.firestore.toFirestoreMap
import kg.ayant.app.domain.contract.HostRepository
import kg.ayant.app.domain.model.HostVenueDTO
import kotlinx.coroutines.tasks.await

/** Оффлайн-режим: кабинет живёт только в SharedPreferences, на сервер ничего не уходит. */
class MockHostRepository : HostRepository {
    override suspend fun saveVenue(dto: HostVenueDTO, ownerID: String) {}
}

/**
 * Пишет `venues/{id}` с merge-семантикой. Зеркалит `FirebaseHostRepository.saveVenue`
 * на iOS: правила Firestore пускают запись только владельцу (`ownerID == uid`) или
 * админу, поэтому без входа вызов упадёт — вызывающий глотает ошибку, кэш на
 * устройстве остаётся источником правды для кабинета.
 */
class FirebaseHostRepository : HostRepository {

    private val db = FirebaseFirestore.getInstance()

    override suspend fun saveVenue(dto: HostVenueDTO, ownerID: String) {
        db.collection(FS.Collection.VENUES).document(dto.id)
            .set(dto.toFirestoreMap(ownerID), SetOptions.merge()).await()
    }
}
