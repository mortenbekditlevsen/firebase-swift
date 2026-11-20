# swift-corelibs-foundation WebSocket repro

`server.py` and `client.swift` reproduce three bugs in swift-corelibs-foundation's
`URLSessionWebSocketTask`, found by the Database's transport conformance tests on
Windows: fragmented messages aren't joined, text that isn't valid UTF-8 crashes
the process, and the task opens on a response that isn't 101.

`.github/workflows/corelibs-websocket-repro.yml` runs them on Windows and macOS
whenever they change on a `windows/` branch. Remove this folder and the
workflow once the issues are filed.
