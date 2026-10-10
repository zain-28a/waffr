// Home screen widgets for iOS. The Flutter app writes ready-to-show text
// into the shared App Group (lib/data/services/home_widget_sync.dart);
// these views only lay it out. Setup steps: ios/WaffrWidgets/README.md.

import SwiftUI
import WidgetKit

private let appGroupId = "group.com.waffr.app"

struct WaffrData {
  var balanceAmount = "—"
  var balanceCurrency = ""
  var balanceCaption = ""
  var balancePercentLabel = ""
  var balancePercent = 0.0
  var goalEmpty = true
  var goalName = "لا يوجد هدف بعد"
  var goalCaption = "اضغط لإنشاء هدفك الأول"
  var goalPercentLabel = ""
  var goalPercent = 0.0
  var obligationEmpty = true
  var obligationName = "لا توجد التزامات قادمة"
  var obligationAmount = ""
  var obligationWhen = ""
  var streakCount = "1"
  var streakLabel = "اليوم الأول"

  static func load() -> WaffrData {
    var data = WaffrData()
    guard let store = UserDefaults(suiteName: appGroupId) else { return data }
    func text(_ key: String) -> String? { store.string(forKey: key) }
    func percent(_ key: String) -> Double {
      min(max((Double(text(key) ?? "") ?? 0) / 100, 0), 1)
    }
    data.balanceAmount = text("balance_amount") ?? data.balanceAmount
    data.balanceCurrency = text("balance_currency") ?? ""
    data.balanceCaption = text("balance_caption") ?? ""
    data.balancePercentLabel = text("balance_percent_label") ?? ""
    data.balancePercent = percent("balance_percent")
    data.goalEmpty = store.object(forKey: "goal_empty") as? Bool ?? true
    data.goalName = text("goal_name") ?? data.goalName
    data.goalCaption = text("goal_caption") ?? data.goalCaption
    data.goalPercentLabel = text("goal_percent_label") ?? ""
    data.goalPercent = percent("goal_percent")
    data.obligationEmpty = store.object(forKey: "obligation_empty") as? Bool ?? true
    data.obligationName = text("obligation_name") ?? data.obligationName
    data.obligationAmount = text("obligation_amount") ?? ""
    data.obligationWhen = text("obligation_when") ?? ""
    data.streakCount = text("streak_count") ?? "1"
    data.streakLabel = text("streak_label") ?? data.streakLabel
    return data
  }
}

struct WaffrEntry: TimelineEntry {
  let date: Date
  let data: WaffrData
}

// The app reloads the timelines whenever its data changes, so a single
// entry with no refresh policy is enough.
struct WaffrProvider: TimelineProvider {
  func placeholder(in context: Context) -> WaffrEntry {
    WaffrEntry(date: Date(), data: WaffrData())
  }

  func getSnapshot(in context: Context, completion: @escaping (WaffrEntry) -> Void) {
    completion(WaffrEntry(date: Date(), data: WaffrData.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WaffrEntry>) -> Void) {
    completion(Timeline(entries: [WaffrEntry(date: Date(), data: WaffrData.load())], policy: .never))
  }
}

// MARK: - Style

private struct Palette {
  let scheme: ColorScheme
  var surface: Color {
    scheme == .dark ? Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
      : Color(red: 248 / 255, green: 247 / 255, blue: 246 / 255)
  }
  var accent: Color {
    scheme == .dark ? Color(red: 91 / 255, green: 136 / 255, blue: 88 / 255)
      : Color(red: 37 / 255, green: 74 / 255, blue: 35 / 255)
  }
  var primary: Color { scheme == .dark ? .white : .black }
  var secondary: Color {
    scheme == .dark ? Color(white: 131 / 255) : Color(white: 111 / 255)
  }
}

private func link(_ path: String) -> URL {
  // The homeWidget query lets the home_widget plugin report the tap.
  URL(string: "waffr://\(path)?homeWidget")!
}

private struct WidgetFrame<Content: View>: View {
  @Environment(\.colorScheme) private var scheme
  let content: (Palette) -> Content

  var body: some View {
    let palette = Palette(scheme: scheme)
    let inner = content(palette)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environment(\.layoutDirection, .rightToLeft)
    if #available(iOSApplicationExtension 17.0, *) {
      inner.containerBackground(for: .widget) { palette.surface }
    } else {
      inner.padding().background(palette.surface)
    }
  }
}

private struct ProgressLine: View {
  let value: Double
  let palette: Palette

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(palette.accent.opacity(0.14))
        Capsule().fill(palette.accent).frame(width: proxy.size.width * value)
      }
    }
    .frame(height: 8)
  }
}

// MARK: - Widgets

