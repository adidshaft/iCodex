import "./styles.css";

const appLinks = {
  ios: "https://apps.apple.com/us/search?term=iCodex",
  dmg: "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.dmg",
  appZip:
    "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.app.zip",
};

const supabaseConfig = {
  url: import.meta.env.VITE_SUPABASE_URL ?? "",
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY ?? "",
};

const releaseMeta = {
  version: "2.1.0",
  minimumMacOS: "12+",
  dmgChecksum:
    "DMG  56bdbe64124374090cce41c79fa3d9e2b9a94b5abc68262a6d63d7c045c0cf0d",
  appChecksum:
    "ZIP  c154c906414afd1cf6a2bce7732f20fe2659154e52f9ce054d5ac7a5ed879141",
};

for (const link of document.querySelectorAll("[data-link]")) {
  const key = link.dataset.link;
  if (!key || !appLinks[key]) continue;
  link.href = appLinks[key];
}

for (const target of document.querySelectorAll("[data-build-version]")) {
  target.textContent = releaseMeta.version;
}

for (const target of document.querySelectorAll("[data-min-macos]")) {
  target.textContent = releaseMeta.minimumMacOS;
}

const dmgChecksum = document.querySelector("[data-dmg-checksum]");
if (dmgChecksum) {
  dmgChecksum.textContent = releaseMeta.dmgChecksum;
}

const appChecksum = document.querySelector("[data-app-checksum]");
if (appChecksum) {
  appChecksum.textContent = releaseMeta.appChecksum;
}

const revealTargets = document.querySelectorAll(".reveal");
const prefersReducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)",
).matches;

if (prefersReducedMotion) {
  revealTargets.forEach((target) => target.classList.add("is-visible"));
} else {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    {
      threshold: 0.15,
    },
  );

  revealTargets.forEach((target) => observer.observe(target));
}

const feedbackForm = document.querySelector("[data-feedback-form]");
const feedbackStatus = document.querySelector("[data-feedback-status]");

if (feedbackForm && feedbackStatus) {
  feedbackForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    if (!supabaseConfig.url || !supabaseConfig.anonKey) {
      feedbackStatus.textContent =
        "Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to enable submissions.";
      feedbackStatus.dataset.state = "error";
      return;
    }

    const submitButton = feedbackForm.querySelector('button[type="submit"]');
    const formData = new FormData(feedbackForm);
    const payload = {
      category: formData.get("category"),
      name: formData.get("name"),
      email: formData.get("email"),
      message: formData.get("message"),
      pageContext: formData.get("pageContext"),
    };

    feedbackStatus.textContent = "Sending...";
    feedbackStatus.dataset.state = "pending";
    if (submitButton) submitButton.disabled = true;

    try {
      const response = await fetch(
        `${supabaseConfig.url}/functions/v1/icodex-feedback`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: supabaseConfig.anonKey,
            Authorization: `Bearer ${supabaseConfig.anonKey}`,
          },
          body: JSON.stringify(payload),
        },
      );

      const result = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(result.error || "Could not send your message.");
      }

      feedbackForm.reset();
      const pageContextInput = feedbackForm.querySelector(
        'input[name="pageContext"]',
      );
      if (pageContextInput) pageContextInput.value = "support-page";
      feedbackStatus.textContent =
        "Thanks. Your note is in and we can review it from Supabase.";
      feedbackStatus.dataset.state = "success";
    } catch (error) {
      feedbackStatus.textContent =
        error instanceof Error ? error.message : "Something went wrong.";
      feedbackStatus.dataset.state = "error";
    } finally {
      if (submitButton) submitButton.disabled = false;
    }
  });
}
