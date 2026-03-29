import "./styles.css";

const appLinks = {
  ios:    "https://apps.apple.com/in/app/icodex/id6760627147",
  dmg:    "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.dmg",
  appZip: "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.app.zip",
  sha256: "https://github.com/adidshaft/iCodex/releases/download/main-build/SHA256SUMS.txt",
};

const githubReleaseApi =
  "https://api.github.com/repos/adidshaft/iCodex/releases/tags/main-build";

const supabaseConfig = {
  url:     import.meta.env.VITE_SUPABASE_URL     ?? "",
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY ?? "",
};

const releaseMeta = {
  version:     "2.1.0",
  minimumMacOS:"12+",
  dmgChecksum: "DMG  Loading...",
  appChecksum: "ZIP  Loading...",
};

/* ── hydrate links ────────────────────────────────────────────── */

for (const el of document.querySelectorAll("[data-build-version]"))
  el.textContent = releaseMeta.version;

for (const el of document.querySelectorAll("[data-min-macos]"))
  el.textContent = releaseMeta.minimumMacOS;

const dmgEl = document.querySelector("[data-dmg-checksum]");
if (dmgEl) dmgEl.textContent = releaseMeta.dmgChecksum;

const appEl = document.querySelector("[data-app-checksum]");
if (appEl) appEl.textContent = releaseMeta.appChecksum;

const releaseTagEl = document.querySelector("[data-release-tag]");
const releaseNameEl = document.querySelector("[data-release-name]");
const releaseDateEl = document.querySelector("[data-release-date]");
const releaseNotesEl = document.querySelector("[data-release-notes]");

const stripMarkdown = (value) =>
  value
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_>#]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const summarizeReleaseBody = (body) => {
  if (!body) return [];

  const bulletNotes = body
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => /^[-*]\s+/.test(line))
    .map((line) => stripMarkdown(line.replace(/^[-*]\s+/, "")))
    .filter((line) => line.length > 12);

  if (bulletNotes.length >= 2) return bulletNotes.slice(0, 2);

  const paragraphNotes = body
    .split("\n")
    .map((line) => stripMarkdown(line))
    .filter((line) => line.length > 32);

  return [...bulletNotes, ...paragraphNotes].slice(0, 2);
};

const renderReleaseNotes = (notes) => {
  if (!releaseNotesEl) return;
  releaseNotesEl.innerHTML = "";

  for (const note of notes) {
    const item = document.createElement("li");
    item.textContent = note;
    releaseNotesEl.appendChild(item);
  }
};

const extractReleaseMetadata = (release) => {
  const combinedText = [release?.name, release?.body]
    .filter(Boolean)
    .join("\n");

  const versionMatch =
    combinedText.match(/(?:^|\n)Version:\s*`?([^\n`]+)`?/i) ||
    combinedText.match(/\bv(\d+(?:\.\d+){1,3}(?:[-+.\w]+)?)\b/i);
  const minimumMacOSMatch = combinedText.match(
    /(?:^|\n)Minimum macOS:\s*`?([^\n`]+)`?/i,
  );

  return {
    version: versionMatch?.[1]?.trim() || null,
    minimumMacOS: minimumMacOSMatch?.[1]?.trim() || null,
  };
};

const hydrateDownloadLinks = () => {
  for (const el of document.querySelectorAll("[data-link]")) {
    const key = el.dataset.link;
    if (key && appLinks[key]) el.href = appLinks[key];
  }
};

hydrateDownloadLinks();

const dropdowns = [...document.querySelectorAll(".dropdown")];

const closeDropdowns = () => {
  for (const dropdown of dropdowns) {
    dropdown.classList.remove("open");
    const trigger = dropdown.querySelector(".dropdown-toggle");
    if (trigger) trigger.setAttribute("aria-expanded", "false");
  }
};

for (const dropdown of dropdowns) {
  const trigger = dropdown.querySelector(".dropdown-toggle");
  if (!trigger) continue;

  trigger.addEventListener("click", (event) => {
    event.preventDefault();
    const willOpen = !dropdown.classList.contains("open");
    closeDropdowns();
    if (willOpen) {
      dropdown.classList.add("open");
      trigger.setAttribute("aria-expanded", "true");
    }
  });
}

document.addEventListener("click", (event) => {
  if (!event.target.closest(".dropdown")) closeDropdowns();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeDropdowns();
});

