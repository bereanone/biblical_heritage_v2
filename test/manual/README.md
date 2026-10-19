# Manual fixture diagnostics

`sl27_live_repro.dart` is a retained historical diagnostic, not an automated regression test. It requires the original private SL27 seed and trace directory named inside it, which are not repository fixtures. Run it explicitly only after providing an isolated copy of those fixtures. It has been moved out of automatic `*_test.dart` discovery; no library records or original fixtures were deleted.
