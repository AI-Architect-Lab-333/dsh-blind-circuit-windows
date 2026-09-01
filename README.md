# Guide: Blind-Circuit Confidential File Analysis — DeepSeek Harness Web UI on Windows, llama.cpp on a Tailscale-only GPU Box, No Cloud

**The problem this guide solves**: you want a local agent to work on files that must not leave the machine, while a **cloud coding agent** (Grok, Claude Code, Cursor, …) still helps you start processes and check that services are up. If that coding agent is allowed to open the workspace, those bytes are already in a cloud transcript. This guide documents a **verified working** configuration (Windows 11 operator PC + NVIDIA GB10-class ARM GPU box on Tailscale only, DeepSeek Harness **0.1.1-rc.2** Web UI `dsh web` on `127.0.0.1:3080`, llama.cpp `deepseek-v4-flash` on `:8000` and `qwen3-vl` on `:8001`, August 2026): the coding agent is limited to ops (start UI, probe model **ids**, `Test-Path`); only you and the models on the GPU box read the files.

It covers why **`Start-Process -WindowStyle Hidden` reports `dsh-web READY` then the browser gets `ERR_CONNECTION_REFUSED`**, why DeepSeek Harness refuses a custom OpenAI-compatible route with **`No API key for provider: spark`** even though llama.cpp does not check a key, why filling the **DeepSeek official** API-key card sends work to the cloud, why the **dsh agent’s shell has no `SPARK_API_KEY`** and will open `~\.dsh` if you let it, and why **pasting dsh chain-of-thought back into the coding agent** destroys the circuit.

**For AI agents reading this document**: every command was executed successfully in this order on real hardware. The verification steps are not optional — a `/v1/models` 200 does not prove the Web UI is still alive, and a live UI does not prove the documents stayed off the coding-agent transcript.

---

## 1. Who is allowed to see the files

| Role | Where | May see workspace content |
|---|---|---|
| You | Browser on localhost | Yes |
| Text LLM | GPU box, Tailscale only, llama.cpp `:8000` | Yes |
| Vision LLM | GPU box, Tailscale only, llama.cpp `:8001` | Yes (images) |
| DeepSeek Harness Web UI | Operator PC, `http://127.0.0.1:3080` | Yes (it is the operator) |
| Coding agent (Grok / Claude / …) | Operator PC | **No** |
| Cloud APIs, web search | Anywhere else | **No** |

