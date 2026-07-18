# DiffRhythm — AI Music Generation

**Model:** ASLP-lab/DiffRhythm-base  
**Machine:** RTX_3060_image_gen (192.168.0.204)  
**Setup date:** July 17, 2026

---

## Overview

DiffRhythm is the first diffusion-based song generation model capable of creating full-length songs (95s or 285s). It generates vocal music from lyrics (LRC format) + a style prompt (text or reference audio).

- **Architecture:** Latent Diffusion (DiT + CFM + Audio VAE)
- **Paper:** https://arxiv.org/abs/2503.01183
- **HF Space:** https://huggingface.co/spaces/ASLP-lab/DiffRhythm
- **GitHub:** https://github.com/ASLP-lab/DiffRhythm

---

## Hardware

| Component | Detail |
|---|---|
| GPU | NVIDIA GeForce RTX 3060 (12 GB VRAM) |
| Driver | 580.159.03, CUDA 13.0 |
| CPU | 14 cores |
| RAM | 12 GB system |
| OS | Ubuntu (x86_64) |
| User | `image` |

---

## Directory Layout

```
~/diffrhythm_project/
├── diffrhythm_code/          # Cloned from HF Space (ASLP-lab/DiffRhythm)
│   ├── diffrhythm/           # Main package
│   │   ├── model/            # DiT, CFM model definitions
│   │   ├── infer/            # Inference (infer.py, infer_utils.py)
│   │   ├── g2p/              # Grapheme-to-phoneme (tokenizer)
│   │   └── config/           # Model config (config.json)
│   ├── pretrained/           # Downloaded model weights + eval files
│   ├── src/                  # Negative prompt, reference audio examples
│   ├── app.py                # Gradio app (original)
│   ├── diffrhythm_test.py    # 5-second test generation script
│   ├── happy_birthday.py     # Happy birthday song generator
│   └── requirements.txt      # Python deps
├── run_test.sh               # Wrapper: generates 5-second test
└── run_birthday.sh           # Wrapper: generates happy birthday song

~/diffrhythm_env/             # Python 3.12 virtual environment
├── bin/espeak-ng             # espeak-ng binary (text-to-phoneme)
├── lib/                      # Shared libraries for espeak-ng
│   ├── libespeak-ng.so.1
│   ├── libpcaudio.so.0
│   └── libsonic.so.0
└── lib/python3.12/           # All Python packages

~/.cache/huggingface/hub/     # HF model cache (~8 GB)
├── models--ASLP-lab--DiffRhythm-1_2/       # CFM/DiT (2.1 GB)
├── models--ASLP-lab--DiffRhythm-vae/       # Audio VAE (596 MB)
├── models--OpenMuQ--MuQ-MuLan-large/       # Style encoder (2.5 GB)
└── models--OpenMuQ--MuQ-large-msd-iter/    # Eval model (2.5 GB)
```

---

## Model Weights

| Component | HuggingFace Repo | Size | Purpose |
|---|---|---|---|
| CFM / DiT | `ASLP-lab/DiffRhythm-1_2` | 2.1 GB | Main diffusion model (95s songs) |
| Full CFM | `ASLP-lab/DiffRhythm-1_2-full` | ~4 GB | Full model (285s songs) |
| VAE | `ASLP-lab/DiffRhythm-vae` | 596 MB | Audio encoder/decoder |
| MuQ-MuLan | `OpenMuQ/MuQ-MuLan-large` | 2.5 GB | Music style encoder |
| MuQ (eval) | `OpenMuQ/MuQ-large-msd-iter` | 2.5 GB | Quality evaluation model |

**Total download:** ~8 GB  
**VRAM during inference:** ~5-7 GB (fits RTX 3060 12 GB)

---

## Python Environment

- **Python:** 3.12.3
- **PyTorch:** 2.6.0+cu124
- Key packages: `torchaudio 2.6.0`, `transformers 4.49.0`, `gradio 5.20.0`, `x-transformers 2.1.2`, `librosa 0.10.2`, `phonemizer 3.3.0`, `muq 0.1.0`, `onnxruntime 1.20.1`

---

## System Dependencies (espeak-ng)

The tokenizer uses `phonemizer` library which requires `espeak-ng` for text-to-phoneme conversion. Since `sudo` is not available, packages were extracted manually:

```bash
# Packages downloaded and extracted:
apt-get download espeak-ng espeak-ng-data libespeak-ng1 libpcaudio0 libsonic0

# Binary:   ~/diffrhythm_env/bin/espeak-ng
# Libraries: ~/diffrhythm_env/lib/libespeak-ng.so.1  (and deps)
# Data:      ~/.local/share/espeak-ng-data/
```

**Critical env vars** (set in wrapper scripts):
```bash
export LD_LIBRARY_PATH=$HOME/diffrhythm_env/lib
export ESPEAK_DATA_PATH=$HOME/.local/share/espeak-ng-data
export PHONEMIZER_ESPEAK_LIBRARY=$HOME/diffrhythm_env/lib/libespeak-ng.so.1
```

