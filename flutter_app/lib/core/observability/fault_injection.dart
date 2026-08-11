/// Fault injection for deterministic ADI capture tests (v0.1 infrastructure).
///
/// Goal: prove the Agent can obtain *reliable evidence* without waiting for a
/// flaky, real-world bug. Instead of hoping a `RenderOverflow` happens on a
/// real device, a test flips [enabled] on and the targeted renderer
/// (e.g. [CodeBlock]) manufactures a *known* failure. The observability layer
/// then captures the full causal chain, which the ADI CLI classifies into a
/// stable `RenderOverflow`.
///
/// Safety: this is test-only infrastructure. [enabled] defaults to `false` and
/// MUST never be toggled by production code. Shipping behavior is unchanged when
/// the flag is off (the default). See ADR-0024 §9 (fault-injection plan).
library;

/// Global kill-switch for all fault-injection behaviors.
///
/// Tests set this to `true` in `setUp` and reset it in `tearDown`. Production
/// never sets it, so no shipped UI / behavior change occurs.
class FaultInjection {
  /// Whether any fault-injection behavior is active.
  ///
  /// Gated and default-off: zero impact on production builds.
  static bool enabled = false;

  /// Whether the deterministic `RenderOverflow` fault should be injected into
  /// [CodeBlock] rendering (the FULL-observability capture path).
  static bool get renderOverflowEnabled => enabled;
}
