package com.waffr.app.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.waffr.app.MainActivity
import com.waffr.app.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

// Home screen widgets. The app writes ready-to-show text into the shared
// widget storage (see lib/data/services/home_widget_sync.dart); these
// providers place it in the layouts, pick the layout for the widget's size
// and wire the taps.
//
// Sizes: Android 12+ gets every layout at once (RemoteViews by size) and the
// launcher picks the one that fits; older versions get the layout for the
// size reported in the widget options, redrawn when the user resizes.
//
// Text that depends on today's date (the month, "today", days to a bill) is
// worked out here from saved dates, because the app only writes when it is
// open while the widgets also redraw every few hours on their own.

/** The three layouts a widget can have. */
internal enum class WidgetSize { SMALL, MEDIUM, LARGE }

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

/** Ints saved from Dart arrive as Long on Android. */
private fun SharedPreferences.number(key: String): Long =
    when (val value = all[key]) {
        is Long -> value
        is Int -> value.toLong()
        is String -> value.toLongOrNull() ?: 0L
        else -> 0L
    }

private fun dayFormat() = SimpleDateFormat("yyyy-MM-dd", Locale.US)

private fun today(): String = dayFormat().format(Date())

private fun isNight(context: Context): Boolean =
    (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES

/** Levantine month names, as CalendarPeriod.monthNames in the app. */
private val monthNames = arrayOf(
    "كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران",
    "تموز", "آب", "أيلول", "تشرين الأول", "تشرين الثاني", "كانون الأول",
)

/** Whole days from today to [day] (yyyy-MM-dd); null when unreadable. */
private fun daysUntil(day: String): Long? {
    val target = runCatching { dayFormat().parse(day) }.getOrNull() ?: return null
    val start = dayFormat().parse(today()) ?: return null
    // Rounded, so a day shortened or lengthened by a clock change still
    // counts as one.
    return Math.round((target.time - start.time) / TimeUnit.DAYS.toMillis(1).toDouble())
}

/** "بعد 3 أيام" with the noun agreeing with the number, as Ar.days does. */
private fun inDays(n: Long): String = when {
    n == 2L -> "بعد يومين"
    n in 3L..10L -> "بعد $n أيام"
    else -> "بعد $n يوماً"
}

/** "اليوم", "أمس" or "12 آب" for a saved day. */
private fun dayLabel(day: String): String {
    val diff = daysUntil(day) ?: return ""
    if (diff == 0L) return "اليوم"
    if (diff == -1L) return "أمس"
    val date = dayFormat().parse(day) ?: return day
    val calendar = Calendar.getInstance().apply { time = date }
    return "${calendar.get(Calendar.DAY_OF_MONTH)} ${monthNames[calendar.get(Calendar.MONTH)]}"
}

/** Tints a progress bar (Android 12+; older versions keep the accent). */
private fun RemoteViews.tintBar(id: Int, color: Int) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        setColorStateList(id, "setProgressTintList", ColorStateList.valueOf(color))
    }
}

/**
 * Shared base: draws every widget id at the right size and redraws on
 * resize. Subclasses list the sizes they have and build one layout.
 */
abstract class WaffrWidgetProvider : HomeWidgetProvider() {
    /** Sizes this widget has a layout for. */
    internal abstract val sizes: Set<WidgetSize>

    internal abstract fun build(
        context: Context,
        data: SharedPreferences,
        size: WidgetSize,
    ): RemoteViews