> **Note:** `PHONEMIZER_ESPEAK_LIBRARY` is required because the phonemizer library loads espeak via ctypes, which does NOT respect `LD_LIBRARY_PATH`.

---

## How to Generate Music

### Quick test (5-second clip)
```bash
ssh RTX_3060_image_gen 'bash ~/diffrhythm_project/run_test.sh'
scp RTX_3060_image_gen:~/diffrhythm_project/diffrhythm_code/test_output_5s.wav .
```

### Happy Birthday song
```bash
ssh RTX_3060_image_gen 'bash ~/diffrhythm_project/run_birthday.sh'
scp RTX_3060_image_gen:~/diffrhythm_project/diffrhythm_code/happy_birthday.wav .
```

### Custom song (direct)
```bash
ssh RTX_3060_image_gen
cd ~/diffrhythm_project/diffrhythm_code
export LD_LIBRARY_PATH=$HOME/diffrhythm_env/lib
export ESPEAK_DATA_PATH=$HOME/.local/share/espeak-ng-data
export PHONEMIZER_ESPEAK_LIBRARY=$HOME/diffrhythm_env/lib/libespeak-ng.so.1
$HOME/diffrhythm_env/bin/python3 diffrhythm_test.py \
    --steps 32 \
    --cfg 4.0 \
    --text-prompt "Your style description here" \
    --output my_song.wav
```

### Parameters

| Flag | Default | Range | Description |
|---|---|---|---|
| `--steps` | 32 | 10-100 | Diffusion steps (fewer = faster, more = quality) |
| `--cfg` | 4.0 | 1-10 | CFG strength (higher = stronger style adherence) |
| `--duration` | 95 | 95 or 285 | Song length in seconds |
| `--text-prompt` | "cheerful..." | any text | Music style description |
| `--output` | test_output_5s.wav | path | Output WAV file |

---

## Lyrics Format (LRC)

Lyrics must be in LRC format with timestamps:
```
[mm:ss.xx]Lyric line here
```

Example:
```
[00:04.00] Happy birthday to you
[00:09.00] Happy birthday to you
[00:14.00] Happy birthday dear friend
[00:19.00] Happy birthday to you
```

- Timestamps must be within the song duration (95s or 285s)
- First line should NOT start at 00:00 (leave intro space)
- Lyrics can be English or Chinese
- One line per timestamp

---

## Style Prompt

The style prompt describes the musical style. Use **text** (simplest) or **reference audio**.

**Text examples:**
- "Celebratory upbeat birthday song, piano and light percussion, cheerful and warm"
- "A cheerful upbeat pop melody with piano"
- "Emotional piano ballad, slow tempo, minor key"
- "Indie folk ballad, acoustic guitar, warm vocals"

**Audio prompt:** Provide a reference `.wav` file (1-10 seconds). Not yet implemented in the test scripts.

---

## VRAM Management

The model uses 5-7 GB VRAM during inference. On the RTX 3060 (12 GB):
- Leaves room for other GPU processes (STT at 184 MB)
- If OOM occurs, kill zombie processes:
  ```bash
  pkill -f diffrhythm_test
  nvidia-smi  # verify only expected processes
  ```

---

## Troubleshooting

### "espeak not installed on your system"
- Verify `PHONEMIZER_ESPEAK_LIBRARY` is set to the .so path
- Verify `ESPEAK_DATA_PATH` is set
- Test: `PHONEMIZER_ESPEAK_LIBRARY=~/diffrhythm_env/lib/libespeak-ng.so.1 python3 -c 'from phonemizer.backend import EspeakBackend; EspeakBackend("en-us")'`

### "CUDA out of memory"
- Kill zombie processes: `pkill -f diffrhythm`
- Check: `nvidia-smi`
- Model alone uses ~5.5 GB; leave at least 7 GB free

### SSH drops during generation
- Normal under heavy GPU load; process may continue on remote
- Check output: `ls -la ~/diffrhythm_project/diffrhythm_code/*.wav`
- Use tmux for long generations: `tmux new -s dr 'bash ~/diffrhythm_project/run_test.sh'`

### ONNX model error "InvalidProtobuf"
- Git LFS pointer file instead of actual model
- Re-download: `curl -L -o diffrhythm/g2p/sources/g2p_chinese_model/poly_bert_model.onnx 'https://huggingface.co/spaces/ASLP-lab/DiffRhythm/resolve/main/diffrhythm/g2p/sources/g2p_chinese_model/poly_bert_model.onnx'`

---

## Performance

| Operation | Time |
|---|---|
| Model loading (all weights) | ~18 seconds |
| Generation (32 steps, 95s song) | ~21 seconds |
| Generation (32 steps, 285s song) | ~60 seconds |
| Total (load + generate 95s) | ~40 seconds |

Times measured on RTX 3060 (12 GB VRAM).

---

## REST API

A FastAPI server keeps the model loaded in GPU memory and exposes a simple REST API.

