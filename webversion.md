The Hitchhiker's Guide to the Galaxy (Simulator)

Don't Panic.

A web-based simulation of the iconic device from Douglas Adams' The Hitchhiker's Guide to the Galaxy. This application functions as a real encyclopedia, pulling live data from Wikipedia and—optionally—using a local AI model to rewrite entries in the cynical, humorous voice of the Guide.

🌌 Features

Authentic Retro Design: Vector-style graphics, glowing green CRT aesthetics, and the classic "DON'T PANIC" boot screen.

Live Data: Queries the Wikipedia API for real-time information on almost any topic.

Dual Modes:

AI ONLINE: Fetches facts from Wikipedia, then uses a local LLM to rewrite them into a short, witty, Douglas Adams-style entry.

AI BYPASSED: Displays the raw archival data (Wikipedia intro) directly.

Responsive Interface: Works on Desktop and features a specific Portrait Mode for iPads/Tablets with a larger, touch-friendly keyboard.

Audio Synthesis: Procedural typing sounds and beeps (includes an audio-unlock engine for iOS devices).

Smart Interactions:

Physical and On-screen keyboard support.

Space bar interrupts text generation (for rapid searching).

Auto-scrolling text display.

🚀 Getting Started

1. Prerequisites

A modern web browser (Chrome, Firefox, Safari, Edge).

Python (or any method to spin up a simple local web server).

(Optional) Ollama installed locally for AI features.

2. Installation

Download hitchhikers_guide.html.

Place it in a folder on your computer.

3. Running the Guide

Crucial: Due to browser security policies (CORS), this application cannot connect to Wikipedia or Ollama if you simply double-click the HTML file (file:// protocol). You must run it via a local web server.

Using Python (Recommended):

Open your terminal/command prompt.

Navigate to the folder containing the file.

Run:

python -m http.server


Open your browser and go to http://localhost:8000.

🧠 Setting up the AI (Ollama)

To enable the "AI ONLINE" mode where the Guide writes its own entries, you need Ollama running locally.

Install Ollama: Download from ollama.com.

Pull the Model: The Guide is configured to use gemma3:270m (a fast, lightweight model). Open your terminal and run:

ollama pull gemma3:270m


(Note: You can change the model in the config object inside the HTML file if you prefer another).

Run with CORS Enabled: Browsers block web pages from talking to local servers unless permitted. Stop Ollama if it's running, and restart it with this specific environment variable:

Mac/Linux:

OLLAMA_ORIGINS="*" ollama serve


Windows (PowerShell):

$env:OLLAMA_ORIGINS="*"; ollama serve


Connect: Open the Guide in your browser. The "LINK" light on the bezel should turn Green.

🎮 Controls

Keyboard: Type to enter queries.

Enter: Search.

Space: Stop current text output / Type space.

Backspace: Delete.

AI Toggle (Keyboard Button): Switches between:

Green: AI Mode (Summarized, funny).

Grey: Bypass Mode (Raw Wikipedia text).

Diagnostics: Click the "SUB-ETHA LINK" panel in the top left to run a system check on your Ollama connection.

📱 iPad / Tablet Usage

The Guide has a specific layout for Portrait mode:

Host the app on your PC/Mac.

Find your PC's local IP address (e.g., 192.168.1.50).

On your iPad, visit http://192.168.1.50:8000.

The Guide detects the hostname automatically and connects to the Ollama instance running on your PC.

Note: Tap anywhere on the screen once to unlock audio on iOS.

🛠 Troubleshooting

Stuck on "Connecting to Sub-Etha...": Check if your internet connection is active (needed for Wikipedia).

"Error: Deep Thought Generation Failed":

Is Ollama running?

Did you set OLLAMA_ORIGINS="*"?

Did you pull the correct model (gemma3:270m)?

Click the "LINK" light for a diagnostic report.

No Sound on iPad: Ensure your device is not in Silent Mode and tap the screen once to initialize the audio engine.

📜 License

This project is a fan creation inspired by the works of Douglas Adams. Content provided by Wikipedia under CC BY-SA 3.0.

Share and Enjoy.
