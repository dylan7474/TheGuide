The Hitchhiker's Guide (Offline AI Node)

"DON'T PANIC"

A project to build a fully offline, handheld encyclopedic assistant inspired by The Hitchhiker's Guide to the Galaxy.

This device runs on a Raspberry Pi Zero 2 W (or equivalent low-resource hardware), providing instant access to the entire text of Wikipedia (~50GB) and using a tiny, quantized AI Language Model (SLM) to summarize articles and answer questions without an internet connection.

🚀 Current Status: Phase 1 (Core Software)

The software stack is fully functional and tested on Debian 13 (Intel VM) and is ready for deployment on ARM64 hardware.

Key Capabilities

Zero Internet Required: All data and intelligence reside locally on the SD card.

Dual Modes:

Fast Mode: Instant text-based reader for Wikipedia articles (formatted for small screens).

AI Mode: Uses llama.cpp to read the article and generate a concise summary or answer specific questions.

Resource Optimized: Designed specifically for the 512MB RAM limit of the Pi Zero 2 W.

Uses a massive 4GB Swap file.

Uses highly quantized GGUF models (Qwen2-0.5B).

Direct memory mapping (mmap) to prevent OOM crashes.

Resilient Updates: Uses zsync to download only the changes when updating the 50GB database, saving bandwidth and time.

🛠️ Installation

Prerequisites

Hardware: Raspberry Pi Zero 2 W (or Debian 13 VM).

Storage: 64GB+ microSD card (High endurance recommended).

OS: Raspberry Pi OS Lite (64-bit) / Debian 13.

Quick Start

Clone or Copy the Setup Script:
Download setup_pi_guide.sh to your home directory.

Make it Executable:

chmod +x setup_pi_guide.sh


Run the Installer (Full Setup):
This will install dependencies, compile the AI engine, configure swap, and download the 50GB Wikipedia database. This takes a long time.

./setup_pi_guide.sh -d


-d: Downloads/Updates the Wikipedia database and AI model.

-n: Launches the Network Configuration wizard (Static IP setup).

📖 Usage

Navigate to the install directory:

cd ~/hhgttg


Mode 1: Fast Reader (Default)

Instant access to knowledge. Browse articles in a clean, scrollable text interface.

./start_guide.sh


Mode 2: AI Guide

Activates the "Neural Brain". The startup takes ~15-30s to load the model into RAM.

./start_guide.sh -ai


Query: Type "Earth" or "Guisborough".

Result: The AI reads the offline article and generates a summary.

🔮 Roadmap (Phase 2: Hardware)

The next phase involves moving from a terminal interface to physical hardware.

Display: Integrate luma.oled drivers for 128x64 or 256x64 OLED screens via SPI/I2C.

Input: Replace input() command with a GPIO-driven menu system (Rotary Encoder or Matrix Keypad).

Power: UPS / LiPo battery management implementation.

Case: 3D printed enclosure.

⚠️ Notes on Performance

First Run: The AI model loading is I/O bound. A slow SD card will make the "Thinking..." phase take longer (up to 30s).

Swap Thrashing: If the system hangs, ensure your Swap file is active (free -h). The Pi Zero 2 W requires swap to run the compiler and the AI model simultaneously.