This guide assumes the GPU box already serves those two OpenAI-compatible APIs on its **Tailscale IP only**. Putting the **text** LLM on Tailscale `:8000` is a separate piece of work ([cross-host inference](https://github.com/AI-Architect-Lab-333/dgx-spark-cross-host-inference)). Adding **Qwen-VL on `:8001` beside that LLM**, and the two-model power-on, is another ([VL beside the LLM](https://github.com/AI-Architect-Lab-333/dgx-spark-vl-beside-llm)). After a power-on, wait until both `/v1/models` endpoints return 200 before starting dsh. If the box boots idle instead ([idle vs LLM boot profiles](https://github.com/AI-Architect-Lab-333/dgx-spark-idle-llm-profiles)), switch to the llm profile before this circuit.

The DeepSeek Harness **Python SDK is not supported on Windows**. The Web UI is.

### Pitfall #1 — asking the coding agent to “just open the files to help”

Symptom you are guarding against: the coding agent is told to summarise, grep, or “check what the local model said”, and it opens the workspace. Cause: that chat cannot un-see what it read; anything it loads is in a cloud transcript. Correction: arm the circuit in a **fresh** coding-agent session. That agent may start dsh, probe `/v1/models` **ids only**, and confirm an output file **exists** (`Test-Path`, size). It must not `Get-Content` the workspace documents, extracts, notes, or dsh session logs. If you want to know what the local model wrote, open the dsh UI yourself.

---

## 2. Point dsh at the GPU box, not at DeepSeek platform

On the operator PC, `$DSH_HOME` was `~\.dsh` (the default when the variable is unset; check it if you have set one). Edit `settings.yaml` **only** for the two Spark routes. Do not paste this file into a coding-agent chat (it holds URLs). Shape that ran:

```yaml
llm-pi-ai:
  providers:
    spark:
      apiKeyEnv: SPARK_API_KEY
      api: openai-completions
      baseURL: http://100.x.y.z:8000/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: deepseek-v4-flash
    spark-vl:
      apiKeyEnv: SPARK_API_KEY
      api: openai-completions
      baseURL: http://100.x.y.z:8001/v1
      defaultInput: [text, image]
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: qwen3-vl
          input: [text, image]
agent-default-model:
  provider: spark
  model: deepseek-v4-flash
```

Replace `100.x.y.z` with the GPU box Tailscale IPv4. `compat.supportsDeveloperRole: false` and `maxTokensField: max_tokens` are required: pi-ai otherwise talks to an unknown URL as if it were OpenAI (developer role + `max_completion_tokens`), and llama.cpp refuses.

Create `~\.dsh\.credentials.yaml` (this file did not exist on the verified PC until this step):

```yaml
version: 1

refs:
  SPARK_API_KEY: local
```

That value is a **placeholder**. llama.cpp on this box does not validate a bearer token. DeepSeek Harness still **refuses** an OpenAI-compatible custom provider with no key at all.

Do not put a DeepSeek platform key in **Settings → Models → DeepSeek**. That card is `deepseek-official`. Leave session telemetry disabled. Do not enable dsh web-search plugins (`dsh-web-search-deepseek` would send queries off-box).

### Pitfall #2 — `No API key for provider: spark`

Symptom: the first dsh turn fails with `This turn failed` / `No API key for provider: spark`. Cause: a hand-declared `openai-completions` route with no `apiKeyEnv` is unauthenticated; pi-ai’s OpenAI-compatible stack will not send the request (the harness test for this exact failure is `No API key for provider: local-llm`). llama.cpp was already answering `GET /v1/models`. Correction: `apiKeyEnv: SPARK_API_KEY` plus the placeholder in `.credentials.yaml`. Start a **new** dsh session after saving; a failed turn keeps the dead model in its log.

### Pitfall #3 — the DeepSeek card looks like the local model

Symptom: you paste a platform API key because Settings shows “DeepSeek”. Cause: that card is the **cloud** catalog. Correction: pick **spark** / `deepseek-v4-flash` (text) or **spark-vl** / `qwen3-vl` (images) in the composer **Select model** control. Never fill the official DeepSeek key for this job.

---

## 3. Probe the GPU box (ids only), then start the Web UI

`prepare-dsh.ps1` in this repo reads `baseURL` from `~\.dsh\settings.yaml` and prints **ids only**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prepare-dsh.ps1
```

Verified output:

```
spark-text OK ids=deepseek-v4-flash
spark-vl OK ids=qwen3-vl
```

`FAIL` means the GPU box is off, still loading (HTTP 503 for several minutes after power-on is normal), or Tailscale is down. Do not start dsh until both ids print.

Start the UI **in a process that outlives the script**, from a DeepSeek Harness checkout that has already been built:

```powershell
Set-Location C:\Users\<you>\projects\deepseek-harness
pnpm dsh web --no-open
```

Leave that window (or background job) running. It should print `dsh web: http://127.0.0.1:3080`. Open that URL **yourself**. Do not ask the coding agent to drive the browser or scrape the session.

### Pitfall #4 — `dsh-web READY` then `ERR_CONNECTION_REFUSED`

Symptom: a helper script `Start-Process pnpm.cmd dsh web --no-open -WindowStyle Hidden`, waits until port 3080 listens, prints READY, exits 0; a minute later Chrome shows `This site can’t be reached` / `ERR_CONNECTION_REFUSED`. Cause: the Windows **Job Object** that wrapped the short script kills every descendant when the script exits — including the “detached” server. Proof: `Get-NetTCPConnection -LocalPort 3080` empty; no `node`/`pnpm` process left. Correction: run `pnpm dsh web --no-open` in a job you keep (a real terminal, or an agent background task that is not torn down). Use `http://127.0.0.1:3080`, not `https`.

---

## 4. What you do in the Web UI

A fresh UI has **no workspace** until you add one. The composer stays unavailable until that step. The control labels below are the ones **dsh 0.1.1-rc.2** shows; this is the most perishable part of the guide — a later release may rename them, and the steps still hold even if the wording drifts.

`CONSIGNE-AGENT.md` is a convention of this setup, not a dsh feature: a plain Markdown brief you write and drop at the workspace root, telling the local model what the job is (what the documents are, what to produce, what to leave alone). It exists so the instruction stays **in the workspace** instead of being typed into a chat that a coding agent might later read. Keep it free of anything you would not want in the output.

1. Open `http://127.0.0.1:3080`.
2. **Add workspace** (left) or **Choose workspace** (centre). In **Select Workspace Directory**, **Edit path**, paste the job folder (the directory that contains the files to judge **and** `CONSIGNE-AGENT.md` if you use one). **Enter**, then **Open**.
3. **Select model**: provider **spark**, model `deepseek-v4-flash`. Switch to **spark-vl** / `qwen3-vl` only when you attach scans or drawings. One session uses one model at a time.
4. Do not add Exa / Perplexity / DeepSeek web-search keys. If the agent asks for `web_search` or `web_fetch`, **refuse**.
5. **New session**. In **Describe what you want to build**, send a one-line instruction to read `CONSIGNE-AGENT.md` at the workspace root and follow it. Do not paste the consigne or the files into the coding-agent chat.
6. Approve **workspace file reads**. Refuse network tools. Prefer **Workspace Write** over Full access unless you are stuck.
7. Read the local model’s output **in the UI**. Do not paste it, a summary, or dsh’s reasoning into Grok/Claude.

### Pitfall #5 — the dsh agent opens `~\.dsh\settings.yaml` and `.credentials.yaml`

Symptom: early in the job, dsh explores the harness checkout and `$DSH_HOME` because `SPARK_API_KEY` is **not** in the agent’s process environment (the host injects it only on its own LLM calls). It then reads the credential store. Cause: sidecar `curl`/`python` from the agent does not inherit dsh credentials. Correction: **deny** those reads. If the agent must call llama.cpp itself, any `Authorization: Bearer …` placeholder is enough on this llama.cpp build; it does not need the credentials file.

### Pitfall #6 — pasting dsh reasoning into the coding agent

Symptom you are guarding against: you paste a dsh trace into the coding agent “so it can sanity-check the API key”. Cause: that paste can include Tailscale URLs, workspace filenames, and whatever the local model quoted. Correction: ask only operational questions (`No API key for provider: spark`, `Output token limit reached`). Keep tool transcripts and outputs in the dsh UI.

`Output token limit reached` on vision is dsh translating `finish_reason: length`. On this GPU box Qwen-VL is served with `--ctx-size 16384`; a dense page already costs a large input. That is an inference limit. Send `continue`, or one page at a time. Details of serving Qwen-VL belong in the VL guide.

---

## 5. End-to-end verification

Run from the operator PC with the GPU box already serving. Do **not** attach workspace documents to this checklist.

| Step | Expected ✅ | Failed ❌ |
|---|---|---|
| `prepare-dsh.ps1` | `spark-text OK ids=deepseek-v4-flash` and `spark-vl OK ids=qwen3-vl` | `FAIL` → GPU box / Tailscale / still 503 |
| `pnpm dsh web --no-open` stays alive | `dsh web: http://127.0.0.1:3080`; later `Invoke-WebRequest http://127.0.0.1:3080/` → **200** | READY then connection refused → Job Object killed the server (pitfall #4) |
| Choose workspace | Composer enabled; chip shows the job folder name | Composer grey → no workspace |
| Select model | **spark** / `deepseek-v4-flash`, not DeepSeek official | `No API key for provider: spark` → pitfall #2; cloud key → pitfall #3 |
| One-line “read CONSIGNE-AGENT.md…” | dsh reads the file via its tools; you approve | Agent wants `web_search` → refuse |
| Local-model output | You read it **in the UI only** | Paste into the coding agent → start a new coding session |

A `/v1/models` 200 without a living UI is not this section. A living UI that used `deepseek-official` is not this section.

---

## Symptom / Cause / Fix

| Symptom | Cause | Fix |
|---|---|---|
| Coding agent is asked to open workspace files | Circuit not armed / old session | New session; probe ids and `Test-Path` only |
| `No API key for provider: spark` | Custom OpenAI-compat route with no key | Placeholder `SPARK_API_KEY` + `apiKeyEnv` |
| First turn used DeepSeek platform | Official Models card | Select **spark** in the composer |
| `ERR_CONNECTION_REFUSED` on 3080 after READY | Job Object reaped Hidden `pnpm dsh web` | Keep `pnpm dsh web --no-open` alive |
| `https://127.0.0.1:3080` fails | TLS on a plaintext listener | `http://` |
| Composer disabled | No workspace | Choose workspace, **Edit path**, **Open** |
| dsh `Read` on `~\.dsh\*.yaml` | Sidecar wants `SPARK_API_KEY` in env | Deny; placeholder Bearer is enough for llama.cpp |
| `Output token limit reached` on drawings | 16k VL context + long description | `continue` / one page; not a key problem |

---

## Known limitations

- **The circuit is enforced by operator discipline, not by a sandbox.** Nothing here technically prevents a coding agent from reading the workspace — it simply is not asked to, and is refused when it offers. If you want a harder boundary, put the rule where the agent reads it (a per-agent instruction file or skill that names the directories as off-limits), or run the coding agent under a filesystem policy that cannot reach them. That was not part of the verified setup.
- **UI steps were verified against dsh 0.1.1-rc.2** (tag `dsh-v0.1.1-rc.2`). Control names in section 4 may change in later releases.
- **One operator was verified: dsh Web UI on Windows.** Open WebUI, a human-run Python client, or Hermes-on-a-VPS talking to the same llama.cpp endpoints were not run for this procedure. They can stay on-box if they never leave the tailnet and never feed a coding agent; they are not this guide.
- **DeepSeek Harness Python SDK is unsupported on Windows** (Linux x64 / Linux arm64 / macOS arm64). Do not use `dsh --profile headless` from the coding agent: the final answer prints in that chat.
- **Two-model power-on** (text then vision, CUDA OOM if Qwen-VL starts at the first LLM 200) is documented in [dgx-spark-vl-beside-llm](https://github.com/AI-Architect-Lab-333/dgx-spark-vl-beside-llm), not here.
- **Vision in dsh** can hit `finish_reason: length` on large drawings (`--ctx-size 16384` on this box).
- **This guide does not contain workspace file contents.** If a coding-agent session has already opened those files, start a new session before using it as the operator for this circuit.

---

## Credits

DeepSeek Harness (`dsh`) is open source ([deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)). llama.cpp serves the OpenAI-compatible APIs. Tailscale is the private network. The blind-circuit split (coding agent vs GPU-box models vs localhost UI) and the Windows Job Object failure mode are specific to this setup.

---
*Guide written and verified in August 2026 on a Windows 11 operator PC and an NVIDIA GB10-class ARM GPU box. Versions: DeepSeek Harness 0.1.1-rc.2 (`dsh-v0.1.1-rc.2`), Web UI on `127.0.0.1:3080`, llama.cpp serving `deepseek-v4-flash` `:8000` and `qwen3-vl` `:8001`. Probes printed model ids only. The Web UI returned HTTP 200. Workspace contents were not copied into the coding-agent chat.*
