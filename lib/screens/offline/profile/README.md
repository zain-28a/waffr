# Profile and wallet expression

`ProfileScreen` displays the identity, usage streak, usage statistics and the
wallet backdrop. Identity editing remains in Settings. The balance scale was
removed; it must not be restored as part of motion/performance fixes.

The wallet's mouth follows the same `HealthBand` as the profile insight report:
excellent and good smile, fair is nearly neutral, and low frowns. This is an
overall signal, not a requirement to save as much as the user spends.

The score's savings component compares **net average monthly saving to income**.
A 20% saving rate receives the full savings-component credit; a smaller rate
can still produce a smile when the other supported factors are healthy. The
average uses available savings history, capped at three months, rather than
dividing a new user's first deposit by three. Withdrawals reduce net saving.
The other factors are obligations, balance coverage, spending trend and
logging consistency. Missing income omits income-dependent factors. With no
financial movements the backdrop retains the brand's default smile.

`WalletBackdrop` precaches the mouthless logo, draws a vector mouth and morphs
between bands. Its breath is isolated from static artwork by a repaint boundary.
Hidden/reduced-motion pages stop breathing. Reduced motion settles appearance
and mouth changes immediately.

Health refreshes are coalesced and serialized. Changes on a hidden tab only
mark the score dirty; returning computes the latest result. An older load is
discarded if data changed while it was waiting. `StreakCard` only replays for
a count/replay-token change and shows final values directly with reduced motion.

Regression tests include 20% saving with 80% spending, 10% saving with adequate
remaining balance, withdrawals, new-user history, and retained-tab motion.
