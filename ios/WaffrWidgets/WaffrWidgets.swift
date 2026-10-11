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
  var obligationValue = ""
  var obligationWhen = ""
  var streakCount = "1"
  var streakLabel = "اليوم الأول"
  var streakWord = "يوم"
  var streakPercent = 0.0

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
    data.obligationValue = text("obligation_value") ?? data.obligationAmount
    data.obligationWhen = text("obligation_when") ?? ""
    data.streakCount = text("streak_count") ?? "1"
    data.streakLabel = text("streak_label") ?? data.streakLabel
    data.streakWord = text("streak_word") ?? data.streakWord
    data.streakPercent = percent("streak_percent")
    // Past the last day the streak survives, a whole day was skipped.
    if let aliveUntil = text("streak_alive_until"), !aliveUntil.isEmpty {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      if formatter.string(from: Date()) > aliveUntil {
        data.streakCount = "0"
        data.streakLabel = text("streak_reset_label") ?? data.streakLabel
        data.streakWord = data.streakLabel
        data.streakPercent = 0
      }
    }
    return data
  }
}

struct WaffrEntry: TimelineEntry {
  let date: Date
  let data: WaffrData
}

// The app reloads the timelines whenever its data changes. A refresh after
// midnight lets the streak widget notice a skipped day on its own.
struct WaffrProvider: TimelineProvider {
  func placeholder(in context: Context) -> WaffrEntry {
    WaffrEntry(date: Date(), data: WaffrData())
  }

  func getSnapshot(in context: Context, completion: @escaping (WaffrEntry) -> Void) {
    completion(WaffrEntry(date: Date(), data: WaffrData.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WaffrEntry>) -> Void) {
    let midnight = Calendar.current.startOfDay(
      for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    )
    completion(Timeline(
      entries: [WaffrEntry(date: Date(), data: WaffrData.load())],
      policy: .after(midnight.addingTimeInterval(60))
    ))
  }
}

// MARK: - Style

// Tokens from lib/core/theme/app_color.dart and the glass surface in
// lib/widgets/containers/glass.dart, so the widgets read like the app's cards.
private struct Palette {
  let scheme: ColorScheme
  private var dark: Bool { scheme == .dark }

  private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
  }

  var surface: Color { dark ? Self.rgb(26, 32, 28) : Self.rgb(248, 247, 246) }
  var accent: Color { dark ? Self.rgb(123, 193, 122) : Self.rgb(37, 74, 35) }
  /// Top of a progress fill: the accent 18% toward white.
  var accentLight: Color { dark ? Self.rgb(147, 204, 146) : Self.rgb(76, 107, 75) }
  var primary: Color { dark ? .white : .black }
  var secondary: Color { dark ? Self.rgb(155, 165, 158) : Self.rgb(111, 111, 111) }
  var accentTrack: Color { accent.opacity(0.12) }
  var neutralTrack: Color { primary.opacity(0.08) }
  var sheen: Color { .white.opacity(dark ? 0.045 : 0.6) }
  var rim: Color { dark ? .white.opacity(0.14) : .black.opacity(0.07) }
  var buttonFill: Color { dark ? Self.rgb(38, 44, 40) : .white }
}

// Outfit for numbers and Tajawal for Arabic, as in the app. Font files and
// UIAppFonts: ios/WaffrWidgets/Fonts and Info.plist.
private enum WaffrFont {
  static func arabic(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "Tajawal-Bold" : "Tajawal-Medium", size: size)
  }

  static func number(_ size: CGFloat, heavy: Bool = false) -> Font {
    .custom(heavy ? "Outfit-ExtraBold" : "Outfit-Bold", size: size)
  }
}

private func link(_ path: String) -> URL {
  // The homeWidget query lets the home_widget plugin report the tap.
  URL(string: "waffr://\(path)?homeWidget")!
}

// Surface fill with a soft sheen from the top corner, like GlassContainer.
private struct GlassFill: View {
  let palette: Palette

  var body: some View {
    LinearGradient(
      colors: [palette.sheen, .clear],
      startPoint: .topLeading,
      endPoint: UnitPoint(x: 0.6, y: 0.7)
    )
    .background(palette.surface)
  }
}

private struct WidgetFrame<Content: View>: View {
  @Environment(\.colorScheme) private var scheme
  var glass = true
  let content: (Palette) -> Content

  var body: some View {
    let palette = Palette(scheme: scheme)
    let inner = content(palette)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environment(\.layoutDirection, .rightToLeft)
    if #available(iOSApplicationExtension 17.0, *) {
      inner.containerBackground(for: .widget) {
        if glass { GlassFill(palette: palette) } else { palette.surface }
      }
    } else {
      inner.padding().background(glass ? AnyView(GlassFill(palette: palette)) : AnyView(palette.surface))
    }
  }
}

// Pill progress bar with a fill a shade lighter on top, like the app's.
private struct ProgressPill: View {
  let value: Double
  let height: CGFloat
  let track: Color
  let palette: Palette

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        if value > 0 {
          Capsule()
            .fill(LinearGradient(colors: [palette.accentLight, palette.accent], startPoint: .top, endPoint: .bottom))
            .frame(width: max(height, proxy.size.width * value))
        }
      }
    }
    .frame(height: height)
  }
}

