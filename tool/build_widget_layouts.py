#!/usr/bin/env python3
"""Writes the Android home-widget layouts (res/layout/widget_*.xml).

Every widget shares one card style (the glass card background, the icon
tile header, Tajawal labels and Outfit numbers), so the layouts are built
from the helpers below instead of being edited one by one. Change a helper
or a layout here and run the script again; the XML files are committed.

Ids must match android/app/src/main/kotlin/com/waffr/app/widgets/
WaffrWidgets.kt, which fills them.

Usage:
  python3 tool/build_widget_layouts.py
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "android/app/src/main/res/layout"
NS = 'xmlns:android="http://schemas.android.com/apk/res/android"'

def root(children, pad=(16, 14), comment=''):
    h, v = pad
    c = f'<!-- {comment} -->\n' if comment else ''
    return f'''<?xml version="1.0" encoding="utf-8"?>
{c}<LinearLayout {NS}
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background"
    android:layoutDirection="rtl"
    android:orientation="vertical"
    android:paddingStart="{h}dp"
    android:paddingTop="{v}dp"
    android:paddingEnd="{h}dp"
    android:paddingBottom="{v}dp">
{children}
</LinearLayout>
'''

def text(tid=None, value=None, font='tajawal_medium', size=12.5, color='widget_text_secondary',
         width='wrap_content', weight=None, lines=1, gravity=None, extra=''):
    a = []
    if tid: a.append(f'android:id="@+id/{tid}"')
    a.append(f'android:layout_width="{"0dp" if weight else width}"')
    a.append('android:layout_height="wrap_content"')
    if weight: a.append(f'android:layout_weight="{weight}"')
    if gravity: a.append(f'android:gravity="{gravity}"')
    a.append('android:ellipsize="end"')
    a.append(f'android:fontFamily="@font/{font}"')
    a.append('android:includeFontPadding="false"')
    a.append(f'android:maxLines="{lines}"')
    if value: a.append(f'android:text="{value}"')
    a.append(f'android:textColor="@color/{color}"')
    a.append(f'android:textSize="{size}sp"')
    if extra: a.append(extra)
    return '<TextView\n    ' + '\n    '.join(a) + ' />'

def indent(s, n=4):
    return '\n'.join((' ' * n + l) if l.strip() else l for l in s.split('\n'))

def row(children, gravity='center_vertical', extra='', width='match_parent'):
    return f'''<LinearLayout
    android:layout_width="{width}"
    android:layout_height="wrap_content"
    android:gravity="{gravity}"
    android:orientation="horizontal"{(' ' + extra) if extra else ''}>
{indent(children)}
</LinearLayout>'''

def column(children, weight=None, extra=''):
    w = 'android:layout_width="0dp"\n    android:layout_weight="%s"' % weight if weight else 'android:layout_width="match_parent"'
    return f'''<LinearLayout
    {w}
    android:layout_height="wrap_content"
    android:orientation="vertical"{(' ' + extra) if extra else ''}>
{indent(children)}
</LinearLayout>'''

def spacer():
    return '''<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="0dp"
    android:layout_weight="1"
    android:orientation="vertical" />'''

def gap(dp):
    return f'''<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="{dp}dp"
    android:orientation="vertical" />'''

def hgap(dp):
    return f'''<LinearLayout
    android:layout_width="{dp}dp"
    android:layout_height="1dp"
    android:orientation="horizontal" />'''

def divider():
    return '''<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="1dp"
    android:layout_marginTop="10dp"
    android:layout_marginBottom="10dp"
    android:background="@color/widget_rim"
    android:orientation="horizontal" />'''

def icon_tile(icon, size=30, glyph=17):
    return f'''<FrameLayout
    android:layout_width="{size}dp"
    android:layout_height="{size}dp"
    android:background="@drawable/widget_icon_tile">
    <ImageView
        android:layout_width="{glyph}dp"
        android:layout_height="{glyph}dp"
        android:layout_gravity="center"
        android:importantForAccessibility="no"
        android:src="@drawable/{icon}" />
</FrameLayout>'''

def header(icon, title, title_id=None, trailing=''):
    return row(icon_tile(icon) + '\n' + text(title_id, title, 'tajawal_bold', 13.5, 'widget_text_primary', weight=1,
               extra='android:layout_marginStart="9dp"') + (('\n' + trailing) if trailing else ''))

def amount(aid, cid, size, autosize=False):
    auto = ''
    if autosize:
        auto = ('android:autoSizeMaxTextSize="%ssp"\n    android:autoSizeMinTextSize="14sp"\n    '
                'android:autoSizeStepGranularity="1sp"\n    android:autoSizeTextType="uniform"' % size)
    amt = text(aid, None, 'outfit_bold', size, 'widget_accent', width='0dp' if autosize else 'wrap_content',
               weight=1 if autosize else None, extra=auto)
    cur = text(cid, None, 'tajawal_medium', 13, 'widget_text_secondary', extra='android:layout_marginStart="6dp"')
    return row(amt + '\n' + cur, gravity='bottom')

def progress(pid, height=8, drawable='widget_progress_accent', margin=6):
    return f'''<ProgressBar
    android:id="@+id/{pid}"
    style="@android:style/Widget.ProgressBar.Horizontal"
    android:layout_width="match_parent"
    android:layout_height="{height}dp"
    android:layout_marginTop="{margin}dp"
    android:max="100"
    android:maxHeight="{height}dp"
    android:minHeight="{height}dp"
    android:mirrorForRtl="true"
    android:progressDrawable="@drawable/{drawable}" />'''

def round_button(bid, icon, desc, size=38):
    return f'''<ImageView
    android:id="@+id/{bid}"
    android:layout_width="{size}dp"
    android:layout_height="{size}dp"
    android:background="@drawable/widget_button"
    android:contentDescription="@string/{desc}"
    android:padding="10dp"
    android:src="@drawable/{icon}" />'''

def pill(pid, icon, label, weight=1, height=42):
    return f'''<LinearLayout
    android:id="@+id/{pid}"
    android:layout_width="0dp"
    android:layout_height="{height}dp"
    android:layout_weight="{weight}"
    android:background="@drawable/widget_pill"
    android:gravity="center"
    android:orientation="horizontal">
    <ImageView
        android:layout_width="18dp"
        android:layout_height="18dp"
        android:importantForAccessibility="no"
        android:src="@drawable/{icon}" />
{indent(text(None, label, 'tajawal_bold', 13.5, 'widget_text_primary', extra='android:layout_marginStart="7dp"'))}
</LinearLayout>'''

def stat(label, vid):
    return column(text(None, label, 'tajawal_medium', 12, 'widget_text_secondary') + '\n' +
                  text(vid, None, 'outfit_bold', 17, 'widget_text_primary', extra='android:layout_marginTop="3dp"'), weight=1)

def dot(did, size=9):
    return f'''<ImageView
    android:id="@+id/{did}"
    android:layout_width="{size}dp"
    android:layout_height="{size}dp"
    android:importantForAccessibility="no"
    android:src="@drawable/widget_dot" />'''

def top_row(i, with_bar):
    head = row(dot(f'month_dot_{i}') + '\n' +
               text(f'month_name_{i}', None, 'tajawal_medium', 12.5, 'widget_text_primary', weight=1, extra='android:layout_marginStart="7dp"') + '\n' +
               text(f'month_amount_{i}', None, 'outfit_bold', 12.5, 'widget_text_primary', extra='android:layout_marginStart="6dp"') + '\n' +
               text(f'month_percent_{i}', None, 'outfit_bold', 12, 'widget_text_secondary', extra='android:layout_marginStart="6dp"\n    android:minWidth="34dp"\n    android:gravity="end"'))
    body = head
    if with_bar:
        body += '\n' + progress(f'month_bar_{i}', height=5, drawable='widget_progress_neutral', margin=4)
    return column(body, extra=f'android:id="@+id/month_row_{i}"\n    android:layout_marginTop="7dp"')

def recent_row(i):
    left = column(text(f'recent_title_{i}', None, 'tajawal_medium', 13, 'widget_text_primary') + '\n' +
                  text(f'recent_day_{i}', None, 'tajawal_medium', 11, 'widget_text_secondary', extra='android:layout_marginTop="2dp"'),
                  weight=1, extra='android:layout_marginStart="9dp"')
    return row(dot(f'recent_dot_{i}', 10) + '\n' + left + '\n' +
               text(f'recent_amount_{i}', None, 'outfit_bold', 13.5, 'widget_text_primary', extra='android:layout_marginStart="6dp"'),
               extra=f'android:id="@+id/recent_row_{i}"\n    android:layout_marginTop="8dp"')

files = {}

# Balance
files['widget_balance_small'] = root('\n'.join([
    header('ic_widget_wallet', '@string/widget_balance_short'),
    spacer(),
    amount('balance_amount', 'balance_currency', 26, autosize=True),
    progress('balance_progress'),
    text('balance_percent', None, 'tajawal_bold', 11.5, extra='android:layout_marginTop="6dp"'),
]), comment='Balance, small: the amount and how much of the period is left.')

files['widget_balance'] = root('\n'.join([
    header('ic_widget_wallet', '@string/widget_balance_title', trailing=round_button('balance_add_income', 'ic_widget_income', 'widget_add_income') + '\n' + hgap(8) + '\n' + round_button('balance_add_expense', 'ic_widget_expense', 'widget_add_expense')),
    spacer(),
    amount('balance_amount', 'balance_currency', 32),
    progress('balance_progress'),
    row(text('balance_caption', None, weight=1) + '\n' + text('balance_percent', None, 'tajawal_bold', 12, extra='android:layout_marginStart="8dp"'), extra='android:layout_marginTop="7dp"'),
], ), pad=(18, 14), comment='Balance, medium: mirrors the dashboard balance card (_BalanceHero).')

files['widget_balance_large'] = root('\n'.join([
    header('ic_widget_wallet', '@string/widget_balance_title'),
    gap(14),
    amount('balance_amount', 'balance_currency', 34),
    progress('balance_progress', margin=8),
    row(text('balance_caption', None, weight=1) + '\n' + text('balance_percent', None, 'tajawal_bold', 12, extra='android:layout_marginStart="8dp"'), extra='android:layout_marginTop="7dp"'),
    divider(),
    row(stat('@string/widget_cycle_income', 'cycle_income') + '\n' + stat('@string/widget_cycle_spent', 'cycle_spent')),
    spacer(),
    row(pill('balance_add_expense', 'ic_widget_expense', '@string/widget_expense_short') + '\n' + hgap(10) + '\n' + pill('balance_add_income', 'ic_widget_income', '@string/widget_income_short')),
]), pad=(18, 16), comment='Balance, large: the balance card, the period income and spending, and quick add.')

# Month
month_head = header('ic_widget_chart', '@string/widget_month_title', trailing=text('month_label', None, 'tajawal_medium', 12))
files['widget_month'] = root('\n'.join([
    month_head,
    spacer(),
    row(stat('@string/widget_month_spent', 'month_spent') + '\n' + stat('@string/widget_month_income', 'month_income')),
    text('month_note', None, 'tajawal_medium', 12, extra='android:layout_marginTop="6dp"\n    android:visibility="gone"'),
    top_row(0, False),
]), pad=(18, 14), comment='This month, medium: spent, income and the largest category.')

files['widget_month_large'] = root('\n'.join([
    month_head,
    gap(12),
    row(stat('@string/widget_month_spent', 'month_spent') + '\n' + stat('@string/widget_month_income', 'month_income')),
    divider(),
    text('month_note', None, 'tajawal_medium', 12.5, extra='android:visibility="gone"'),
    top_row(0, True), top_row(1, True), top_row(2, True), top_row(3, True),
    spacer(),
]), pad=(18, 16), comment='This month, large: spent, income and the four largest categories with their shares.')

# Quick add
files['widget_quick_add_small'] = root('\n'.join([
    row(pill('quick_add_expense', 'ic_widget_expense', '@string/widget_expense_short', height=44)),
    gap(8),
    row(pill('quick_add_income', 'ic_widget_income', '@string/widget_income_short', height=44)),
]), pad=(12, 12), comment='Quick add, small: two stacked buttons.')

files['widget_quick_add_row'] = root(
    row(pill('quick_add_expense', 'ic_widget_expense', '@string/widget_add_expense', height=40) + '\n' + hgap(10) + '\n' + pill('quick_add_income', 'ic_widget_income', '@string/widget_add_income', height=40)),
    pad=(10, 8), comment='Quick add, one row high (4 x 1): the two buttons side by side.')

files['widget_quick_add'] = root('\n'.join([
    header('ic_widget_plus', '@string/widget_quick_add_title'),
    spacer(),
    row(pill('quick_add_expense', 'ic_widget_expense', '@string/widget_add_expense') + '\n' + hgap(10) + '\n' + pill('quick_add_income', 'ic_widget_income', '@string/widget_add_income')),
    text('recent_line', None, 'tajawal_medium', 12, extra='android:layout_marginTop="8dp"'),
]), pad=(16, 14), comment='Quick add, medium: add an expense or an income, and the last record.')

files['widget_quick_add_large'] = root('\n'.join([
    header('ic_widget_receipt', '@string/widget_recent_title'),
    row(pill('quick_add_expense', 'ic_widget_expense', '@string/widget_add_expense') + '\n' + hgap(10) + '\n' + pill('quick_add_income', 'ic_widget_income', '@string/widget_add_income'), extra='android:layout_marginTop="12dp"'),
    gap(4),
    text('recent_empty', '@string/widget_recent_empty', 'tajawal_medium', 12.5, extra='android:layout_marginTop="10dp"\n    android:visibility="gone"'),
    recent_row(0), recent_row(1), recent_row(2), recent_row(3),
    spacer(),
]), pad=(16, 16), comment='Quick add, large: the add buttons and the four latest records.')

# Goal
files['widget_goal'] = root('\n'.join([
    header('ic_widget_target', '@string/widget_goal_title'),
    spacer(),
    text('goal_name', None, 'tajawal_bold', 15, 'widget_text_primary'),
    row(text('goal_percent', None, 'outfit_bold', 22, 'widget_accent'), extra='android:id="@+id/goal_progress_row"\n    android:layout_marginTop="2dp"'),
    progress('goal_progress'),
    text('goal_caption', None, 'tajawal_medium', 11.5, lines=2, extra='android:layout_marginTop="6dp"'),
]), comment='Savings goal, small: name, percent and progress.')

files['widget_goal_medium'] = root('\n'.join([
    header('ic_widget_target', '@string/widget_goal_title', trailing=text('goal_percent', None, 'outfit_bold', 20, 'widget_accent')),
    spacer(),
    text('goal_name', None, 'tajawal_bold', 16, 'widget_text_primary'),
    row(progress('goal_progress', margin=8), extra='android:id="@+id/goal_progress_row"'),
    row(text('goal_caption', None, weight=1) + '\n' + text('goal_remaining', None, 'tajawal_bold', 12, extra='android:layout_marginStart="8dp"'), extra='android:layout_marginTop="7dp"'),
]), pad=(18, 14), comment='Savings goal, medium: name, progress, saved and remaining.')

# Obligation
files['widget_obligation'] = root('\n'.join([
    header('ic_widget_event', '@string/widget_obligation_title'),
    spacer(),
    text('obligation_name', None, 'tajawal_bold', 15, 'widget_text_primary'),
    row(text('obligation_value', None, 'outfit_bold', 22, 'widget_text_primary') + '\n' + text('obligation_currency', None, 'tajawal_medium', 12, extra='android:layout_marginStart="5dp"'), gravity='bottom', extra='android:id="@+id/obligation_amount_row"\n    android:layout_marginTop="3dp"'),
    text('obligation_when', None, 'tajawal_bold', 12, 'widget_accent', extra='android:layout_marginTop="6dp"\n    android:background="@drawable/widget_chip"\n    android:paddingStart="9dp"\n    android:paddingTop="3dp"\n    android:paddingEnd="9dp"\n    android:paddingBottom="3dp"'),
]), comment='Next bill, small: name, amount and when it is due.')

files['widget_obligation_medium'] = root('\n'.join([
    header('ic_widget_event', '@string/widget_obligation_title', trailing=text('obligation_when', None, 'tajawal_bold', 12, 'widget_accent', extra='android:background="@drawable/widget_chip"\n    android:paddingStart="9dp"\n    android:paddingTop="3dp"\n    android:paddingEnd="9dp"\n    android:paddingBottom="3dp"')),
    spacer(),
    row(text('obligation_name', None, 'tajawal_bold', 16, 'widget_text_primary', weight=1) + '\n' +
        row(text('obligation_value', None, 'outfit_bold', 22, 'widget_text_primary') + '\n' + text('obligation_currency', None, 'tajawal_medium', 12, extra='android:layout_marginStart="5dp"'), gravity='bottom', width='wrap_content', extra='android:id="@+id/obligation_amount_row"')),
]), pad=(18, 14), comment='Next bill, medium: when it is due, its name and amount.')

# Streak
ring = '''<FrameLayout
    android:layout_width="%(s)sdp"
    android:layout_height="%(s)sdp">
    <ProgressBar
        android:id="@+id/streak_ring"
        style="@android:style/Widget.ProgressBar.Horizontal"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:max="100"
        android:progressDrawable="@drawable/widget_ring"
        android:rotation="-90" />
    <LinearLayout
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:gravity="center"
        android:orientation="vertical">
%(count)s
%(word)s
    </LinearLayout>
</FrameLayout>'''
def ring_of(s, size):
    return ring % {'s': s, 'count': indent(text('streak_count', None, 'outfit_bold', size, 'widget_text_primary'), 8),
                   'word': indent(text('streak_word', None, 'tajawal_medium', 11.5), 8)}
files['widget_streak'] = root('\n'.join([
    header('ic_widget_flame', '@string/widget_streak_title'),
    spacer(),
    row(ring_of(78, 26), gravity='center'),
    spacer(),
]), comment='Streak, small: the ring toward the next milestone.')
files['widget_streak_medium'] = root('\n'.join([
    header('ic_widget_flame', '@string/widget_streak_title'),
    spacer(),
    row(ring_of(76, 24) + '\n' + column(text('streak_label', None, 'tajawal_bold', 15, 'widget_text_primary') + '\n' +
        text('streak_next', None, 'tajawal_medium', 12, lines=2, extra='android:layout_marginTop="4dp"'), weight=1, extra='android:layout_marginStart="14dp"')),
    spacer(),
]), pad=(18, 14), comment='Streak, medium: the ring, the run in words and the next milestone.')

for name, xml in files.items():
    (OUT / f'{name}.xml').write_text(xml)
print(len(files))
