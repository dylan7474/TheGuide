AI Agent Configuration

This project uses a "Retrieval Augmented Generation" (RAG) architecture optimized for extreme resource constraints.

The "Guide" Persona

The AI is not designed to "know" everything (which requires massive RAM). Instead, it acts as a Reader/Summarizer.

Role: Librarian & Summarizer.

Goal: Provide concise, factual answers based only on the provided Wikipedia context.

Tone: Helpful, concise, tailored for a traveler.

Model Selection

We strictly use Small Language Models (SLMs) under 1 billion parameters to fit within the 512MB RAM envelope of the Raspberry Pi Zero 2 W.

Model

Parameters

Quantization

Size

RAM Usage

Notes

Qwen2

0.5B

Q4_K_M

~350MB

~400MB

Current Default. Excellent logic for its size.

TinyLlama

1.1B

Q4_K_M

~640MB

~700MB

Requires heavy swap usage. Slower.

Danube3

500M

Q4_K_M

~330MB

~380MB

Fast alternative if Qwen fails.

System Prompt Strategy

The system prompt used in guide.py is engineered to prevent hallucinations by grounding the model in the retrieved context.

<|im_start|>user
Based ONLY on the Context below, answer the Question.
Context: {truncated_wiki_text}

Question: {user_query}

Summarize the answer in one short sentence for a traveler.<|im_end|>
<|im_start|>assistant


Context Management

Truncation: Wikipedia articles can be massive. The script intelligently extracts only the first ~2,000 characters of text (stripping HTML/Tables) to fit the model's context window.

Clean-up: Navigation, citations ([1]), and edit markers are stripped before the AI sees the text to save tokens.
