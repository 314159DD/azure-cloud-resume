// English/German content. Language comes from the saved choice, then the browser, then English.
const TEXT = {
  en: {
    role: "Full-Stack Engineer · AI Systems & Integration",
    summary:
      "Full-stack engineer in Berlin. I build AI systems and integrations and run them in production. I am currently the only engineer on a legal-tech platform for a German law firm, which includes AI agents, a CRM and email automation. Before that I worked in FinTech as a technical project manager.",
    capabilitiesTitle: "Core capabilities",
    capAiTitle: "AI systems",
    capAi: "LLM orchestration (Azure OpenAI EU, Anthropic), agent tool calling, RAG, human-in-the-loop approval, PII anonymization, cost-tiered model routing",
    capIntTitle: "Integration",
    capInt: "REST APIs, OAuth/OIDC, webhooks, Microsoft Graph, n8n orchestration, job queues, multi-source ingestion",
    capSecTitle: "Security & compliance",
    capSec: "PostgreSQL row-level security, role-based permission models, security audits, GDPR-compliant EU-only architectures",
    capStackTitle: "Stack",
    projectsTitle: "Selected projects",
    p1Title: "Legal-tech platform for a German law firm",
    p1: "The only engineer on a production platform for case management, AI-drafted briefs, dunning, a CRM and AI email handling. The work includes a RAG research agent, approval workflows, Microsoft Graph ingestion, a PII anonymization gateway, the move to dedicated EU servers, CI/CD and incident response.",
    p2Title: "Career intelligence SaaS",
    p2: "Subscription platform shipped solo: Python backend with AI operations, bilingual Next.js frontend, data aggregator with 29 source parsers, cost-tiered LLM evaluation pipeline, Stripe billing with atomic credit deductions.",
    p3Title: "Multi-tenant field sales PWA",
    p3: "Mobile-first B2B app for FMCG field reps replacing Excel campaign tracking, multi-tenant from day one with row-level security.",
    experienceTitle: "Experience",
    e1When: "since Apr 2026",
    e1: "AI Engineer (freelance): architecture, implementation, AI integration and operations of a production legal-tech platform",
    e2When: "since 2024",
    e3When: "2021 to 2024",
    e2: "Independent engineering: 10+ production systems across FinTech, legal-tech, B2B SaaS and DeFi tooling",
    e3: "Technical Project Manager, Better Payment GmbH (FinTech)",
    thisSiteTitle: "About this site",
    thisSite:
      "This page runs on Azure Static Web Apps. The visitor counter below is an Azure Function (Flex Consumption, TypeScript) that writes to Cosmos DB through a managed identity, so it needs no keys. The infrastructure is defined in Bicep and deployed by GitHub Actions over OIDC, with cost caps and a kill switch that stops the API when traffic looks like abuse.",
    visits: (n) => `Visits: ${n.toLocaleString("en-US")}`,
    visitsUnavailable: "Visits: unavailable",
  },
  de: {
    role: "Full-Stack Engineer · KI-Systeme & Integration",
    summary:
      "Full-Stack-Engineer in Berlin. Ich baue KI-Systeme und Integrationen und betreibe sie produktiv. Derzeit bin ich der einzige Entwickler einer Legal-Tech-Plattform für eine deutsche Kanzlei, mit KI-Agenten, CRM und E-Mail-Automatisierung. Davor war ich technischer Projektmanager im FinTech-Bereich.",
    capabilitiesTitle: "Schwerpunkte",
    capAiTitle: "KI-Systeme",
    capAi: "LLM-Orchestrierung (Azure OpenAI EU, Anthropic), Agenten mit Werkzeugen, RAG, Freigabe-Workflows, Anonymisierung personenbezogener Daten, kostengestaffeltes Modell-Routing",
    capIntTitle: "Integration",
    capInt: "REST-APIs, OAuth/OIDC, Webhooks, Microsoft Graph, n8n, Job-Queues, Datenaufnahme aus vielen Quellen",
    capSecTitle: "Sicherheit & Compliance",
    capSec: "Row-Level Security in PostgreSQL, Rollen- und Rechtemodelle, Sicherheitsaudits, DSGVO-konforme Architekturen nur mit EU-Dienstleistern",
    capStackTitle: "Stack",
    projectsTitle: "Ausgewählte Projekte",
    p1Title: "Legal-Tech-Plattform für eine deutsche Kanzlei",
    p1: "Einziger Entwickler einer produktiven Plattform für Aktenverwaltung, KI-Schriftsätze, Mahnwesen, CRM und KI-gestützte E-Mail-Bearbeitung. Dazu gehören ein RAG-Rechercheagent, Freigabe-Workflows, die Anbindung an Microsoft Graph, ein Anonymisierungs-Gateway, der Umzug auf eigene EU-Server, CI/CD und Incident Response.",
    p2Title: "Career-Intelligence-SaaS",
    p2: "Abo-Plattform, allein gebaut: Python-Backend mit KI-Funktionen, zweisprachiges Next.js-Frontend, Datenaggregator mit 29 Quellen, kostengestaffelte LLM-Auswertung, Stripe-Abrechnung mit atomaren Guthabenbuchungen.",
    p3Title: "Mandantenfähige Außendienst-PWA",
    p3: "Mobile B2B-App für den FMCG-Außendienst statt Excel-Listen, von Anfang an mandantenfähig mit Row-Level Security.",
    experienceTitle: "Werdegang",
    e1When: "seit Apr. 2026",
    e1: "AI Engineer (freiberuflich): Architektur, Umsetzung, KI-Integration und Betrieb einer produktiven Legal-Tech-Plattform",
    e2When: "seit 2024",
    e3When: "2021 bis 2024",
    e2: "Selbstständige Entwicklung: über 10 Produktivsysteme in FinTech, Legal-Tech, B2B-SaaS und DeFi",
    e3: "Technical Project Manager, Better Payment GmbH (FinTech)",
    thisSiteTitle: "Über diese Seite",
    thisSite:
      "Diese Seite läuft auf Azure Static Web Apps. Der Besucherzähler unten ist eine Azure Function (Flex Consumption, TypeScript), die per Managed Identity in Cosmos DB schreibt und deshalb keine Schlüssel braucht. Die Infrastruktur ist in Bicep beschrieben und wird von GitHub Actions per OIDC ausgerollt, mit Kostendeckeln und einem Not-Aus, der die API bei Missbrauch stoppt.",
    visits: (n) => `Besuche: ${n.toLocaleString("de-DE")}`,
    visitsUnavailable: "Besuche: nicht verfügbar",
  },
};

const I18N = (() => {
  const listeners = [];
  const readSaved = () => {
    try { return localStorage.getItem("lang"); } catch { return null; }
  };
  const initial = readSaved() ?? (navigator.language?.toLowerCase().startsWith("de") ? "de" : "en");
  let lang = TEXT[initial] ? initial : "en";

  function apply() {
    document.documentElement.lang = lang;
    for (const el of document.querySelectorAll("[data-i18n]")) {
      const value = TEXT[lang][el.dataset.i18n];
      if (typeof value === "string") el.textContent = value;
    }
    for (const btn of document.querySelectorAll("[data-lang]")) {
      btn.setAttribute("aria-pressed", String(btn.dataset.lang === lang));
    }
    listeners.forEach((fn) => fn());
  }

  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-lang]");
    if (!btn || btn.dataset.lang === lang) return;
    lang = btn.dataset.lang;
    try { localStorage.setItem("lang", lang); } catch { /* storage unavailable */ }
    apply();
  });

  apply();
  return {
    t: (key) => TEXT[lang][key],
    onChange: (fn) => listeners.push(fn),
  };
})();
