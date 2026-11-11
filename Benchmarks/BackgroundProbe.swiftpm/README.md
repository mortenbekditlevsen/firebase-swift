# Background probe

An iOS app that measures how the Realtime Database's transports cope with
backgrounding and network changes on a real device. It's for choosing the
default transport on Apple platforms (see [Benchmarks/README.md](../README.md)).

On each return to the foreground, the app writes a new value over REST, which
doesn't go through the connection. It then times how long the connection takes
to deliver that change. A connection that died in the background but still
reports `.info/connected` as true never delivers it. Upstream's NSURLSession
transport had that problem in #14188, #13877 and #13855.

## Running it

1. Pick a database. Either:
   - **A Realtime Database you own.** Give it rules that open only the probe's
     path:

     ```json
     { "rules": { "probe": { ".read": true, ".write": true } } }
     ```

     The URL is `https://<project>-default-rtdb.firebaseio.com`, or the
     region's URL.
   - **The Database emulator on your Mac.** Run
     `firebase emulators:start --only database` with `"host": "0.0.0.0"` for
     the database in `firebase.json`. The URL is then
     `http://<your Mac's address>:9000?ns=demo-probe`. A device on the same
     Wi-Fi reaches it, but over cellular it can't, so the network-switch
     scenarios need a real database.
2. Open this folder in Xcode, select the `BackgroundProbe` target, and under
   Signing & Capabilities set your team. Then run it on the phone.
3. Enter the URL, pick a transport and tap **Start**.
4. Pick a scenario, do what it says, and come back. Each return to the
   foreground is one test. Repeat each scenario a few times for each transport,
   and switch scenarios and transports in the app as you go.

| Scenario | What to do |
|---|---|
| Background 30 s, 5 min, 30 min | Leave the app for that long, then open it again |
| Screen off 10 min | Lock the phone with the app open, unlock it after 10 minutes |
| Wi-Fi → cellular, cellular → Wi-Fi | Turn Wi-Fi off or on in Control Center with the app open, then tap **Test now** |
| Airplane mode | On for a minute, then off, with the app open; then **Test now** |
| Low Power Mode | Turn it on, then repeat a background scenario |

## Results

The **Results** section shows, for each transport and scenario:
- the number of tests;
- the median and worst time until the change arrived;
- how many tests got nothing within 60 seconds ("never recovered");
- spurious disconnects: `.info/connected` going false while the app was in the
  foreground.

**Share the log** exports every event as JSON Lines (`probe-log.jsonl`). Each
line carries:
- the transport and scenario;
- the network (Wi-Fi, cellular, offline);
- whether Low Power Mode was on;
- the milliseconds since the app came to the foreground.

The events are also signposts (subsystem `dev.firebase-swift.BackgroundProbe`),
so you can watch them in Instruments.

For a run without tapping, for example in the Simulator, launch the app with
`-autostart -databaseURL <url> -transport nio|networkFramework|urlSession`.
