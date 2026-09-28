// Counts one visit per browser session (POST), later page loads only read (GET).
(async () => {
  const el = document.getElementById("visits");
  let count = null;
  const render = () => {
    el.textContent = count === null ? I18N.t("visitsUnavailable") : I18N.t("visits")(count);
  };
  I18N.onChange(render);
  render();

  const base = window.CLOUDRESUME_API;
  if (!base) return;

  let firstInSession = true;
  try { firstInSession = !sessionStorage.getItem("counted"); } catch { /* storage unavailable */ }

  try {
    const res = await fetch(`${base}/visits`, { method: firstInSession ? "POST" : "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    ({ count } = await res.json());
    try { sessionStorage.setItem("counted", "1"); } catch { /* storage unavailable */ }
  } catch {
    count = null;
  }
  render();
})();
