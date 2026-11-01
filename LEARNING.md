# InterviewGuide learning workspace

This workspace builds on [Snailclimb/interview-guide](https://github.com/Snailclimb/interview-guide). Preserve the upstream history, attribution and license, and use your commits to show the changes you actually implement and understand.

## Git workflow

- `origin` points to your GitHub fork, where you push your work.
- `upstream` points to the original Snailclimb repository.
- `learning/interview-guide` is the working branch for this learning project.

Check the active branch and remotes before starting:

```powershell
git branch --show-current
git remote -v
git status
```

After completing and checking one small task, inspect and commit its specific files. For example, after implementing an upload page:

```powershell
git diff
git add frontend/src/pages/UploadPage.tsx
git diff --cached
git commit -m "feat: implement single-file resume upload"
git push -u origin learning/interview-guide
```

Stage the files belonging to that task. Keep `.env`, API keys, local data, logs and dependency folders out of commits. Record real improvements such as a page, a failure case or a meaningful test; do not create artificial activity-only commits.

When you later need upstream changes, fetch and inspect them before merging or rebasing. Keep the current learning baseline stable while finishing a task.

## Local environment

Run commands from the repository root. `dev.cmd` starts its own PowerShell process and changes neither your machine-wide Java settings nor your saved PowerShell execution policy. Backend commands choose a local JDK 25 automatically. Set `LEARNING_JAVA_HOME` for the current terminal if you need to choose a particular installation.

For everyday use, double-click `start.cmd`, or use one command in IDEA's terminal:

```powershell
.\dev.cmd start
```

The launcher initializes missing configuration, starts Docker Desktop if needed, waits for the dedicated infrastructure, and starts the backend and frontend in the background. It prints the application URL after health checks. Existing healthy IDEA instances are reused and remain under IDEA's control.

```powershell
.\dev.cmd status  # Health and whether each application is launcher-owned.
.\dev.cmd stop    # Stop only launcher-owned applications; retain infrastructure/data.
```

Logs and process metadata are in the ignored `.learning/` directory. Check `backend.stdout.log`, `backend.stderr.log`, `frontend.stdout.log` and `frontend.stderr.log` if a background startup fails. If an occupied port does not pass this project's health check, inspect it rather than starting another copy. For debugging, stop the launcher-owned backend first, then use the IDEA run configuration. `stop` leaves external/IDEA processes alone.

The separate commands below remain available when you want to inspect each step:

```powershell
.\dev.cmd init
.\dev.cmd doctor
.\dev.cmd infra
```

On a fresh clone, `init` creates the ignored local `.env` from `.env.learning.example`, generates local random credentials and an encryption key, and leaves the model key empty. It also creates the frontend proxy configuration if missing. Existing configuration files are preserved, keeping their credentials consistent with persistent local data. `init` requires neither Java nor Docker.

After `init` and `infra`, use two terminals:

```powershell
# Terminal 1: Java backend; Ctrl+C stops it.
.\dev.cmd backend
```

```powershell
# Terminal 2: React frontend; Ctrl+C stops it.
.\dev.cmd frontend
```

- Application: <http://localhost:15173>
- Backend: <http://localhost:18080>
- PostgreSQL: `localhost:15432`
- Redis: `localhost:16379`
- RustFS API: `localhost:19000`; console: <http://localhost:19001>

This machine uses `FRONTEND_PORT=15173` in the ignored root `.env`: Windows reserves the range 5160–5259, including 5173. The launcher's default remains 5173 when no override is set. Follow the URL printed by the launcher; keep any separate frontend/IDEA configuration consistent. The backend port comes from `SERVER_PORT`.

The dedicated `compose.learning.yml` uses the Compose project `interview-guide-learning` and separate ports/data volumes. Its connection settings are stored in the ignored local `.env`. Runtime logs and other local state belong in the ignored `.learning/` directory.

```powershell
.\dev.cmd check       # Compile Java, then run the TypeScript/Vite build.
.\dev.cmd stop-infra  # Stop only this project's infrastructure; retain its data.
```

Docker Desktop must be running for infrastructure commands. The frontend command requires installed dependencies (`pnpm.cmd install --frozen-lockfile` in `frontend/`). The `check` command verifies compilation and the frontend build; it does not claim that the full test suite passes. The existing backend test profile needs a separate configuration review before using `:app:test` as a learning checkpoint. Tests that require Redis also need the infrastructure running.

## IntelliJ IDEA

Open the repository root as a Gradle project. Set Project SDK and Gradle JVM to JDK 25, and use the Gradle Wrapper. On this machine, JDK 25 is installed under `C:\Program Files\Eclipse Adoptium\jdk-25.0.4.7-hotspot`; choose that installation through IDEA's SDK settings if it is not listed.

Start Docker Desktop and run `.\dev.cmd infra` in IDEA's terminal. Then select the shared **Backend (Learning - No AI)** run configuration and click Run. This runs `:app:bootRun`, which loads the root `.env`, and supplies the same temporary speech startup arguments as the command-line launcher. Running `App.main` directly does not automatically load the root `.env`.

Open another IDEA terminal and run `.\dev.cmd frontend`. The application is at <http://localhost:15173>, and the backend is at <http://localhost:18080>. Stop any previous instance before launching another one on the same port. The backend run configuration does not require an optional frontend plugin; the frontend uses the terminal.

The configuration name **Backend (Learning - No AI)** describes its temporary speech startup arguments. A local chat provider configured in the database still works. When adding a cloud provider, keep its settings consistent with the database as described below. Remove the temporary speech arguments or create a normal `:app:bootRun` run configuration before studying startup speech configuration.

## Starting without a model API key

The development environment can start before a model key is available. `dev.cmd backend` disables opening-audio warmup and, only when the local cloud key is empty, supplies temporary startup-only ASR/TTS placeholder arguments. It does not write a fake key into `.env` or the database.

You can inspect pages and APIs, work on React/TypeScript with fixture data, and run local tests. Real AI features need their corresponding valid providers. The local Qwen chat provider below is now configured without a cloud key; embeddings and speech remain unconfigured. Passing short chat tests does not prove that full resume analysis or multi-turn interviews work reliably.

For an optional cloud comparison later, open <http://localhost:15173/settings>, edit the DashScope provider, save a valid chat model key and test the provider connection. The current default chat provider is local Qwen. The first startup can seed an empty provider in the database: changing only `.env` later does not overwrite that stored chat provider. Use the settings page to update an existing provider.

ASR/TTS are separate speech configurations. Configure them through the voice settings when you are ready to study speech. With this launcher, startup speech credentials follow `AI_BAILIAN_API_KEY`: set a valid shared DashScope key in your local `.env` and restart before relying on startup speech configuration. While that key is empty, the launcher deliberately supplies startup-only placeholders. A chat provider key saved in the database alone does not enable speech.

## Local Qwen through Ollama (verified 2026-11-01)

The existing Ollama service runs at `127.0.0.1:12500`, selected by this machine's `OLLAMA_HOST`; its models are stored under `D:\AI\Ollama\models`. Start Ollama before testing AI features. The project launcher does not start or manage this external service. No model download, Ollama global setting change or backend source change was needed.

Open <http://localhost:15173/settings> to inspect the database-backed provider:

| Setting | Current value |
|---|---|
| Provider ID / default chat | `qwen35-local` |
| Base URL | `http://127.0.0.1:12500/v1` |
| API key field | `ollama` — non-secret local placeholder required by the project |
| Model | `qwen3.5:4b` |
| Temperature | `0.2` |
| Supports embedding | `false` |
| Default embedding provider | `dashscope` — unchanged, without a usable cloud key |

Verified using fictional short input: the cold direct call took about 36 seconds but exhausted its short output budget on reasoning without producing answer text; after increasing the test output budget, a warm direct call returned OK in 1.85 seconds. Other checks passed: project provider connection test, application AI interview-schedule parsing (18.81 seconds), and application JD structured parsing after schema validation/retry (22.61 seconds; six categories). The first JD attempt included Markdown backticks and failed schema validation; the project retry then succeeded. These are sample timings, not performance guarantees. The JD output associated PostgreSQL with the existing `mysql.md` reference: schema acceptance does not establish semantic accuracy.

Ollama reported an active context length of **4096**, despite the model metadata advertising a much larger maximum. Input, tool descriptions, conversation history and output share the runtime budget; long inputs can be truncated. Full resumes and long multi-turn interviews have not been validated. Do not infer that they work from the short samples. No context tuning or explicit thinking control was applied; investigate an isolated model configuration and memory cost before changing `num_ctx` later.

Use this 4B model to learn provider routing, prompts, structured output, timeouts and failure handling. Keep fixture-based tests for deterministic behavior, then evaluate quality with your own small dataset. RAG needs a separate compatible embedding model (current database expects 1024 dimensions); Qwen chat does not provide that configuration. ASR/TTS remain separate speech services. Do not mark RAG or voice lessons complete from these chat tests.

## First learning milestone

Build and explain one complete flow: select a resume, upload it, track analysis state, display the result, and reopen its history. Start with typed fixture data and a single file; then connect the real APIs. For each task, write down the behavior, implement it, check success and failure paths, and make one focused commit with a short explanation of your decisions.
