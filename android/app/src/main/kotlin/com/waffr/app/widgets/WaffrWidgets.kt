package com.waffr.app.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.waffr.app.MainActivity
import com.waffr.app.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Home screen widgets. The app writes ready-to-show text into the shared
// widget storage (see lib/data/services/home_widget_sync.dart); these
// providers only place it in the layouts and wire the taps.

private fun launch(context: Context, path: String): PendingIntent =
    HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("waffr://$path"),
    )

private fun SharedPreferences.text(key: String, fallback: String = ""): String =
    getString(key, null) ?: fallback

private fun SharedPreferences.percent(key: String): Int =
    (getString(key, null)?.toIntOrNull() ?: 0).coerceIn(0, 100)

class BalanceWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_balance).apply {
                setTextViewText(R.id.balance_amount, widgetData.text("balance_amount", "—"))
                setTextViewText(R.id.balance_currency, widgetData.text("balance_currency"))
                setTextViewText(R.id.balance_caption, widgetData.text("balance_caption"))
                setTextViewText(R.id.balance_percent, widgetData.text("balance_percent_label"))
                setProgressBar(R.id.balance_progress, 100, widgetData.percent("balance_percent"), false)
                setOnClickPendingIntent(R.id.widget_root, launch(context, "home"))
                setOnClickPendingIntent(R.id.balance_add_expense, launch(context, "add-expense"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class QuickAddWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add).apply {
                setOnClickPendingIntent(R.id.quick_add_expense, launch(context, "add-expense"))
                setOnClickPendingIntent(R.id.quick_add_income, launch(context, "add-income"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class GoalWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val empty = widgetData.getBoolean("goal_empty", true)
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_goal).apply {
                setTextViewText(
                    R.id.goal_name,
                    widgetData.text("goal_name", context.getString(R.string.widget_goal_empty_title)),
                )
                setTextViewText(
                    R.id.goal_caption,
                    widgetData.text("goal_caption", context.getString(R.string.widget_goal_empty_caption)),
                )
                setTextViewText(R.id.goal_percent, widgetData.text("goal_percent_label"))
                setProgressBar(R.id.goal_progress, 100, widgetData.percent("goal_percent"), false)
                setViewVisibility(R.id.goal_progress_row, if (empty) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(R.id.widget_root, launch(context, if (empty) "create-goal" else "savings"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class ObligationWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val empty = widgetData.getBoolean("obligation_empty", true)
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_obligation).apply {
                setTextViewText(
                    R.id.obligation_name,
                    widgetData.text("obligation_name", context.getString(R.string.widget_obligation_empty)),
                )
                setTextViewText(R.id.obligation_value, widgetData.text("obligation_value"))
                setTextViewText(R.id.obligation_currency, widgetData.text("balance_currency"))
                setTextViewText(R.id.obligation_when, widgetData.text("obligation_when"))
                setViewVisibility(R.id.obligation_amount_row, if (empty) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.obligation_when, if (empty) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(R.id.widget_root, launch(context, "obligations"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class StreakWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_streak).apply {
                setTextViewText(R.id.streak_count, widgetData.text("streak_count", "1"))
                setTextViewText(
                    R.id.streak_word,
                    widgetData.text("streak_word", context.getString(R.string.widget_streak_word)),
                )
                setProgressBar(R.id.streak_ring, 100, widgetData.percent("streak_percent"), false)
                setOnClickPendingIntent(R.id.widget_root, launch(context, "profile"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
