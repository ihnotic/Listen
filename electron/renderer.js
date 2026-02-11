// ============================================================
// DOM elements
// ============================================================

const recordBtn = document.getElementById("record-btn");
const iconMic = document.getElementById("icon-mic");
const iconMicOff = document.getElementById("icon-mic-off");
const iconLoader = document.getElementById("icon-loader");
const statusText = document.getElementById("status-text");
const hotkeyHint = document.getElementById("hotkey-hint");
const transcriptContent = document.getElementById("transcript-content");
const modeSelect = document.getElementById("mode-select");
const hotkeyInput = document.getElementById("hotkey-input");
const deviceSelect = document.getElementById("device-select");
const settingsToggle = document.getElementById("settings-toggle");
const settingsBody = document.getElementById("settings-body");

let modelLoaded = false;
let currentState = "idle";

// ============================================================
// Theme management
// ============================================================

let themePreference = localStorage.getItem("theme") || "system";

async function initTheme() {
  const systemDark = await window.listen.getSystemDark();
  applyTheme(themePreference, systemDark);

  // Update active button
  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.theme === themePreference);
  });
}

function applyTheme(preference, systemDark) {
  let dark;
  if (preference === "system") {
    dark = systemDark;
  } else {
    dark = preference === "dark";
  }

  document.documentElement.classList.toggle("dark", dark);
}

// Theme button clicks
document.querySelectorAll(".theme-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    themePreference = btn.dataset.theme;
    localStorage.setItem("theme", themePreference);

    const systemDark = await window.listen.getSystemDark();
    applyTheme(themePreference, systemDark);

    document.querySelectorAll(".theme-btn").forEach((b) => {
      b.classList.toggle("active", b.dataset.theme === themePreference);
    });
  });
});

// Listen for system theme changes
window.listen.onSystemThemeChanged(async (data) => {
  if (themePreference === "system") {
    applyTheme("system", data.dark);
  }
});

initTheme();

// ============================================================
// Settings panel toggle
// ============================================================

settingsToggle.addEventListener("click", () => {
  settingsToggle.classList.toggle("open");
  settingsBody.classList.toggle("open");
});

// ============================================================
// Record button
// ============================================================

recordBtn.addEventListener("click", () => {
  if (!modelLoaded) return;
  if (currentState === "recording" || currentState === "listening") {
    window.listen.send({ action: "set_active", active: false });
  } else if (
    currentState === "ready" ||
    currentState === "muted" ||
    currentState === "stopped"
  ) {
    window.listen.send({ action: "set_active", active: true });
  }
});

// ============================================================
// Icon management
// ============================================================

function showIcon(which) {
  iconMic.classList.toggle("hidden", which !== "mic");
  iconMicOff.classList.toggle("hidden", which !== "mic-off");
  iconLoader.classList.toggle("hidden", which !== "loader");
}

// ============================================================
// Status updates
// ============================================================

function setStatus(state, text) {
  currentState = state;
  statusText.textContent = text;

  // Update button state
  recordBtn.className = "record-btn";
  recordBtn.classList.add(state);

  // Update icon
  switch (state) {
    case "recording":
    case "listening":
      showIcon("mic");
      break;
    case "muted":
    case "ready":
    case "stopped":
      showIcon("mic-off");
      break;
    case "loading":
      showIcon("loader");
      break;
    case "error":
      showIcon("mic-off");
      break;
    default:
      showIcon("mic");
  }
}

// ============================================================
// Transcription display
// ============================================================

function addTranscription(text) {
  const empty = transcriptContent.querySelector(".empty-state");
  if (empty) empty.remove();

  const line = document.createElement("div");
  line.className = "transcript-line";
  line.textContent = text;
  transcriptContent.appendChild(line);

  const transcript = document.getElementById("transcript");
  transcript.scrollTop = transcript.scrollHeight;
}

// ============================================================
// Backend message handler
// ============================================================

window.listen.onMessage((msg) => {
  switch (msg.type) {
    case "state":
      handleState(msg);
      break;
    case "transcription":
      addTranscription(msg.text);
      break;
    case "model_loading":
      setStatus("loading", `Loading model...`);
      break;
    case "model_loaded":
      modelLoaded = true;
      setStatus("ready", "Model loaded");
      window.listen.send({ action: "start" });
      break;
    case "status":
      setStatus("loading", msg.message);
      break;
    case "devices":
      populateDevices(msg.devices);
      break;
    case "error":
      setStatus("error", msg.message);
      console.error("Backend error:", msg.message);
      break;
  }
});

function handleState(msg) {
  if (msg.mode) {
    modeSelect.value = msg.mode;
  }

  if (msg.hotkey) {
    hotkeyInput.value = msg.hotkey;
    hotkeyHint.textContent = msg.hotkey;
    hotkeyHint.classList.add("visible");
  }

  if (msg.state) {
    switch (msg.state) {
      case "idle":
        setStatus("loading", "Initializing...");
        window.listen.send({ action: "get_devices" });
        window.listen.send({ action: "download_model" });
        break;
      case "ready":
        setStatus("ready", "Ready");
        break;
      case "recording":
        setStatus("recording", "Recording...");
        break;
      case "listening":
        setStatus("listening", "Listening...");
        break;
      case "muted":
        setStatus("muted", "Muted");
        break;
      case "stopped":
        setStatus("ready", "Stopped");
        break;
      case "quit":
        setStatus("ready", "Disconnected");
        break;
    }
  }
}

// ============================================================
// Device dropdown
// ============================================================

function populateDevices(devices) {
  deviceSelect.innerHTML = '<option value="">System Default</option>';
  for (const dev of devices) {
    const option = document.createElement("option");
    option.value = dev.index;
    option.textContent = dev.name;
    deviceSelect.appendChild(option);
  }
}

// ============================================================
// Settings event listeners
// ============================================================

modeSelect.addEventListener("change", () => {
  window.listen.send({ action: "set_mode", mode: modeSelect.value });
});

hotkeyInput.addEventListener("click", () => {
  hotkeyInput.removeAttribute("readonly");
  hotkeyInput.value = "";
  hotkeyInput.placeholder = "Press a key combo...";
});

hotkeyInput.addEventListener("keydown", (e) => {
  e.preventDefault();

  const parts = [];
  if (e.ctrlKey) parts.push("ctrl");
  if (e.shiftKey) parts.push("shift");
  if (e.altKey) parts.push("alt");
  if (e.metaKey) parts.push("cmd");

  const key = e.key.toLowerCase();
  if (!["control", "shift", "alt", "meta"].includes(key)) {
    parts.push(key === " " ? "space" : key);
  }

  if (parts.length >= 2) {
    const hotkey = parts.join("+");
    hotkeyInput.value = hotkey;
    hotkeyInput.setAttribute("readonly", "");
    hotkeyInput.placeholder = "Press keys...";
    window.listen.updateHotkey(hotkey);
    hotkeyInput.blur();
  }
});

hotkeyInput.addEventListener("blur", () => {
  hotkeyInput.setAttribute("readonly", "");
  hotkeyInput.placeholder = "Press keys...";
});

deviceSelect.addEventListener("change", () => {
  const val = deviceSelect.value;
  const device = val === "" ? null : parseInt(val, 10);
  window.listen.send({ action: "set_device", device });

  if (modelLoaded) {
    window.listen.send({ action: "stop" });
    setTimeout(() => {
      window.listen.send({ action: "start" });
    }, 500);
  }
});
