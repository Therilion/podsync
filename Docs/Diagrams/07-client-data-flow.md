# Diagrama de Arquitectura del Cliente — Flujo de Datos Interno

> **Referencia TDD:** §6.1.1 Captura de Audio Local, §6.1.2 Buffer y Envío de Chunks, §6.5 Reducción de Ruido (Nivel 1), §6.7.1 Voice Activity Detection

Este diagrama muestra cómo un único stream de `getUserMedia()` alimenta simultáneamente tres subsistemas independientes en el cliente: el SFU (comunicación en vivo), MediaRecorder (grabación local), y el VAD (detección de voz). Además muestra el flujo del Web Worker para envío de chunks.

```mermaid
flowchart TB
    subgraph BROWSER["🌐 NAVEGADOR (Cliente)"]
        direction TB

        MIC["🎤 getUserMedia()<br/>MediaStream (audio)"]

        subgraph AUDIO_PIPELINE["Audio Pipeline (Web Audio API)"]
            direction LR
            AC["AudioContext"]
            SRC["MediaStreamSource"]
            AN["AnalyserNode<br/>(VAD)"]
            SPLIT["MediaStream<br/>(fork)"]
        end

        MIC --> SRC
        SRC --> AN
        SRC --> SPLIT

        subgraph SFU_PATH["Ruta 1: Comunicación en vivo (SFU)"]
            direction TB
            RNN_OPT{{"RNNoise WASM<br/>AudioWorklet<br/>(opcional)"}}
            MS_CLIENT["mediasoup-client<br/>sendTransport.produce()"]
            PRODUCER["Producer<br/>(1 uplink)"]
        end

        SPLIT -->|"audioTrack"| RNN_OPT
        RNN_OPT -->|"audio limpio<br/>(si activado)"| MS_CLIENT
        SPLIT -.->|"audio crudo<br/>(si RNN desactivado)"| MS_CLIENT
        MS_CLIENT --> PRODUCER

        subgraph REC_PATH["Ruta 2: Grabación local"]
            direction TB
            MR["MediaRecorder<br/>audio/webm;codecs=opus<br/>timeslice: 5000ms"]
            CHUNK["ondataavailable<br/>→ Blob (chunk)"]
        end

        SPLIT -->|"audioTrack<br/>(siempre crudo,<br/>sin RNNoise)"| MR
        MR --> CHUNK

        subgraph VAD_PATH["Ruta 3: Detección de Voz (VAD)"]
            direction TB
            RMS["Cálculo RMS<br/>cada 50-100ms"]
            THRESH["Umbral +<br/>hold time 300-500ms"]
            STATE["Estado:<br/>speaking / silent"]
        end

        AN -->|"getByteFrequencyData()"| RMS
        RMS --> THRESH
        THRESH --> STATE

        subgraph WORKER["Web Worker (hilo separado)"]
            direction TB
            BUF["Buffer Local<br/>(array, max 60 chunks)"]
            HEADER["Construir header<br/>40 bytes binario"]
            SEND["Envío WebSocket<br/>(binary frame)"]
            RETRY["Retry con backoff<br/>(5s, 10s, 20s)"]
            ACK_WAIT["Esperar ACK<br/>(timeout 5s)"]
        end

        CHUNK -->|"postMessage"| BUF
        BUF --> HEADER
        HEADER --> SEND
        SEND --> ACK_WAIT
        ACK_WAIT -->|"timeout sin ACK"| RETRY
        RETRY --> SEND
        ACK_WAIT -->|"ACK recibido"| BUF

        subgraph RECV_PATH["Recepción de audio (downlinks del SFU)"]
            direction TB
            CONSUMERS["Consumers<br/>(N-1 downlinks)"]
            AUDIO_EL["<audio> elements<br/>(reproducción)"]
        end

        subgraph UI_LAYER["Capa de UI (React)"]
            direction LR
            AVATAR["Avatares<br/>idle ↔ speaking<br/>(crossfade 150ms)"]
            LEVEL["Indicador<br/>nivel audio"]
            STATUS["Estado:<br/>conexión,<br/>grabación"]
        end

        STATE -->|"vad:state<br/>(via WS)"| AVATAR
        STATE --> LEVEL
        CONSUMERS --> AUDIO_EL
    end

    subgraph SERVER["Servidor"]
        direction LR
        SFU_SERVER["mediasoup<br/>Router + Workers"]
        WS_GW["WebSocket<br/>Gateway"]
        SEAWEED["SeaweedFS"]
    end

    PRODUCER -->|"SRTP/DTLS<br/>(1 uplink)"| SFU_SERVER
    SFU_SERVER -->|"SRTP/DTLS<br/>(N-1 downlinks)"| CONSUMERS
    SEND -->|"WSS<br/>(binary frames)"| WS_GW
    WS_GW -->|"chunk:ack"| ACK_WAIT
    WS_GW --> SEAWEED
    STATE -->|"vad:state<br/>(WS event)"| WS_GW

    style MIC fill:#3b82f6,color:#fff
    style RNN_OPT fill:#f59e0b,color:#000,stroke-dasharray: 5 5
    style SPLIT fill:#6b7280,color:#fff
    style MR fill:#22c55e,color:#fff
    style BUF fill:#a855f7,color:#fff
```

## Puntos clave del diseño

| Aspecto | Detalle |
|---|---|
| **RNNoise solo afecta SFU** | La grabación local siempre captura audio crudo, sin importar si RNNoise está activo. Esto preserva la calidad máxima para post-producción. |
| **Web Worker aislado** | El buffer y envío de chunks operan en un hilo separado para no bloquear el hilo principal (UI + Web Audio API). |
| **VAD usa AnalyserNode nativo** | Sin librerías externas. < 1% CPU. Los eventos se emiten por WebSocket para animar avatares en todos los clientes. |
| **MediaRecorder independiente** | No depende del SFU. Si mediasoup falla, la grabación local continúa sin interrupción. |
| **Un solo getUserMedia()** | Se solicita el micrófono una sola vez. El stream se bifurca a los tres subsistemas sin duplicar la captura. |
