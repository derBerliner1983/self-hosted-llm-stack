# Android development

Creating, building and testing Android projects.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/android.md)

**Documentation:** [Installation & getting started](installation.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · **Android development** · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Android development (`android-mcp`)

The throwaway sandbox isn't enough for Android: Gradle pulls dependencies from the network, a build takes minutes rather than seconds, and without a persistent cache every run would start from scratch. The stack therefore ships a **dedicated service** for it (`android-mcp/`) where builds run **directly in the container** — which also spares it the Docker socket access the code sandbox needs.

Included: **JDK 21**, the **Android SDK** (command-line tools, platform-tools, build-tools, platform android-34) and **Gradle**. Tools exposed to the model:

| Tool | Purpose |
|---|---|
| `list_projects()` | List projects in the workspace |
| `create_project(name, package_name)` | Create a new, buildable Java/Gradle project (manifest, MainActivity, example test, Gradle wrapper) |
| `gradle(project, args)` | Run a Gradle task — `assembleDebug`, `test`, `clean`, `tasks`, … |
| `sdk_packages()` | Show installed SDK packages |
| `install_sdk_package(package)` | Install another SDK package, e.g. `platforms;android-35` |

Sources live in the `android-workspace` volume, which is **also mounted in the `mcp` container** at `/workspace`. That lets the model edit the code with the **filesystem tools** and build it with `gradle` — writing and building hit the same files.

**Typical chat flow:** "Create an Android project `MyApp`" → `create_project` → model edits `MainActivity.java` via the filesystem tool → "build it" → `gradle(project="MyApp", args="assembleDebug")` → on errors the model reads the Gradle output and fixes it itself.

**Build and start:**

```bash
docker compose -f docker-compose.rocm.yml up -d --build android-mcp
./scripts/wire-mcp.sh    # adds /workspace to the filesystem tool
```

> ⚠️ **The image is large (~6–8 GB) and the first build takes a while** (Android SDK). The first Gradle run of a project also pulls Gradle and all dependencies — after that the cache in the `android-gradle` volume kicks in. If you don't need Android development, drop the service entirely (and remove the `android_build` entry from `mcpo/config.template.json`).

**Limits:**

- **No emulator, no running the app.** Building, compiling and unit testing happen in the container; trying out the APK needs a real device. An emulator would need `/dev/kvm` inside the container and is fragile in practice.
- **No `adb` access to your devices** — those hang off your machine, not the server.
- **Network access is intentional here** (Gradle needs it) — unlike the code sandbox. Gradle build scripts are executable code, so this service is about as powerful as the sandbox, just with internet. Like the sandbox it is therefore reachable **internally only**, with no published port.
- **The project template is deliberately minimal** (Java, no Kotlin/Compose) — fewer version dependencies between Gradle, AGP and Kotlin that have to line up. Kotlin/Compose can be added within the project itself.

Configurable via `.env`: `ANDROID_DEFAULT_TIMEOUT` (default `600` s), `ANDROID_MAX_TIMEOUT` (`1800` s), `ANDROID_COMPILE_SDK` (`34`), `ANDROID_MIN_SDK` (`24`). SDK/Gradle/AGP versions are build arguments in `android-mcp/Dockerfile`.