    /** A layout for a widget one row high, if this widget has one. */
    internal open fun buildShort(context: Context, data: SharedPreferences): RemoteViews? = null

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) draw(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        draw(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun draw(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        data: SharedPreferences,
    ) {
        val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The launcher shows the largest layout that fits the widget.
            val bySize = linkedMapOf<SizeF, RemoteViews>()
            buildShort(context, data)?.let { bySize[SizeF(MEDIUM_MIN_WIDTH, 40f)] = it }
            val smallest = if (WidgetSize.SMALL in sizes) WidgetSize.SMALL else WidgetSize.MEDIUM
            bySize[SizeF(100f, 100f)] = build(context, data, smallest)
            if (WidgetSize.SMALL in sizes) {
                bySize[SizeF(MEDIUM_MIN_WIDTH, 100f)] = build(context, data, WidgetSize.MEDIUM)
            }
            if (WidgetSize.LARGE in sizes) {
                bySize[SizeF(MEDIUM_MIN_WIDTH, LARGE_MIN_HEIGHT)] =
                    build(context, data, WidgetSize.LARGE)
            }
            RemoteViews(bySize)
        } else {
            val options = manager.getAppWidgetOptions(id)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            val short = if (height in 1 until SHORT_MAX_HEIGHT) buildShort(context, data) else null
            short ?: build(context, data, pick(width.toFloat(), height.toFloat()))
        }
        manager.updateAppWidget(id, views)
    }

    private fun pick(width: Float, height: Float): WidgetSize = when {
        width in 1f..(MEDIUM_MIN_WIDTH - 1) && WidgetSize.SMALL in sizes -> WidgetSize.SMALL
        height >= LARGE_MIN_HEIGHT && WidgetSize.LARGE in sizes -> WidgetSize.LARGE
        WidgetSize.MEDIUM in sizes -> WidgetSize.MEDIUM
        else -> sizes.first()
    }

    private companion object {
        /** Narrower than this is the small layout. */
        const val MEDIUM_MIN_WIDTH = 200f

        /** Taller than this is the large layout. */
        const val LARGE_MIN_HEIGHT = 230f

        /** Lower than this is a one-row widget. */
        const val SHORT_MAX_HEIGHT = 100
    }
}

/** Balance: small (amount and what is left), medium (the dashboard card),
 *  large (plus the period's income and spending and quick add). */
class BalanceWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.SMALL, WidgetSize.MEDIUM, WidgetSize.LARGE)

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val layout = when (size) {
            WidgetSize.SMALL -> R.layout.widget_balance_small
            WidgetSize.MEDIUM -> R.layout.widget_balance
            WidgetSize.LARGE -> R.layout.widget_balance_large
        }
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.balance_amount, data.text("balance_amount", "—"))
            setTextViewText(R.id.balance_currency, data.text("balance_currency"))
            setTextViewText(R.id.balance_percent, data.text("balance_percent_label"))
            setProgressBar(R.id.balance_progress, 100, data.percent("balance_percent"), false)
            setOnClickPendingIntent(R.id.widget_root, launch(context, "home"))
            if (size != WidgetSize.SMALL) {
                setTextViewText(R.id.balance_caption, data.text("balance_caption"))
                setOnClickPendingIntent(R.id.balance_add_expense, launch(context, "add-expense"))
                setOnClickPendingIntent(R.id.balance_add_income, launch(context, "add-income"))
            }
            if (size == WidgetSize.LARGE) {
                setTextViewText(R.id.cycle_income, data.text("cycle_income", "—"))
                setTextViewText(R.id.cycle_spent, data.text("cycle_spent", "—"))
            }
        }
    }
}

/** This month: medium (totals and the top category), large (four
 *  categories with their shares). Once the month turns while the app stays
 *  closed, it asks to open the app instead of showing last month as this. */
class MonthWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.MEDIUM, WidgetSize.LARGE)

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val large = size == WidgetSize.LARGE
        val views = RemoteViews(
            context.packageName,
            if (large) R.layout.widget_month_large else R.layout.widget_month,
        )
        val stale = data.text("month_key") != today().substring(0, 7)
        val count = if (stale) 0 else data.number("month_top_count").toInt()
        val rows = if (large) 4 else 1
        val night = isNight(context)
        views.apply {
            setTextViewText(R.id.month_label, if (stale) "" else data.text("month_label"))
            setTextViewText(R.id.month_spent, if (stale) "—" else data.text("month_spent", "—"))
            setTextViewText(R.id.month_income, if (stale) "—" else data.text("month_income", "—"))
            val note = when {
                stale -> context.getString(R.string.widget_month_stale)
                count == 0 -> context.getString(R.string.widget_month_empty)
                else -> null
            }
            setViewVisibility(R.id.month_note, if (note == null) View.GONE else View.VISIBLE)
            setTextViewText(R.id.month_note, note ?: "")
            for (i in 0 until rows) {
                val row = rowIds[i]
                if (i >= count) {
                    setViewVisibility(row.row, View.GONE)
                    continue
                }
                setViewVisibility(row.row, View.VISIBLE)
                val color = data.number(
                    if (night) "month_top_${i}_color_dark" else "month_top_${i}_color",
                ).toInt()
                setInt(row.dot, "setColorFilter", color)
                setTextViewText(row.name, data.text("month_top_${i}_name"))
                setTextViewText(row.amount, data.text("month_top_${i}_amount"))
                setTextViewText(row.percent, "${data.percent("month_top_${i}_percent")}%")
                if (large) {
                    setProgressBar(row.bar, 100, data.percent("month_top_${i}_percent"), false)
                    tintBar(row.bar, color)
                }
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, "reports"))
        }
        return views
    }

    private class Row(val row: Int, val dot: Int, val name: Int, val amount: Int, val percent: Int, val bar: Int)

    private val rowIds = listOf(
        Row(R.id.month_row_0, R.id.month_dot_0, R.id.month_name_0, R.id.month_amount_0, R.id.month_percent_0, R.id.month_bar_0),
        Row(R.id.month_row_1, R.id.month_dot_1, R.id.month_name_1, R.id.month_amount_1, R.id.month_percent_1, R.id.month_bar_1),
        Row(R.id.month_row_2, R.id.month_dot_2, R.id.month_name_2, R.id.month_amount_2, R.id.month_percent_2, R.id.month_bar_2),
        Row(R.id.month_row_3, R.id.month_dot_3, R.id.month_name_3, R.id.month_amount_3, R.id.month_percent_3, R.id.month_bar_3),
    )
}

/** Quick add: small (two stacked buttons), medium (buttons and the last
 *  record), large (buttons and the four latest records). */
class QuickAddWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.SMALL, WidgetSize.MEDIUM, WidgetSize.LARGE)

    // Quick-add widgets placed one row high before the redesign keep a row
    // of two buttons.
    override fun buildShort(context: Context, data: SharedPreferences): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_quick_add_row).apply {
            setOnClickPendingIntent(R.id.quick_add_expense, launch(context, "add-expense"))
            setOnClickPendingIntent(R.id.quick_add_income, launch(context, "add-income"))
        }

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val layout = when (size) {
            WidgetSize.SMALL -> R.layout.widget_quick_add_small
            WidgetSize.MEDIUM -> R.layout.widget_quick_add
            WidgetSize.LARGE -> R.layout.widget_quick_add_large
        }
        val count = data.number("recent_count").toInt()
        val night = isNight(context)
        return RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(R.id.quick_add_expense, launch(context, "add-expense"))
            setOnClickPendingIntent(R.id.quick_add_income, launch(context, "add-income"))
            when (size) {
                WidgetSize.SMALL -> Unit
                WidgetSize.MEDIUM -> {
                    val line = if (count == 0) {
                        context.getString(R.string.widget_recent_empty)
                    } else {
                        "${data.text("recent_0_title")} · ${dayLabel(data.text("recent_0_day"))} · " +
                            "${data.text("recent_0_amount")} ${data.text("balance_currency")}"
                    }
                    setTextViewText(R.id.recent_line, line)
                    setOnClickPendingIntent(R.id.widget_root, launch(context, "expenses"))
                }
                WidgetSize.LARGE -> {
                    setViewVisibility(R.id.recent_empty, if (count == 0) View.VISIBLE else View.GONE)
                    for (i in 0 until 4) {
                        val row = rowIds[i]
                        if (i >= count) {
                            setViewVisibility(row.row, View.GONE)
                            continue
                        }
                        setViewVisibility(row.row, View.VISIBLE)
                        val color = data.number(
                            if (night) "recent_${i}_color_dark" else "recent_${i}_color",
                        ).toInt()
                        setInt(row.dot, "setColorFilter", color)
                        setTextViewText(row.title, data.text("recent_${i}_title"))
                        setTextViewText(row.day, dayLabel(data.text("recent_${i}_day")))
                        setTextViewText(row.amount, data.text("recent_${i}_amount"))
                    }
                    setOnClickPendingIntent(R.id.widget_root, launch(context, "expenses"))
                }
            }
        }
    }

    private class Row(val row: Int, val dot: Int, val title: Int, val day: Int, val amount: Int)

    private val rowIds = listOf(
        Row(R.id.recent_row_0, R.id.recent_dot_0, R.id.recent_title_0, R.id.recent_day_0, R.id.recent_amount_0),
        Row(R.id.recent_row_1, R.id.recent_dot_1, R.id.recent_title_1, R.id.recent_day_1, R.id.recent_amount_1),
        Row(R.id.recent_row_2, R.id.recent_dot_2, R.id.recent_title_2, R.id.recent_day_2, R.id.recent_amount_2),
        Row(R.id.recent_row_3, R.id.recent_dot_3, R.id.recent_title_3, R.id.recent_day_3, R.id.recent_amount_3),
    )
}

