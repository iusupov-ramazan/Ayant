package kg.ayant.app.data

import kg.ayant.app.data.model.Review
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.Venue

/**
 * Source of venues/deals/reviews. MockDataRepository serves local data;
 * a FirebaseDataRepository (see FirebaseDataRepository.kt) reads the same models
 * from Firestore — the UI does not change. Mirrors DataRepository.swift.
 */
interface DataRepository {
    suspend fun fetchVenues(): List<Venue>
    suspend fun fetchDeals(): List<Deal>
    suspend fun fetchReviews(): List<Review>
    suspend fun saveReview(review: Review)
    suspend fun deleteReview(id: String)
}

class MockDataRepository : DataRepository {
    override suspend fun fetchVenues(): List<Venue> = MockData.venues
    override suspend fun fetchDeals(): List<Deal> = MockData.deals
    override suspend fun fetchReviews(): List<Review> = MockData.reviews
    override suspend fun saveReview(review: Review) {}
    override suspend fun deleteReview(id: String) {}
}