// Section header from the savings screen: a tinted icon tile and a title.
private struct SectionHeader: View {
  let icon: String
  let title: String
  let palette: Palette

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(palette.accent)
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.accent.opacity(0.10)))
      Text(title).font(WaffrFont.arabic(14, bold: true)).foregroundColor(palette.primary).lineLimit(1)
    }
  }
}

// MARK: - Widgets

struct BalanceView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            Text("الرصيد الحالي").font(WaffrFont.arabic(13.5)).foregroundColor(p.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(data.balanceAmount).font(WaffrFont.number(32))
                .foregroundColor(p.accent).minimumScaleFactor(0.6).lineLimit(1)
              Text(data.balanceCurrency).font(WaffrFont.arabic(15)).foregroundColor(p.secondary)
            }
          }
          Spacer(minLength: 8)
          Link(destination: link("add-expense")) {
            Image(systemName: "minus.circle")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(p.accent)
              .frame(width: 40, height: 40)
              .background(Circle().fill(p.buttonFill))
              .overlay(Circle().stroke(p.rim, lineWidth: 1))
          }
        }
        Spacer(minLength: 4)
        Text(data.balancePercentLabel).font(WaffrFont.arabic(12.5, bold: true)).foregroundColor(p.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
        ProgressPill(value: data.balancePercent, height: 20, track: p.accentTrack, palette: p)
          .padding(.top, 3)
        Text(data.balanceCaption).font(WaffrFont.arabic(12.5)).foregroundColor(p.secondary)
          .lineLimit(1).padding(.top, 7)
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

// The dashboard's add income / add expense buttons as two glass pills.
private struct ActionPill: View {
  let title: String
  let icon: String
  let path: String
  let palette: Palette

  var body: some View {
    Link(destination: link(path)) {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(palette.accent)
        Text(title).font(WaffrFont.arabic(14.5, bold: true)).foregroundColor(palette.primary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(RoundedRectangle(cornerRadius: 22).fill(palette.buttonFill))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.rim, lineWidth: 1))
    }
  }
}

struct QuickAddView: View {
  var body: some View {
    WidgetFrame(glass: false) { p in
      HStack(spacing: 10) {
        ActionPill(title: "إضافة دخل", icon: "plus.circle", path: "add-income", palette: p)
        ActionPill(title: "إضافة مصروف", icon: "minus.circle", path: "add-expense", palette: p)
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
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(icon: "wallet.pass", title: "هدف التوفير", palette: p)
        Spacer(minLength: 6)
        Text(data.goalName).font(WaffrFont.arabic(14.5, bold: true)).foregroundColor(p.primary).lineLimit(1)
        if !data.goalEmpty {
          HStack(spacing: 8) {
            ProgressPill(value: data.goalPercent, height: 16, track: p.neutralTrack, palette: p)
            Text(data.goalPercentLabel).font(WaffrFont.number(12.5)).foregroundColor(p.secondary)
          }
          .padding(.top, 8)
        }
        Text(data.goalCaption).font(WaffrFont.arabic(12)).foregroundColor(p.secondary)
          .lineLimit(2).padding(.top, 7)
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
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(icon: "calendar", title: "الالتزام القادم", palette: p)
        Spacer(minLength: 6)
        Text(data.obligationName).font(WaffrFont.arabic(14.5, bold: true)).foregroundColor(p.primary).lineLimit(1)
        if !data.obligationEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(data.obligationValue).font(WaffrFont.number(22)).foregroundColor(p.accent)
              .minimumScaleFactor(0.6).lineLimit(1)
            Text(data.balanceCurrency).font(WaffrFont.arabic(13)).foregroundColor(p.secondary)
          }
          .padding(.top, 2)
          Text(data.obligationWhen).font(WaffrFont.arabic(11.5, bold: true)).foregroundColor(p.accent)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(p.accent.opacity(0.10)))
            .padding(.top, 6)
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

// Ring toward the next milestone with the Waffr mark, as on the profile card.
private struct StreakRing: View {
  let progress: Double
  let palette: Palette

  var body: some View {
    ZStack {
      Circle().stroke(palette.accentTrack, lineWidth: 7)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          AngularGradient(colors: [palette.accent.opacity(0.55), palette.accent], center: .center,
                          startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
          style: StrokeStyle(lineWidth: 7, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      Image("WidgetLogo").resizable().scaledToFit().frame(width: 34, height: 34)
    }
    .frame(width: 76, height: 76)
  }
}

struct StreakView: View {
  let data: WaffrData

  var body: some View {
    WidgetFrame { p in
      VStack(spacing: 4) {
        StreakRing(progress: data.streakPercent, palette: p)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(data.streakCount).font(WaffrFont.number(28, heavy: true)).foregroundColor(p.accent)
          Text(data.streakWord).font(WaffrFont.arabic(14, bold: true)).foregroundColor(p.primary)
        }
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