struct BalanceView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("الرصيد الحالي").font(.caption).foregroundColor(p.secondary)
          Spacer()
          Link(destination: link("add-expense")) {
            Text("+ مصروف").font(.caption.bold()).foregroundColor(p.accent)
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(Capsule().fill(p.accent.opacity(0.14)))
          }
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(data.balanceAmount).font(.system(size: 26, weight: .bold))
            .foregroundColor(p.accent).minimumScaleFactor(0.6).lineLimit(1)
          Text(data.balanceCurrency).font(.caption).foregroundColor(p.secondary)
        }
        Spacer(minLength: 0)
        Text(data.balancePercentLabel).font(.caption2.bold()).foregroundColor(p.secondary)
        ProgressLine(value: data.balancePercent, palette: p)
        Text(data.balanceCaption).font(.caption2).foregroundColor(p.secondary).lineLimit(1)
      }
    }
    .widgetURL(link("home"))
  }
}

struct WaffrBalanceWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WaffrBalanceWidget", provider: WaffrProvider()) { entry in
      BalanceView(data: entry.data)
    }
    .configurationDisplayName("الرصيد الحالي")
    .description("رصيدك ونسبة المتبقي منه")
    .supportedFamilies([.systemMedium])
  }
}

struct QuickAddView: View {
  var body: some View {
    WidgetFrame { p in
      HStack(spacing: 10) {
        Link(destination: link("add-expense")) {
          Text("+ مصروف").font(.headline).foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(p.accent))
        }
        Link(destination: link("add-income")) {
          Text("+ دخل").font(.headline).foregroundColor(p.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(p.accent.opacity(0.14)))
        }
      }
    }
  }
}

struct WaffrQuickAddWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WaffrQuickAddWidget", provider: WaffrProvider()) { _ in
      QuickAddView()
    }
    .configurationDisplayName("إضافة سريعة")
    .description("أضف مصروفاً أو دخلاً بلمسة")
    .supportedFamilies([.systemMedium])
  }
}

struct GoalView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(alignment: .leading, spacing: 4) {
        Text("هدف التوفير").font(.caption).foregroundColor(p.secondary)
        Text(data.goalName).font(.headline).foregroundColor(p.primary).lineLimit(1)
        Spacer(minLength: 0)
        if !data.goalEmpty {
          Text(data.goalPercentLabel).font(.title2.bold()).foregroundColor(p.accent)
          ProgressLine(value: data.goalPercent, palette: p)
        }
        Text(data.goalCaption).font(.caption2).foregroundColor(p.secondary).lineLimit(2)
      }
    }
    .widgetURL(link(data.goalEmpty ? "create-goal" : "savings"))
  }
}

struct WaffrGoalWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WaffrGoalWidget", provider: WaffrProvider()) { entry in
      GoalView(data: entry.data)
    }
    .configurationDisplayName("هدف التوفير")
    .description("تقدّم هدف التوفير الحالي")
    .supportedFamilies([.systemSmall])
  }
}

struct ObligationView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(alignment: .leading, spacing: 4) {
        Text("الالتزام القادم").font(.caption).foregroundColor(p.secondary)
        Text(data.obligationName).font(.headline).foregroundColor(p.primary).lineLimit(1)
        Spacer(minLength: 0)
        if !data.obligationEmpty {
          Text(data.obligationAmount).font(.title3.bold()).foregroundColor(p.accent)
            .minimumScaleFactor(0.6).lineLimit(1)
          Text(data.obligationWhen).font(.caption2.bold()).foregroundColor(p.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(p.accent.opacity(0.14)))
        }
      }
    }
    .widgetURL(link("obligations"))
  }
}

struct WaffrObligationWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WaffrObligationWidget", provider: WaffrProvider()) { entry in
      ObligationView(data: entry.data)
    }
    .configurationDisplayName("الالتزام القادم")
    .description("أقرب دفعة متكررة وموعدها")
    .supportedFamilies([.systemSmall])
  }
}

struct StreakView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(spacing: 2) {
        Text("🔥").font(.title2)
        Text(data.streakCount).font(.system(size: 34, weight: .bold)).foregroundColor(p.accent)
        Text(data.streakLabel).font(.caption2).foregroundColor(p.secondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .widgetURL(link("profile"))
  }
}

struct WaffrStreakWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WaffrStreakWidget", provider: WaffrProvider()) { entry in
      StreakView(data: entry.data)
    }
    .configurationDisplayName("سلسلة الأيام")
    .description("سلسلة أيامك المتواصلة مع وفّر")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct WaffrWidgetsBundle: WidgetBundle {
  var body: some Widget {
    WaffrBalanceWidget()
    WaffrQuickAddWidget()
    WaffrGoalWidget()
    WaffrObligationWidget()
    WaffrStreakWidget()
  }
}
