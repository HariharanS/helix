const labels = {
  idle: ["Idle", "Waiting for Copilot"],
  thinking: ["Thinking", "Reading the thread"],
  tool: ["Tool", "Running a command"],
  pass: ["Done", "Checks passed"],
  fail: ["Needs help", "Review needed"],
};

const root = document.documentElement;
const dot = document.querySelector("[data-state-dot]");
const label = document.querySelector("[data-state-label]");
const bubble = document.querySelector("[data-bubble]");
const buttons = [...document.querySelectorAll("[data-state]")];

function setPetState(state, message) {
  const next = labels[state] ? state : "idle";
  const [stateLabel, defaultMessage] = labels[next];
  root.dataset.state = next;
  dot.dataset.stateDot = next;
  label.textContent = stateLabel;
  bubble.textContent = message || defaultMessage;
  buttons.forEach((button) => {
    button.toggleAttribute("aria-current", button.dataset.state === next);
  });
}

buttons.forEach((button) => {
  button.addEventListener("click", () => setPetState(button.dataset.state));
});

window.setPetState = setPetState;

// Borderless WPF window drag: forward mousedown to the host via postMessage.
// In a normal browser tab `chrome.webview` is undefined and this is a no-op.
document.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage("drag");
  }
});

const demoEnabled = new URLSearchParams(window.location.search).has("demo");

if (demoEnabled) {
  const demo = ["idle", "thinking", "tool", "pass", "idle"];
  let index = 0;
  setPetState(demo[index]);

  setInterval(() => {
    index = (index + 1) % demo.length;
    setPetState(demo[index]);
  }, 2600);
} else {
  setPetState("idle");
}