/** Savings goal: small (name, percent, progress), medium (plus saved and
 *  remaining). With no goal it invites creating one. */
class GoalWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.SMALL, WidgetSize.MEDIUM)

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val empty = data.getBoolean("goal_empty", true)
        val layout = if (size == WidgetSize.SMALL) R.layout.widget_goal else R.layout.widget_goal_medium
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(
                R.id.goal_name,
                data.text("goal_name", context.getString(R.string.widget_goal_empty_title)),
            )
            setTextViewText(
                R.id.goal_caption,
                data.text("goal_caption", context.getString(R.string.widget_goal_empty_caption)),
            )
            setTextViewText(R.id.goal_percent, data.text("goal_percent_label"))
            setProgressBar(R.id.goal_progress, 100, data.percent("goal_percent"), false)
            setViewVisibility(R.id.goal_progress_row, if (empty) View.GONE else View.VISIBLE)
            if (size == WidgetSize.MEDIUM) {
                setTextViewText(R.id.goal_remaining, if (empty) "" else data.text("goal_remaining"))
                setViewVisibility(R.id.goal_percent, if (empty) View.GONE else View.VISIBLE)
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, if (empty) "create-goal" else "savings"))
        }
    }
}

/** Next bill: small (name, amount, when), medium (the same on a wider
 *  card, "when" beside the title). "When" is counted from today here. */
class ObligationWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.SMALL, WidgetSize.MEDIUM)

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val empty = data.getBoolean("obligation_empty", true)
        val layout = if (size == WidgetSize.SMALL) R.layout.widget_obligation else R.layout.widget_obligation_medium
        val days = daysUntil(data.text("obligation_due_day"))
        val whenText = when {
            days == null -> data.text("obligation_when")
            days < 0 -> "مستحق الآن"
            days == 0L -> "اليوم"
            days == 1L -> "غداً"
            else -> inDays(days)
        }
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(
                R.id.obligation_name,
                data.text("obligation_name", context.getString(R.string.widget_obligation_empty)),
            )
            setTextViewText(R.id.obligation_value, data.text("obligation_value"))
            setTextViewText(R.id.obligation_currency, data.text("balance_currency"))
            setTextViewText(R.id.obligation_when, whenText)
            setViewVisibility(R.id.obligation_amount_row, if (empty) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.obligation_when, if (empty) View.GONE else View.VISIBLE)
            setOnClickPendingIntent(R.id.widget_root, launch(context, "obligations"))
        }
    }
}

/** Streak: small (the ring), medium (the ring with the run in words and
 *  the next milestone). Past the last day it survives, it shows as broken. */
class StreakWidgetProvider : WaffrWidgetProvider() {
    override val sizes = setOf(WidgetSize.SMALL, WidgetSize.MEDIUM)

    override fun build(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val aliveUntil = data.text("streak_alive_until")
        val broken = aliveUntil.isNotEmpty() && today() > aliveUntil
        val layout = if (size == WidgetSize.SMALL) R.layout.widget_streak else R.layout.widget_streak_medium
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.streak_count, if (broken) "0" else data.text("streak_count", "1"))
            setTextViewText(
                R.id.streak_word,
                if (broken) {
                    data.text("streak_reset_label", context.getString(R.string.widget_streak_word))
                } else {
                    data.text("streak_word", context.getString(R.string.widget_streak_word))
                },
            )
            setProgressBar(R.id.streak_ring, 100, if (broken) 0 else data.percent("streak_percent"), false)
            if (size == WidgetSize.MEDIUM) {
                setTextViewText(
                    R.id.streak_label,
                    if (broken) data.text("streak_reset_label") else data.text("streak_label"),
                )
                setTextViewText(R.id.streak_next, if (broken) "" else data.text("streak_next"))
            }
            setOnClickPendingIntent(R.id.widget_root, launch(context, "profile"))
        }
    }
}
