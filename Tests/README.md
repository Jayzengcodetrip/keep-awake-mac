# Assertion smoke test

This opt-in test creates only its own `PreventUserIdleSystemSleep` assertion. It installs a system-enforced 20-second release timeout, confirms the real assertion type and level, checks repeated enable/disable calls, releases the assertion, and confirms the original ID is no longer returned by the system. It never changes power settings or touches another application's assertions.

From the repository root on macOS with Xcode Command Line Tools and Swift 6 (verified with Apple Swift 6.3.3):

```sh
mkdir -p build
xcrun swiftc -swift-version 6 -parse-as-library \
  Sources/AwakeAssertion.swift Tests/AwakeAssertionSmokeTest.swift \
  -framework IOKit -o build/awake-assertion-smoke-test
build/awake-assertion-smoke-test
```

A passing run prints `CREATE/CHECK PASS` and `RELEASE/CHECK PASS` and exits with status 0. Failure exits with status 1. The process explicitly releases its own assertion before exiting; macOS also removes process-owned assertions on process exit.

The test does not launch the menu-bar app, register a login item, display a window, or contact the network. Actual menu-bar interaction and appearance still require manual testing on each supported macOS release.