const hydrateLatestRelease = async () => {
  if (!releaseNameEl || !releaseDateEl || !releaseNotesEl) return;

  try {
    const response = await fetch(githubReleaseApi, {
      headers: {
        Accept: "application/vnd.github+json",
      },
    });

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const release = await response.json();
    const metadata = extractReleaseMetadata(release);
    const notes = summarizeReleaseBody(release.body);
    const publishedText = release.published_at
      ? new Date(release.published_at).toLocaleDateString(undefined, {
          year: "numeric",
          month: "short",
          day: "numeric",
        })
      : null;

    if (release.tag_name && releaseTagEl) {
      releaseTagEl.textContent = release.tag_name;
    }

    if (metadata.version) {
      releaseMeta.version = metadata.version;
      for (const el of document.querySelectorAll("[data-build-version]")) {
        el.textContent = releaseMeta.version;
      }
    }

    if (metadata.minimumMacOS) {
      releaseMeta.minimumMacOS = metadata.minimumMacOS;
      for (const el of document.querySelectorAll("[data-min-macos]")) {
        el.textContent = releaseMeta.minimumMacOS;
      }
    }

    if (release.name) {
      releaseNameEl.textContent = release.name;
    } else if (release.tag_name) {
      releaseNameEl.textContent = `Latest release: ${release.tag_name}`;
    }

    releaseDateEl.textContent = publishedText
      ? `Published ${publishedText}`
      : "Live on GitHub Releases";

    renderReleaseNotes(
      notes.length > 0
        ? notes
        : [
            "Fresh updates are live for the iPhone app and the Mac connector.",
            "Use the download buttons above to grab the newest release build.",
          ],
    );

    if (Array.isArray(release.assets)) {
      const dmgAsset = release.assets.find((asset) =>
        /\.dmg$/i.test(asset?.name || ""),
      );
      const appZipAsset = release.assets.find((asset) =>
        /\.app\.zip$/i.test(asset?.name || ""),
      );
      const checksumAsset = release.assets.find((asset) =>
        /sha256sums\.txt$/i.test(asset?.name || ""),
      );

      if (dmgAsset?.browser_download_url) appLinks.dmg = dmgAsset.browser_download_url;
      if (appZipAsset?.browser_download_url) {
        appLinks.appZip = appZipAsset.browser_download_url;
      }
      if (checksumAsset?.browser_download_url) {
        appLinks.sha256 = checksumAsset.browser_download_url;
      }

      hydrateDownloadLinks();
      hydrateChecksums();
    }
  } catch (error) {
    console.error("Failed to load rolling release:", error);
    if (releaseTagEl) releaseTagEl.textContent = "main-build";
    releaseNameEl.textContent = "Newest iCodex build is live";
    releaseDateEl.textContent =
      "The download buttons above always point to the latest release.";
    renderReleaseNotes([
      "Fresh updates ship through the latest GitHub release for the iPhone app and the Mac connector.",
      "If GitHub is unavailable right now, the page falls back to the rolling release download links automatically.",
    ]);
  }
};

async function hydrateChecksums() {
  try {
    const response = await fetch(appLinks.sha256, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const text = await response.text();
    const lines = text
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);

    const dmgLine = lines.find((line) => line.endsWith("release/iCodex-Connect.dmg"));
    const appLine = lines.find((line) => line.endsWith("release/iCodex-Connect.app.zip"));

    if (dmgEl && dmgLine) {
      const [hash] = dmgLine.split(/\s+/);
      dmgEl.textContent = `DMG  ${hash}`;
    }

    if (appEl && appLine) {
      const [hash] = appLine.split(/\s+/);
      appEl.textContent = `ZIP  ${hash}`;
    }
  } catch (error) {
    console.error("Failed to load release checksums:", error);
    if (dmgEl) dmgEl.textContent = "DMG  See release SHA256SUMS";
    if (appEl) appEl.textContent = "ZIP  See release SHA256SUMS";
  }
}

hydrateChecksums();
hydrateLatestRelease();

/* ── copy ios link ────────────────────────────────────────────── */
const copyIosLinkBtn = document.getElementById("copy-ios-link");
if (copyIosLinkBtn) {
  copyIosLinkBtn.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(appLinks.ios);
      const originalText = copyIosLinkBtn.textContent;
      copyIosLinkBtn.textContent = "Copied!";
      setTimeout(() => {
        copyIosLinkBtn.textContent = originalText;
      }, 2000);
    } catch (e) {
      console.error("Failed to copy link:", e);
    }
  });
}

/* ── theme toggle ─────────────────────────────────────────────── */
const THEME_KEY = "icodex-theme";
const html      = document.documentElement;

const savedTheme = localStorage.getItem(THEME_KEY);
const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
const initial    = savedTheme ?? (systemDark ? "dark" : "light");
html.setAttribute("data-theme", initial);

const toggle = document.getElementById("themeToggle");
if (toggle) {
  toggle.addEventListener("click", () => {
    const next = html.getAttribute("data-theme") === "dark" ? "light" : "dark";
    html.setAttribute("data-theme", next);
    localStorage.setItem(THEME_KEY, next);
  });
}

/* ── feedback form — Supabase edge function ───────────────────── */
const feedbackForm   = document.querySelector("[data-feedback-form]");
const feedbackStatus = document.querySelector("[data-feedback-status]");

if (feedbackForm && feedbackStatus) {
  feedbackForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    if (!supabaseConfig.url || !supabaseConfig.anonKey) {
      feedbackStatus.textContent = "Supabase env vars missing.";
      feedbackStatus.dataset.state = "error";
      return;
    }

    const submitBtn = feedbackForm.querySelector('button[type="submit"], .form-btn');
    const data      = new FormData(feedbackForm);

    const payload = {
      category:     data.get("category")    || null,
      name:         data.get("name")        || null,
      email:        data.get("email")       || null,
      message:      data.get("message"),
      pageContext: data.get("pageContext") || "website",
    };

    feedbackStatus.textContent    = "Sending…";
    feedbackStatus.dataset.state  = "pending";
    if (submitBtn) submitBtn.disabled = true;

    try {
      const res = await fetch(`${supabaseConfig.url}/functions/v1/icodex-feedback`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey":        supabaseConfig.anonKey,
          "Authorization": `Bearer ${supabaseConfig.anonKey}`,
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.message || err.error || "Could not send.");
      }

      feedbackForm.reset();
      const ctx = feedbackForm.querySelector('input[name="pageContext"]');
      if (ctx) ctx.value = "support-page";

      feedbackStatus.textContent   = "Sent — thanks.";
      feedbackStatus.dataset.state = "success";
    } catch (err) {
      feedbackStatus.textContent   = err instanceof Error ? err.message : "Something went wrong.";
      feedbackStatus.dataset.state = "error";
    } finally {
      if (submitBtn) submitBtn.disabled = false;
    }
  });
}

/* ── reveal on scroll ────────────────────────────────────────── */
const observerOptions = {
  threshold: 0.1,
  rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('active');
    }
  });
}, observerOptions);

document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
