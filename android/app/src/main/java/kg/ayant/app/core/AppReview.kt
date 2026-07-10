package kg.ayant.app.core

import android.app.Activity
import android.content.Context
import com.google.android.play.core.review.ReviewManagerFactory

/**
 * Play In-App Review. Prompts after the 1st and every 5th coupon (mirrors the
 * iOS requestReview cadence). No-op if not launched from an Activity.
 */
object AppReview {
    fun maybePrompt(context: Context) {
        val activity = context as? Activity ?: return
        val prefs = context.getSharedPreferences("ayant.review", 0)
        val count = prefs.getInt("count", 0) + 1
        prefs.edit().putInt("count", count).apply()
        if (count != 1 && count % 5 != 0) return
        val manager = ReviewManagerFactory.create(context)
        manager.requestReviewFlow().addOnCompleteListener { task ->
            if (task.isSuccessful) manager.launchReviewFlow(activity, task.result)
        }
    }
}