### Starting the server
```bash
# On the remote machine (auto-starts in tmux):
ssh RTX_3060_image_gen 'tmux new-session -d -s diffrhythm_api "bash ~/diffrhythm_project/start_server.sh"'

# Check status:
ssh RTX_3060_image_gen 'tmux capture-pane -t diffrhythm_api -p -S -5'
```

### SSH Tunnel (for local access)
The remote is on a private subnet. Use SSH port forwarding for local dev:
```bash
ssh -f -N -L 8765:localhost:8765 RTX_3060_image_gen
# Now access at http://localhost:8765  (local dev)
# or via the public URL: https://song.npro.ai
```

> **Two URLs, same API:**
> - `https://song.npro.ai` — public production URL
> - `http://localhost:8765` — local dev via SSH tunnel (requires tunnel to be active)

###
### Endpoints

All examples use the public URL. For local dev, replace `https://song.npro.ai` with `http://localhost:8765`.

#### `GET /health`
Check if the server and model are ready.
```bash
curl https://song.npro.ai/health
# or locally: curl http://localhost:8765/health
```
Response:
```json
{
  "status": "ok",
  "model_loaded": true,
  "load_time_seconds": 17.6,
  "device": "cuda",
  "gpu_name": "NVIDIA GeForce RTX 3060",
  "gpu_memory_free_mb": 5541
}
```

#### `POST /music/generate`
Generate music from a text prompt.
```bash
curl -X POST https://song.npro.ai/music/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "happy birthday to you", "duration": 10, "steps": 32}' \
  -o output.wav

# Local dev:
curl -X POST http://localhost:8765/music/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "happy birthday to you", "duration": 10, "steps": 32}' \
  -o output.wav
```

> The legacy `/generate` endpoint also works and is kept for backward compatibility.

**Request body:**
| Field | Type | Default | Description |
|---|---|---|---|
| `prompt` | string | *(required)* | Text for lyrics + style detection (1-500 chars) |
| `duration` | float | 10.0 | Output duration in seconds (5-30) |
| `steps` | int | 32 | Diffusion steps (10-100, fewer = faster) |

**Response:** WAV audio file (44100 Hz, 16-bit stereo).

**Response headers:**
- `X-Generation-Time`: diffusion time in seconds
- `X-Total-Time`: total request time
- `X-Duration-Seconds`: output duration
- `X-Style-Prompt`: auto-detected style description

### Style Detection
The API auto-detects musical style from keyword in the prompt:
- "happy", "birthday", "celebrate" → upbeat piano
- "sad", "melancholy", "rain" → emotional ballad
- "epic", "hero", "battle" → orchestral cinematic
- "chill", "relax", "calm" → ambient
- "dance", "beat", "energy" → electronic
- "love", "romantic", "sweet" → acoustic romantic

### Python client example
```python
import requests

resp = requests.post(
    "https://song.npro.ai/music/generate",
    json={"prompt": "summer breeze and sunshine", "duration": 10}
)
with open("song.wav", "wb") as f:
    f.write(resp.content)
print(f"Generated {resp.headers['X-Duration-Seconds']}s in {resp.headers['X-Total-Time']}s")
```

### Running the test suite
```bash
cd /Users/otto/temp/gpu
python3 test_api.py                    # run all tests
python3 test_api.py --prompt "epic" --duration 8 --steps 20  # single test
```
Tests run 5 generations with different prompts and validate WAV output, style detection, and timing.

### Verified test results (2026-07-18)
| Prompt | Style Detected | Duration | Gen Time | Status |
|---|---|---|---|---|
| hello world | melodic piano/strings | 5s | 12.1s | ✅ |
| summer breeze and sunshine | melodic piano/strings | 10s | 18.6s | ✅ |
| happy birthday celebration | upbeat celebratory piano | 8s | 18.7s | ✅ |
| epic battle victory | orchestral cinematic | 10s | 18.7s | ✅ |
| peaceful garden morning | chill ambient | 8s | 12.3s | ✅

---

## Files

| File | Local Path | Remote Path |
|---|---|---|
| Test script | `/Users/otto/temp/gpu/diffrhythm_test.py` | `~/diffrhythm_project/diffrhythm_code/diffrhythm_test.py` |
| Birthday script | `/Users/otto/temp/gpu/happy_birthday.py` | `~/diffrhythm_project/diffrhythm_code/happy_birthday.py` |
| API server | `/Users/otto/temp/gpu/server.py` | `~/diffrhythm_project/diffrhythm_code/server.py` |
| API test suite | `/Users/otto/temp/gpu/test_api.py` | — |
| Server launcher | — | `~/diffrhythm_project/start_server.sh` |
| Test output | `/Users/otto/temp/gpu/test_output_5s.wav` | `~/diffrhythm_project/diffrhythm_code/test_output_5s.wav` |
| Birthday output | `/Users/otto/temp/gpu/happy_birthday.wav` | `~/diffrhythm_project/diffrhythm_code/happy_birthday.wav` |
| API test output | `/Users/otto/temp/gpu/hello_world_api.wav` | — |
