# `FocusCoreTests` resources

Everything in this directory is declared on the **test target**:

```swift
.testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], resources: [.copy("Resources")])
```

That declaration is the whole reason the directory exists here rather than at the repository
root. SwiftPM bundles only resources declared *inside* a package: a fixture placed at, say,
`/Fixtures/SchemaV1/` is simply absent from the built product, in both the `swift test` and
the `xcodebuild test` lane, and `Bundle.module` can never find it.

`.copy` rather than `.process` is also load-bearing. `.copy` preserves the directory
structure verbatim, so

```swift
Bundle.module.url(forResource: "FocusSentinel.store", withExtension: nil, subdirectory: "Resources/SchemaV1")
```

resolves in both lanes. `.process` would flatten and transform the tree, and a SwiftData
store must reach the bundle byte-for-byte or it is not a fixture of anything.

Contents:

| path | what it is |
|---|---|
| `SchemaV1/` | a committed SwiftData store written through schema v1, plus the notes on how it was produced and how to regenerate it |
